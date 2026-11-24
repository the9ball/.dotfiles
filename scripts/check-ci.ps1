#Requires -Version 7.0
<#
.SYNOPSIS
Builds the Linux CI image and checks this repository in a read-only mount.
.DESCRIPTION
Run with PowerShell 7 and Docker's Linux engine. Returns the build exit code
on build failure, or the container's exit code after running the manual hooks.
A linked worktree is supported by also mounting the shared Git directory.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repositoryPath = Split-Path -Parent $PSScriptRoot
$dockerfilePath = Join-Path $repositoryPath 'Dockerfile.ci'
$imageName = 'dotfiles-ci-checks:local'

$gitDirectory = (git -C $repositoryPath rev-parse --path-format=absolute --git-dir).Trim()
$commonGitDirectory = (git -C $repositoryPath rev-parse --path-format=absolute --git-common-dir).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Cannot resolve the Git directory of $repositoryPath (exit code: $LASTEXITCODE)"
}

$runArguments = @('--rm', '--mount', "type=bind,source=$repositoryPath,target=/workspace,readonly")
# A linked worktree's .git file points to a host path the container cannot resolve.
# Mount the shared Git directory instead and select the worktree's metadata inside it;
# its commondir entry is relative, so it resolves to the mounted shared directory.
$gitDirectoryFull = [IO.Path]::GetFullPath($gitDirectory)
$commonGitDirectoryFull = [IO.Path]::GetFullPath($commonGitDirectory)
if (-not [string]::Equals($gitDirectoryFull, $commonGitDirectoryFull, [StringComparison]::OrdinalIgnoreCase)) {
    $worktreeGitPath = [IO.Path]::GetRelativePath($commonGitDirectoryFull, $gitDirectoryFull)
    if ([IO.Path]::IsPathRooted($worktreeGitPath) -or $worktreeGitPath.StartsWith('..')) {
        throw "The worktree Git directory $gitDirectoryFull is not inside $commonGitDirectoryFull"
    }
    $runArguments += @(
        '--mount', "type=bind,source=$commonGitDirectoryFull,target=/git-common,readonly",
        '--env', ('GIT_DIR=/git-common/' + $worktreeGitPath.Replace('\', '/')),
        '--env', 'GIT_WORK_TREE=/workspace'
    )
}

docker build --file $dockerfilePath --tag $imageName $repositoryPath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker run @runArguments $imageName
exit $LASTEXITCODE

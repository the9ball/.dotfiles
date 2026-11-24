#Requires -Version 7.0
<#
.SYNOPSIS
Builds the Linux CI image and checks this repository in a read-only mount.
.DESCRIPTION
Run with PowerShell 7 and Docker's Linux engine. Returns the build exit code
on build failure, or the container's exit code after running the manual hooks.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repositoryPath = Split-Path -Parent $PSScriptRoot
$dockerfilePath = Join-Path $repositoryPath 'Dockerfile.ci'
$imageName = 'dotfiles-ci-checks:local'

docker build --file $dockerfilePath --tag $imageName $repositoryPath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker run --rm --mount "type=bind,source=$repositoryPath,target=/workspace,readonly" $imageName
exit $LASTEXITCODE

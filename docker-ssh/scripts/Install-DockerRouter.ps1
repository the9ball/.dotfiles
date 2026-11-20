#requires -Version 7.5
<# .SYNOPSIS Checks or explicitly installs a router package; publication is the last operation and never removes an existing gateway. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageRoot, [switch]$Execute,
    [string]$DestinationRoot = (Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerRouter'))
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows required.' }
if (-not [IO.Path]::IsPathFullyQualified($PackageRoot) -or -not [IO.Path]::IsPathFullyQualified($DestinationRoot)) { throw 'Absolute package and destination paths required.' }
$sourceRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $sourceRoot 'chezmoi/AppData/Local/Dotfiles/DockerSsh/Get-TpmDockerEnvironment.ps1') -DefinitionsOnly
$destination = [IO.Path]::GetFullPath($DestinationRoot)
$expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerRouter'))
if ($destination -ine $expected) { throw 'Only the fixed router installation is supported.' }
$package = [IO.Path]::GetFullPath($PackageRoot)
$names = @('bin/docker.exe', 'payload/Enter-DockerSshEnvironment.ps1', 'payload/Get-TpmDockerEnvironment.ps1')
Assert-TpmDeploymentPath -Path (Join-Path $package 'package.json') -PublicLeaf
$manifest = Get-Content -LiteralPath (Join-Path $package 'package.json') -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.Version -ne 1 -or $manifest.Files.Count -ne $names.Count) { throw 'Invalid router package.' }
foreach ($name in $names) {
    $path = Join-Path $package $name
    Assert-TpmDeploymentPath -Path $path -PublicLeaf
    if ($manifest.Files[$name] -cnotmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path).Hash -cne $manifest.Files[$name]) { throw 'Router package hash mismatch.' }
}
$runtime = (Get-Process -Id $PID).Path
Assert-TpmDeploymentPath -Path $runtime -PublicLeaf
$runtimeHash = (Get-FileHash -LiteralPath $runtime).Hash
$payloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($manifest.Files['payload/Enter-DockerSshEnvironment.ps1'] + $manifest.Files['payload/Get-TpmDockerEnvironment.ps1'])))
if (Test-Path -LiteralPath $destination) {
    Assert-TpmDeploymentPath -Path $destination
    $existingPublication = Join-Path $destination 'published'
    if (Test-Path -LiteralPath $existingPublication) {
        Assert-TpmDeploymentPath -Path $existingPublication
        if ([IO.File]::ReadAllText($existingPublication) -cne "1`n") { throw 'Invalid publication retained; no installation changes.' }
    }
    foreach ($name in $names | Where-Object { $_.StartsWith('bin/') }) {
        $installed = Join-Path $destination $name
        if (Test-Path -LiteralPath $installed) {
            Assert-TpmDeploymentPath -Path $installed
            if ((Get-FileHash -LiteralPath $installed).Hash -cne $manifest.Files[$name]) { throw 'Stable gateway upgrade requires a separately approved quiet replacement; no installed binary was changed.' }
        }
    }
}
if (-not $Execute) {
    Write-Output 'Router package check passed; no installation, ACL or publication changes.'
    return
}

function New-RouterPrivateDirectory {
    <# .SYNOPSIS Creates only a new user-private directory and validates existing paths without rewriting their ACL. #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $security = [Security.AccessControl.DirectorySecurity]::new()
        $security.SetOwner($owner)
        $security.SetAccessRuleProtection($true, $false)
        $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        $null = [IO.FileSystemAclExtensions]::CreateDirectory($security, $Path)
    }
    Assert-TpmDeploymentPath -Path $Path
}

$parent = Split-Path $destination -Parent
if (-not (Test-Path -LiteralPath $parent)) { New-RouterPrivateDirectory -Path $parent }
Assert-TpmDeploymentPath -Path $parent -PublicLeaf
New-RouterPrivateDirectory -Path $destination
$claimPath = Join-Path $destination 'install.lock'
if (Test-Path -LiteralPath $claimPath) { Assert-TpmDeploymentPath -Path $claimPath }
$claim = [IO.File]::Open($claimPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $binary = Join-Path $destination 'bin'
    $releases = Join-Path $destination 'releases'
    $payload = Join-Path $releases $payloadHash
    foreach ($directory in @($binary, $releases, $payload)) { New-RouterPrivateDirectory -Path $directory }
    foreach ($name in $names) {
        $target = if ($name.StartsWith('bin/')) { Join-Path $destination $name } else { Join-Path $payload (Split-Path $name -Leaf) }
        if (Test-Path -LiteralPath $target) {
            Assert-TpmDeploymentPath -Path $target
            if ((Get-FileHash -LiteralPath $target).Hash -cne $manifest.Files[$name]) { throw 'Existing router content differs; no overwrite.' }
        } else {
            [IO.File]::Copy((Join-Path $package $name), $target, $false)
            Assert-TpmDeploymentPath -Path $target
        }
    }
    $configuration = [ordered]@{
        Version = 1; Payload = $payloadHash; PowerShellExecutable = $runtime; PowerShellSha256 = $runtimeHash
        SelectorPath = (Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerSsh/ssh-environment.json')
        PublicBootstrapRoot = (Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerSsh')
        Files = @{ 'Enter-DockerSshEnvironment.ps1' = $manifest.Files['payload/Enter-DockerSshEnvironment.ps1']; 'Get-TpmDockerEnvironment.ps1' = $manifest.Files['payload/Get-TpmDockerEnvironment.ps1'] }
    }
    $current = Join-Path $destination 'current.json'
    if (Test-Path -LiteralPath $current) {
        Assert-TpmDeploymentPath -Path $current
        [IO.File]::Copy($current, ($current + '.backup.' + [guid]::NewGuid().ToString('N')), $false)
    }
    $temporary = Join-Path $destination ('current.' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($temporary, ($configuration | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Assert-TpmDeploymentPath -Path $temporary
    [IO.File]::Move($temporary, $current, $true)
    $health = & (Join-Path $binary 'docker.exe') --dotfiles-router-check-staged
    if ($LASTEXITCODE -ne 0 -or $health -cne 'DOTFILES_DOCKER_ROUTER_READY') { throw 'Staged router validation failed; publication unchanged.' }
    $publication = Join-Path $destination 'published'
    if (Test-Path -LiteralPath $publication) {
        Assert-TpmDeploymentPath -Path $publication
        if ([IO.File]::ReadAllText($publication) -cne "1`n") { throw 'Invalid publication retained; no legacy fallback.' }
    } else {
        # CreateNew makes publication atomic with respect to another installer and never retracts prior publication.
        $stream = [IO.File]::Open($publication, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $publicationBytes = [Text.Encoding]::UTF8.GetBytes("1`n")
            $stream.Write($publicationBytes, 0, $publicationBytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
    }
    Write-Output 'Router published; existing panes and processes were not changed. No Docker, TPM or credentials accessed.'
} finally { $claim.Dispose() }

<# .SYNOPSIS Checks or explicitly initializes a private, separate TPM Docker installation; partial state is preserved, never silently repaired. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PackageRoot,
    [Parameter(Mandatory)][string] $DestinationRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string] $InstallationId,
    [Parameter(Mandatory)][ValidateSet('poc','permanent')][string] $Mode,
    [Parameter(Mandatory)][string] $EngineEndpoint,
    [switch] $CheckOnly,
    [switch] $Execute,
    [switch] $AcknowledgePermanent
)
$ErrorActionPreference = 'Stop'
if ($InstallationId -cnotmatch '\A[a-f0-9]{32}\z') { throw 'InstallationId must be exactly 32 lowercase hexadecimal characters.' }
. (Join-Path $PSScriptRoot 'TpmSetupRuntime.ps1')
$Mode = $Mode.ToLowerInvariant()
if (-not $IsWindows -or $PSVersionTable.PSVersion -lt [version]'7.4') { throw 'Windows and PowerShell 7.4+ required.' }
if ($EngineEndpoint -notmatch '^npipe:/{4}\./pipe/[A-Za-z0-9_.-]+$' -or $env:DOCKER_TLS_VERIFY -or $env:DOCKER_CERT_PATH) { throw 'Explicit named-pipe endpoint without inherited TLS required.' }
if (-not [IO.Path]::IsPathFullyQualified($DestinationRoot) -or -not [IO.Path]::IsPathFullyQualified($PackageRoot)) { throw 'Absolute paths required.' }
$destination = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DestinationRoot))
$local = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($env:LOCALAPPDATA))
$expected = if ($Mode -eq 'poc') { Join-Path $local ('docker-ssh-issue142-lab-install-' + $InstallationId) } else { Join-Path $local ('Dotfiles/DockerSsh/Installations/' + $InstallationId) }
if ($destination -ine $expected) { throw 'Destination must match the selected mode and installation ID.' }
if ($Execute -and -not $CheckOnly -and $Mode -eq 'permanent' -and -not $AcknowledgePermanent) { throw 'Explicit permanent initialization acknowledgement required.' }
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User

function Assert-SetupPath {
    <# .SYNOPSIS Checks existing path components against replacement, ACL takeover and reparse traversal before execution. #>
    param([string] $Path, [switch] $Private)
    $trusted = @($owner.Value,'S-1-5-18','S-1-5-32-544',([Security.Principal.NTAccount]::new('NT SERVICE','TrustedInstaller')).Translate([Security.Principal.SecurityIdentifier]).Value)
    $absolute = [IO.Path]::GetFullPath($Path)
    for ($current=$absolute; $current; $current=Split-Path -Parent $current) {
        if (-not (Test-Path -LiteralPath $current)) { continue }
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse path rejected.' }
        $security = Get-Acl -LiteralPath $current
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new($security.Sddl)
        if ($null -eq $raw.DiscretionaryAcl -or $raw.Owner.Value -notin $trusted) { throw 'Unsafe path owner or DACL.' }
        if ($Private -and $current -eq $absolute -and $raw.Owner -ne $owner) { throw 'Private owner required.' }
        foreach ($rule in $security.Access) {
            if ($rule.AccessControlType -ne 'Allow') { continue }
            $sid=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($Private -and $current -eq $absolute -and $sid -ne $owner.Value) { throw 'Private grant required.' }
            $forbidden=[Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
            if (-not ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and $sid -notin $trusted -and ($rule.FileSystemRights -band $forbidden)) { throw 'Replaceable ancestor rejected.' }
        }
    }
}

function New-PrivateSetupDirectory {
    <# .SYNOPSIS Creates a new user-only directory, refusing collisions rather than changing an existing ACL. #>
    param([string] $Path)
    if (Test-Path -LiteralPath $Path) { throw 'Directory collision; no repair performed.' }
    $security=[Security.AccessControl.DirectorySecurity]::new()
    $security.SetOwner($owner)
    $security.SetAccessRuleProtection($true,$false)
    $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    [void][IO.FileSystemAclExtensions]::CreateDirectory($security,$Path)
    Assert-SetupPath -Path $Path -Private
}

function Invoke-SetupChild {
    <# .SYNOPSIS Runs a validated staged binary with fixed public arguments; UI/stall leaves a sticky stop marker and retained partial state. #>
    param([string] $Executable,[string[]] $Arguments)
    Assert-SetupPath -Path $Executable -Private
    $relative = if ([IO.Path]::GetFileName($Executable) -eq 'docker-ssh-tpm-key.exe') { 'key-tool/docker-ssh-tpm-key.exe' } else { 'helper/docker-credential-ssh-tpm.exe' }
    $componentDirectory=Split-Path -Parent $Executable
    foreach ($entry in $manifest.Files.PSObject.Properties | Where-Object { $_.Name.StartsWith(($relative.Split('/')[0] + '/')) }) {
        $file=Join-Path $componentDirectory ([IO.Path]::GetFileName($entry.Name))
        Assert-SetupPath -Path $file -Private
        if ((Get-FileHash -LiteralPath $file).Hash -cne $entry.Value) { throw 'Staged executable changed.' }
    }
    Invoke-TpmSetupProcess -Executable $Executable -Arguments $Arguments -KeyRoot (Join-Path $destination 'key') -InstallationId $InstallationId -EnvironmentValues @{DOCKER_SSH_HELPER_ROOT=(Join-Path $destination 'store');DOCKER_SSH_TPM_BINDING=(Join-Path $destination 'key/key-binding.json')}
}

Assert-SetupPath -Path $destination
$manifestPath=Join-Path $PackageRoot 'package.json'
Assert-SetupPath -Path $manifestPath
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$required=@('helper/docker-credential-ssh-tpm.exe','helper/docker-credential-ssh-tpm.dll','helper/docker-credential-ssh-tpm.deps.json','helper/docker-credential-ssh-tpm.runtimeconfig.json',
    'key-tool/docker-ssh-tpm-key.exe','key-tool/docker-ssh-tpm-key.dll','key-tool/docker-ssh-tpm-key.deps.json','key-tool/docker-ssh-tpm-key.runtimeconfig.json','shell/docker-ssh.bash','shell/Get-TpmDockerEnvironment.ps1')
if ($manifest.Version -ne '0.4.0' -or @($manifest.Files.PSObject.Properties).Count -ne 10 -or @(Compare-Object $required @($manifest.Files.PSObject.Properties.Name)).Count) { throw 'Unsupported package.' }
foreach ($name in $required) {
    $file=Join-Path $PackageRoot $name
    Assert-SetupPath -Path $file
    if ($manifest.Files.$name -notmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $file).Hash -cne $manifest.Files.$name) { throw 'Package hash mismatch.' }
}
$docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop).Source
$runtimes=& dotnet.exe --list-runtimes
if ($LASTEXITCODE -ne 0 -or -not ($runtimes -match '^Microsoft.NETCore.App 10\.')) { throw '.NET 10 runtime required.' }
if (Test-Path -LiteralPath $destination) {
    Assert-SetupPath -Path $destination -Private
    Assert-SetupPath -Path (Join-Path $destination 'settings.json') -Private
    $settings=Get-Content -LiteralPath (Join-Path $destination 'settings.json') -Raw | ConvertFrom-Json
    if ($settings.State -ne 'READY' -or $settings.InstallationId -cne $InstallationId -or $settings.Mode -cne $Mode -or $settings.DockerExecutable -cne $docker -or $settings.HelperVersion -ne '0.4.0' -or $settings.EngineEndpoint -cne $EngineEndpoint) { throw 'Partial or different installation; no new key or repair.' }
    foreach ($name in $required) {
        $relative = if ($name.StartsWith('helper/')) { 'bin/0.4.0/' + [IO.Path]::GetFileName($name) } else { $name }
        $file=Join-Path $destination $relative
        Assert-SetupPath -Path $file -Private
        if ((Get-FileHash -LiteralPath $file).Hash -cne $manifest.Files.$name) { throw 'Installed files differ; no update performed.' }
    }
    if ($Execute -and -not $CheckOnly) { Invoke-SetupChild -Executable (Join-Path $destination 'key-tool/docker-ssh-tpm-key.exe') -Arguments @('inspect',(Join-Path $destination 'key'),$InstallationId,$Mode) }
    Write-Output 'Existing complete installation files match; no rotation or configuration changes.'
    return
}
if ($CheckOnly -or -not $Execute) { Write-Output 'Setup preflight PASS; no directory, key or credential created.'; return }
New-PrivateSetupDirectory -Path $destination
New-PrivateSetupDirectory -Path (Join-Path $destination 'key')
@{Version=1;InstallationId=$InstallationId;Mode=$Mode;State='SETUP_ATTEMPTED';CreatedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'setup-state.json')
foreach ($name in $required) {
    $relative=if ($name.StartsWith('helper/')) { 'bin/0.4.0/' + [IO.Path]::GetFileName($name) } else { $name }
    $target=Join-Path $destination $relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    Copy-Item -LiteralPath (Join-Path $PackageRoot $name) -Destination $target
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $destination 'package.json')
foreach ($name in $required) {
    $relative=if ($name.StartsWith('helper/')) { 'bin/0.4.0/' + [IO.Path]::GetFileName($name) } else { $name }
    $file=Join-Path $destination $relative
    Assert-SetupPath -Path $file -Private
    if ((Get-FileHash -LiteralPath $file).Hash -cne $manifest.Files.$name) { throw 'Staged package changed; no key creation.' }
}
Invoke-SetupChild -Executable (Join-Path $destination 'key-tool/docker-ssh-tpm-key.exe') -Arguments @('create',(Join-Path $destination 'key'),$InstallationId,$Mode)
Copy-Item -LiteralPath (Join-Path $destination 'key/key-binding.json') -Destination (Join-Path $destination 'key-binding.json')
Invoke-SetupChild -Executable (Join-Path $destination 'bin/0.4.0/docker-credential-ssh-tpm.exe') -Arguments @('init')
New-PrivateSetupDirectory -Path (Join-Path $destination 'docker-config')
'{"credsStore":"ssh-tpm"}' | Set-Content -LiteralPath (Join-Path $destination 'docker-config/config.json') -Encoding utf8NoBOM
$helperHashes=@{}
foreach ($entry in $manifest.Files.PSObject.Properties | Where-Object { $_.Name.StartsWith('helper/') }) { $helperHashes[[IO.Path]::GetFileName($entry.Name)]=$entry.Value }
$helperHashes|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $destination 'installed-manifest.json') -Encoding utf8NoBOM
@{Version=1;State='READY';HelperKind='tpm';HelperVersion='0.4.0';InstallationId=$InstallationId;Mode=$Mode;EngineEndpoint=$EngineEndpoint;DockerExecutable=$docker} |
    ConvertTo-Json|Set-Content -LiteralPath (Join-Path $destination 'settings.json') -Encoding utf8NoBOM
Write-Output 'Setup READY; empty encrypted store initialized; private decryption and real registry remain untested.'

<# .SYNOPSIS Disables a dedicated installation or explicitly removes its matched key and encrypted store; default is read-only. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $DestinationRoot,[Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string] $InstallationId,
    [Parameter(Mandatory)][ValidateSet('poc','permanent')][string] $Mode,[switch] $Execute,[switch] $DeleteKey,[switch] $ConfirmIrreversibleKeyDeletion)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TpmSetupRuntime.ps1')
$Mode=$Mode.ToLowerInvariant()
if (-not [IO.Path]::IsPathFullyQualified($DestinationRoot)) { throw 'Absolute destination required.' }
$destination=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DestinationRoot))
$expected=if ($Mode -eq 'poc') { Join-Path $env:LOCALAPPDATA ('docker-ssh-issue142-lab-install-' + $InstallationId) } else { Join-Path $env:LOCALAPPDATA ('Dotfiles/DockerSsh/Installations/' + $InstallationId) }
if ($destination -ine $expected) { throw 'Installation target mismatch.' }
# This trusted repository reader validates the installation before exposing its path-checking function; it executes no helper.
. (Join-Path $PSScriptRoot '../chezmoi/AppData/Local/Dotfiles/DockerSsh/Get-TpmDockerEnvironment.ps1') -DeploymentRoot $destination -AllowDisabled -NoOutput
$settingsPath=Join-Path $destination 'settings.json'
$settings=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json
if ($settings.InstallationId -cne $InstallationId -or $settings.Mode -cne $Mode -or $settings.HelperVersion -ne '0.4.0') { throw 'Installation identity mismatch.' }
$manifest=Get-Content -LiteralPath (Join-Path $destination 'package.json') -Raw|ConvertFrom-Json
$expectedPackage=@('helper/docker-credential-ssh-tpm.exe','helper/docker-credential-ssh-tpm.dll','helper/docker-credential-ssh-tpm.deps.json','helper/docker-credential-ssh-tpm.runtimeconfig.json',
    'key-tool/docker-ssh-tpm-key.exe','key-tool/docker-ssh-tpm-key.dll','key-tool/docker-ssh-tpm-key.deps.json','key-tool/docker-ssh-tpm-key.runtimeconfig.json','shell/docker-ssh.bash','shell/Get-TpmDockerEnvironment.ps1')
if ($manifest.Version -ne '0.4.0' -or @($manifest.Files.PSObject.Properties).Count -ne 10 -or @(Compare-Object $expectedPackage @($manifest.Files.PSObject.Properties.Name)).Count) { throw 'Unexpected package manifest.' }
$allowed=@('settings.json','setup-state.json','package.json','installed-manifest.json','key-binding.json','docker-config/config.json',
    'key/operation.lock','key/create-intent.json','key/created-public.json','key/receipt.json','key/key-binding.json','key/delete-intent.json','key/delete-api.json','key/delete-existence.json',
    'store/settings.json','store/initialization.claim','store/store.lock','store/vault.tpm')
foreach ($entry in $manifest.Files.PSObject.Properties) {
    $relative=if ($entry.Name.StartsWith('helper/')) { 'bin/0.4.0/' + [IO.Path]::GetFileName($entry.Name) } else { $entry.Name }
    if ($relative -notmatch '^(bin/0\.4\.0/|key-tool/|shell/)[A-Za-z0-9.-]+$') { throw 'Unexpected manifest path.' }
    $allowed+=$relative
    $file=Join-Path $destination $relative
    Assert-TpmDeploymentPath -Path $file
    if ((Get-FileHash -LiteralPath $file).Hash -cne $entry.Value) { throw 'Installed file changed; preserve installation.' }
}
$pending=[Collections.Generic.Stack[string]]::new()
$pending.Push($destination)
$allowedDirectories=@('.','bin','bin/0.4.0','key','key-tool','shell','store','docker-config')
while ($pending.Count) {
    $path=$pending.Pop()
    Assert-TpmDeploymentPath -Path $path
    if (Test-Path -LiteralPath $path -PathType Container) {
        if ([IO.Path]::GetRelativePath($destination,$path).Replace('\','/') -notin $allowedDirectories) { throw 'Unknown directory; no removal.' }
        foreach ($child in Get-ChildItem -LiteralPath $path -Force) { $pending.Push($child.FullName) }
    } elseif ([IO.Path]::GetRelativePath($destination,$path).Replace('\','/') -notin $allowed) { throw 'Unknown file; no removal.' }
}
if (-not $Execute) { Write-Output 'Removal plan only; key deletion makes dependent ciphertext unrecoverable; no changes.'; return }
if (-not $DeleteKey) {
    $settings.State='DISABLED'
    $settings|ConvertTo-Json|Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    Write-Output 'Dedicated deployment disabled; encrypted store, key and binaries retained. Existing Desktop unchanged.'
    return
}
if (-not $ConfirmIrreversibleKeyDeletion) { throw 'Explicit irreversible key-deletion acknowledgement required.' }
$tool=Join-Path $destination 'key-tool/docker-ssh-tpm-key.exe'
Invoke-TpmSetupProcess -Executable $tool -Arguments @('delete',(Join-Path $destination 'key'),$InstallationId,$Mode) -KeyRoot (Join-Path $destination 'key') -InstallationId $InstallationId
$api=Get-Content -LiteralPath (Join-Path $destination 'key/delete-api.json') -Raw|ConvertFrom-Json
$existence=Get-Content -LiteralPath (Join-Path $destination 'key/delete-existence.json') -Raw|ConvertFrom-Json
if ($api.Status -cne '0x00000000' -or $existence.Status -cne '0x80090016' -or -not $existence.Absent) { throw 'Independent cleanup evidence mismatch.' }
# Preserve public receipts outside the removal target; they contain no private material or credentials.
$audit=Join-Path (Split-Path -Parent $destination) ($InstallationId + '-removed.json')
if (Test-Path -LiteralPath $audit) { throw 'Audit collision; key removed but package retained.' }
$receipt=Get-Content -LiteralPath (Join-Path $destination 'key/receipt.json') -Raw|ConvertFrom-Json
$auditBytes=[Text.Encoding]::UTF8.GetBytes((@{InstallationId=$InstallationId;Mode=$Mode;Receipt=$receipt;DeleteApi=$api;Existence=$existence}|ConvertTo-Json -Depth 8))
$auditStream=[IO.FileStream]::new($audit,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read,4096,[IO.FileOptions]::WriteThrough)
try { $auditStream.Write($auditBytes);$auditStream.Flush($true) } finally { $auditStream.Dispose() }
# The absolute ID-bound target and all descendants were verified before the one authorized key removal.
Remove-Item -LiteralPath $destination -Recurse -Force
if (Test-Path -LiteralPath $destination) { throw 'Package removal incomplete; no automatic retry.' }
Write-Output 'Dedicated key deletion and separate absence PASS; matching package removed; Desktop unchanged.'

<# .SYNOPSIS Removes only an identity-matched disposable package; never opens or deletes a TPM key. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $DestinationRoot, [Parameter(Mandatory)][string] $InstallationId, [switch] $Execute)
$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($DestinationRoot)) { throw 'Absolute target required.' }
$destination = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DestinationRoot))
$localData = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($env:LOCALAPPDATA))
if (-not $destination.StartsWith($localData + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($destination) -notlike 'docker-ssh-issue142-lab-*') { throw 'Target is outside the disposable lab boundary.' }
$settings = Get-Content -LiteralPath (Join-Path $destination 'settings.json') -Raw | ConvertFrom-Json
if ($settings.Version -ne 1 -or $settings.HelperKind -ne 'tpm' -or $settings.InstallationId -cne $InstallationId -or $InstallationId -notmatch '^[a-f0-9]{32}$') { throw 'Installation identity mismatch.' }
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$allowed = @('installation.claim', 'settings.json', 'installed-manifest.json', 'key-binding.json', 'docker-config/config.json',
    'store/initialization.claim', 'store/store.lock', 'store/settings.json', 'store/vault.tpm',
    'bin/0.4.0/docker-credential-ssh-tpm.exe', 'bin/0.4.0/docker-credential-ssh-tpm.dll', 'bin/0.4.0/docker-credential-ssh-tpm.deps.json', 'bin/0.4.0/docker-credential-ssh-tpm.runtimeconfig.json')
# Inspect each directory before descending; never traverse an unverified reparse point.
$pending = [Collections.Generic.Stack[string]]::new()
$pending.Push($destination)
while ($pending.Count) {
    $current = $pending.Pop()
    $item = Get-Item -LiteralPath $current -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point found; no removal.' }
    $acl = Get-Acl -LiteralPath $current
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($acl.Sddl)
    if ($raw.Owner -ne $owner -or $null -eq $raw.DiscretionaryAcl) { throw 'Unexpected owner or null DACL.' }
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) -ne $owner) { throw 'Unexpected grant; no removal.' }
    }
    if ($item.PSIsContainer) {
        $relativeDirectory = [IO.Path]::GetRelativePath($destination, $current).Replace('\', '/')
        if ($relativeDirectory -notin @('.', 'bin', 'bin/0.4.0', 'docker-config', 'store')) { throw 'Unrecognized directory; preserve the package.' }
        foreach ($child in Get-ChildItem -LiteralPath $current -Force) { $pending.Push($child.FullName) }
    } else {
        $relative = [IO.Path]::GetRelativePath($destination, $current).Replace('\', '/')
        if ($relative -notin $allowed) { throw 'Unrecognized file; preserve the package.' }
    }
}
if (-not $Execute) { Write-Output 'Matched disposable package; removal not executed. TPM key is outside this operation.'; return }
# The absolute target, prefix, installation identity and all descendants have been checked above.
Remove-Item -LiteralPath $destination -Recurse -Force
if (Test-Path -LiteralPath $destination) { throw 'Package removal incomplete; do not retry automatically.' }
Write-Output 'Matched disposable package removed; no TPM key or existing Docker setting changed.'

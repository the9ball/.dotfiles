<#
.SYNOPSIS
Prepares the Cloudflared Windows service so chezmoi apply can follow aqua updates.
.DESCRIPTION
Run once with an explicit PowerShell interpreter as an administrator, from the
same user account that runs chezmoi apply. The script copies the aqua-managed
cloudflared binary to a fixed per-user path, points the service at that path
with automatic self-update disabled, and grants the user the service rights
needed to stop, start, and query it. Re-running is safe.
Use -WhatIf to inspect the operation without administrator privileges or writes.
See docs/windows-cloudflared.md for the background and the accepted risk.
.PARAMETER ServiceName
Name of the existing cloudflared tunnel service.
.PARAMETER UserName
Account that runs chezmoi apply and receives the service control rights.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ServiceName = 'Cloudflared',
    [string]$UserName = "$env:USERDOMAIN\$env:USERNAME"
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$aquaConfig = Join-Path $repositoryRoot 'aqua.yaml'
# Keep this path in sync with run_onchange_after_update-cloudflared-service.ps1.tmpl.
$serviceExecutable = Join-Path $env:LOCALAPPDATA 'cloudflared-service\cloudflared.exe'
# Query config/status, enumerate dependents, start, stop, interrogate, user control, and read control.
# SERVICE_CHANGE_CONFIG (DC) is deliberately excluded so the user cannot repoint the service.
$serviceControlRights = 'CCLCSWRPWPLOCRRC'

function Get-ServiceArguments {
    <#
    .SYNOPSIS
    Returns the service command-line arguments with automatic self-update disabled.
    .PARAMETER PathName
    The current service command line, with or without a quoted executable path.
    .OUTPUTS
    The argument string that follows the executable path.
    #>
    param([string]$PathName)

    # aqua stores the binary inside a directory that also ends in ".exe", so an
    # unquoted path must end at an ".exe" that is followed by whitespace.
    if ($PathName -notmatch '^\s*(?:"(?<executable>[^"]+)"|(?<executable>\S+?\.exe)(?=\s|$))\s*(?<arguments>.*)$') {
        throw "Unexpected service command line: $PathName"
    }
    $arguments = $Matches.arguments.Trim()
    if ($arguments -notmatch '^tunnel\s') {
        throw "The service does not run 'cloudflared tunnel': $arguments"
    }
    # Self-update would rewrite the copied binary behind aqua's pinned version.
    if ($arguments -notmatch '(^|\s)--no-autoupdate(\s|$)') {
        $arguments = $arguments -replace '^tunnel\s+', 'tunnel --no-autoupdate '
    }
    return $arguments
}

function Add-ServiceControlEntry {
    <#
    .SYNOPSIS
    Adds the service control ACE for the given SID unless an equal one already exists.
    .PARAMETER UserSid
    Security identifier of the account that receives the rights.
    .NOTES
    Changes the service security descriptor through sc.exe sdset.
    #>
    param([string]$UserSid)

    $securityDescriptor = ((& sc.exe sdshow $ServiceName) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $securityDescriptor.StartsWith('D:')) {
        throw "Could not read the security descriptor of $ServiceName (exit code: $LASTEXITCODE)"
    }
    $accessControlEntry = "(A;;$serviceControlRights;;;$UserSid)"
    if ($securityDescriptor.Contains($accessControlEntry)) {
        Write-Host "Service control rights for $UserName are already present."
        return
    }
    # The ACE belongs to the DACL, so it must precede an optional SACL ("S:") section.
    $saclIndex = $securityDescriptor.IndexOf('S:')
    $updatedDescriptor = if ($saclIndex -ge 0) {
        $securityDescriptor.Insert($saclIndex, $accessControlEntry)
    } else {
        $securityDescriptor + $accessControlEntry
    }
    if ($PSCmdlet.ShouldProcess($ServiceName, "Grant $serviceControlRights to $UserName")) {
        & sc.exe sdset $ServiceName $updatedDescriptor | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "sc.exe sdset failed (exit code: $LASTEXITCODE)"
        }
    }
}

if (-not $WhatIfPreference) {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in an administrator PowerShell, or use -WhatIf.'
    }
}

$service = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
if (-not $service) {
    throw "Service not found: $ServiceName"
}
$serviceArguments = Get-ServiceArguments -PathName $service.PathName
# Embedded quotes in sc.exe binPath= are not passed through consistently across
# PowerShell versions, so only a space-free executable path is accepted.
if ($serviceExecutable.Contains(' ')) {
    throw "The service executable path must not contain spaces: $serviceExecutable"
}
$binaryPath = "$serviceExecutable $serviceArguments"
$userSid = ([Security.Principal.NTAccount]::new($UserName)).Translate(
    [Security.Principal.SecurityIdentifier]).Value

$aqua = (Get-Command aqua -ErrorAction Stop).Source
$sourceExecutable = (& $aqua -c $aquaConfig which cloudflared | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sourceExecutable -PathType Leaf)) {
    throw "aqua could not resolve an installed cloudflared; run aqua install first (exit code: $LASTEXITCODE)"
}

if ($PSCmdlet.ShouldProcess($ServiceName, 'Stop service')) {
    Stop-Service -Name $ServiceName
}
if ($PSCmdlet.ShouldProcess($serviceExecutable, "Copy $sourceExecutable")) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $serviceExecutable) | Out-Null
    Copy-Item -LiteralPath $sourceExecutable -Destination $serviceExecutable -Force
}
if ($PSCmdlet.ShouldProcess($ServiceName, "Set binPath to $binaryPath")) {
    & sc.exe config $ServiceName binPath= $binaryPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe config failed (exit code: $LASTEXITCODE)"
    }
}
Add-ServiceControlEntry -UserSid $userSid
if ($PSCmdlet.ShouldProcess($ServiceName, 'Start service')) {
    Start-Service -Name $ServiceName
}

if (-not $WhatIfPreference) {
    Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" | Select-Object State, PathName | Format-List
    & $serviceExecutable --version
}

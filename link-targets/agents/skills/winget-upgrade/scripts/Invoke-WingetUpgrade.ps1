#Requires -Version 7
<#
.SYNOPSIS
Upgrades the given winget packages with a single UAC approval.

.DESCRIPTION
Upgrades each package ID one at a time in one elevated PowerShell process, so the
user approves UAC once instead of once per installer. When the caller is already
elevated, the packages are upgraded in-process without another prompt.

Each winget run is logged as UTF-8 in a new directory under the temporary
directory. The script prints a per-package summary and the log directory path.

.PARAMETER PackageId
Exact winget package IDs to upgrade. Comma-separated values are also accepted so
the script can be called with `pwsh -File`, which passes each argument as one
string.

.PARAMETER WorkerRequestPath
Internal parameter used by the elevated worker process. Do not pass it directly.

.EXAMPLE
pwsh -NoProfile -File .\Invoke-WingetUpgrade.ps1 -PackageId WinMerge.WinMerge,Microsoft.WindowsTerminal

.OUTPUTS
System.String

.NOTES
Exit Codes:
0 - Every package was upgraded or had no applicable upgrade.
1 - At least one package is BlockedByPin, NotInstalled, or Failed, or the
    elevated worker stopped before finishing every package.
2 - Invalid input, elevation was declined or failed, or the elevated worker did
    not produce any result.

Trust assumption: the elevated worker runs this script, the current pwsh
executable, and a request file from locations the current user can write to.
Package IDs are validated again in the worker so a changed request cannot add
winget options, but a process running as the same user could still replace these
files. UAC is not a security boundary against such a process.
#>
[CmdletBinding(DefaultParameterSetName = 'Upgrade')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Upgrade')]
    [string[]] $PackageId,

    [Parameter(Mandatory, ParameterSetName = 'Worker')]
    [string] $WorkerRequestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageIdPattern = '^[A-Za-z0-9][A-Za-z0-9._+-]*$'
$requestFileName = 'request.json'
$resultFileName = 'result.json'
$workerErrorFileName = 'worker-error.txt'

# winget result codes that this script distinguishes from a generic failure. The
# keys are hex text because PowerShell parses hex literals such as 0x8A15002B as
# negative Int32 values, which would not match the unsigned exit code.
$statusByExitCode = @{
    '0x00000000' = 'Upgraded'
    '0x8A15002B' = 'NoUpgradeAvailable'
    '0x8A150068' = 'BlockedByPin'
    '0x8A150014' = 'NotInstalled'
}
$successStatuses = @('Upgraded', 'NoUpgradeAvailable')

function Test-IsAdministrator {
    <#
    .SYNOPSIS
    Returns whether the current process runs with an elevated administrator token.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-ExitCodeText {
    <#
    .SYNOPSIS
    Formats a native exit code as eight-digit unsigned hex text, such as 0x8A15002B.
    .PARAMETER ExitCode
    The exit code as reported by $LASTEXITCODE, which is negative for HRESULTs.
    .OUTPUTS
    System.String
    #>
    param([Parameter(Mandatory)] [long] $ExitCode)

    return '0x{0:X8}' -f ($ExitCode -band 0xFFFFFFFFL)
}

function Get-UpgradeStatus {
    <#
    .SYNOPSIS
    Maps a winget exit code to the status name used in the summary.
    .PARAMETER ExitCodeText
    The exit code formatted by ConvertTo-ExitCodeText.
    .OUTPUTS
    System.String. 'Failed' for any code without a specific meaning here.
    #>
    param([Parameter(Mandatory)] [string] $ExitCodeText)

    if ($statusByExitCode.ContainsKey($ExitCodeText)) {
        return $statusByExitCode[$ExitCodeText]
    }
    return 'Failed'
}

function Get-NormalizedPackageIds {
    <#
    .SYNOPSIS
    Splits comma-separated values, trims them, and validates every package ID.
    .PARAMETER RawPackageIds
    Package IDs as received from the command line or the worker request.
    .OUTPUTS
    System.String[]. Unique IDs in their original order.
    .NOTES
    Throws when an ID contains characters outside the winget ID pattern, so no
    value can be interpreted as an extra winget option.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string[]] $RawPackageIds)

    $normalizedIds = [Collections.Generic.List[string]]::new()
    foreach ($rawValue in $RawPackageIds) {
        foreach ($candidateId in ($rawValue -split ',')) {
            $trimmedId = $candidateId.Trim()
            if ($trimmedId -eq '') {
                continue
            }
            if ($trimmedId -notmatch $packageIdPattern) {
                throw "Invalid winget package ID: '$trimmedId'"
            }
            if (-not $normalizedIds.Contains($trimmedId)) {
                $normalizedIds.Add($trimmedId)
            }
        }
    }
    if ($normalizedIds.Count -eq 0) {
        throw 'No package IDs were given.'
    }
    return $normalizedIds.ToArray()
}

function Invoke-PackageUpgrade {
    <#
    .SYNOPSIS
    Runs `winget upgrade` for one exact package ID and logs its output.
    .PARAMETER Id
    The validated winget package ID.
    .PARAMETER LogPath
    The UTF-8 log file that receives the winget output.
    .OUTPUTS
    PSCustomObject with PackageId, ExitCode (hex text), and Status.
    #>
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $LogPath
    )

    $winget = (Get-Command winget -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $wingetArguments = @(
        'upgrade', '--id', $Id, '--exact', '--silent',
        '--disable-interactivity', '--accept-source-agreements', '--accept-package-agreements'
    )
    & $winget @wingetArguments *>&1 | Out-File -LiteralPath $LogPath -Encoding utf8
    $exitCodeText = ConvertTo-ExitCodeText -ExitCode $LASTEXITCODE
    return [pscustomobject]@{
        PackageId = $Id
        ExitCode = $exitCodeText
        Status = (Get-UpgradeStatus -ExitCodeText $exitCodeText)
    }
}

function Invoke-UpgradeBatch {
    <#
    .SYNOPSIS
    Upgrades packages sequentially and records the results after each package.
    .PARAMETER Ids
    The validated package IDs to upgrade.
    .PARAMETER WorkDirectory
    The directory that receives one log file per package and the result file.
    .OUTPUTS
    PSCustomObject[] produced by Invoke-PackageUpgrade.
    .NOTES
    Rewriting the result file after every package keeps the finished results
    available when a later package stops the batch.
    #>
    param(
        [Parameter(Mandatory)] [string[]] $Ids,
        [Parameter(Mandatory)] [string] $WorkDirectory
    )

    # winget writes UTF-8 when its output is redirected. A new elevated console
    # starts with the OEM code page, which garbles that output unless the decoder
    # matches. The console may be shared with the caller, so restore it afterwards.
    $previousOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    try {
        $results = [Collections.Generic.List[object]]::new()
        foreach ($id in $Ids) {
            Write-Host "upgrading $id"
            $results.Add((Invoke-PackageUpgrade -Id $id -LogPath (Join-Path $WorkDirectory "$id.log")))
            ConvertTo-Json -InputObject $results.ToArray() -Depth 3 |
                Set-Content -LiteralPath (Join-Path $WorkDirectory $resultFileName) -Encoding utf8
        }
        return $results.ToArray()
    }
    finally {
        [Console]::OutputEncoding = $previousOutputEncoding
    }
}

function Invoke-ElevatedWorker {
    <#
    .SYNOPSIS
    Runs the elevated pass described by a request file.
    .PARAMETER RequestPath
    The request.json file created by the non-elevated caller. Results and logs are
    written next to it, so the request never names arbitrary output paths.
    .NOTES
    The worker window closes when it exits, so any error is written to a file in
    the work directory for the caller to report.
    #>
    param([Parameter(Mandatory)] [string] $RequestPath)

    $workDirectory = Split-Path -Parent $RequestPath
    try {
        $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8 | ConvertFrom-Json
        $ids = Get-NormalizedPackageIds -RawPackageIds @($request.packageIds)
        Invoke-UpgradeBatch -Ids $ids -WorkDirectory $workDirectory | Out-Null
    }
    catch {
        Set-Content -LiteralPath (Join-Path $workDirectory $workerErrorFileName) -Value ($_ | Out-String) -Encoding utf8
        exit 1
    }
}

function Start-ElevatedWorker {
    <#
    .SYNOPSIS
    Starts this script elevated for the given IDs and waits for it to exit.
    .PARAMETER Ids
    The validated package IDs.
    .PARAMETER WorkDirectory
    The directory shared with the worker for the request, results, and logs.
    .NOTES
    Shows one UAC prompt. Throws when elevation is declined or fails to start.
    #>
    param(
        [Parameter(Mandatory)] [string[]] $Ids,
        [Parameter(Mandatory)] [string] $WorkDirectory
    )

    $requestPath = Join-Path $WorkDirectory $requestFileName
    ConvertTo-Json -InputObject @{ packageIds = @($Ids) } |
        Set-Content -LiteralPath $requestPath -Encoding utf8

    # Start-Process joins the argument list with spaces and does not quote it,
    # so paths that may contain spaces are quoted here.
    $pwshPath = (Get-Process -Id $PID).Path
    $workerArguments = @(
        '-NoProfile', '-File', "`"$PSCommandPath`"",
        '-WorkerRequestPath', "`"$requestPath`""
    )
    Start-Process -FilePath $pwshPath -ArgumentList $workerArguments -Verb RunAs `
        -WindowStyle Minimized -Wait | Out-Null
}

if ($PSCmdlet.ParameterSetName -eq 'Worker') {
    Invoke-ElevatedWorker -RequestPath $WorkerRequestPath
    exit 0
}

try {
    $ids = Get-NormalizedPackageIds -RawPackageIds $PackageId
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 2
}

$workDirectoryName = 'winget-upgrade-{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), [IO.Path]::GetRandomFileName().Replace('.', '')
$workDirectory = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) $workDirectoryName)).FullName

if (Test-IsAdministrator) {
    Invoke-UpgradeBatch -Ids $ids -WorkDirectory $workDirectory | Out-Null
}
else {
    try {
        Start-ElevatedWorker -Ids $ids -WorkDirectory $workDirectory
    }
    catch {
        Write-Error -Message "Elevated upgrade did not start: $($_.Exception.Message). Logs: $workDirectory" -ErrorAction Continue
        exit 2
    }
}

$workerErrorPath = Join-Path $workDirectory $workerErrorFileName
$resultPath = Join-Path $workDirectory $resultFileName
$results = @()
if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
    $results = @(Get-Content -LiteralPath $resultPath -Raw -Encoding utf8 | ConvertFrom-Json)
}
if ($results.Count -gt 0) {
    Write-Output ($results | Format-Table PackageId, Status, ExitCode -AutoSize | Out-String -Width 200).TrimEnd()
}
Write-Output "Logs: $workDirectory"

if (Test-Path -LiteralPath $workerErrorPath -PathType Leaf) {
    Write-Output "The elevated worker stopped after $($results.Count) of $($ids.Count) packages:"
    Write-Output (Get-Content -LiteralPath $workerErrorPath -Raw -Encoding utf8).TrimEnd()
}
if ($results.Count -eq 0) {
    exit 2
}

$unsuccessfulCount = @($results | Where-Object { $successStatuses -notcontains $_.Status }).Count
if ($unsuccessfulCount -gt 0 -or $results.Count -lt $ids.Count) {
    exit 1
}
exit 0

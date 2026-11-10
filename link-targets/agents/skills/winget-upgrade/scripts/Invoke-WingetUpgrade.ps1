<#
.SYNOPSIS
Upgrades the given winget packages with a single UAC approval.

.DESCRIPTION
Upgrades each package ID one at a time in one elevated PowerShell process, so the
user approves UAC once instead of once per installer. Packages that fail in the
elevated pass are retried once without elevation, because some per-user
installers do not install from an elevated process. When the caller is
already elevated, the packages are upgraded in-process and no retry is possible.

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
1 - At least one package was not upgraded (failed, pinned, or not installed).
2 - Invalid input, elevation was declined or failed, or the elevated worker did
    not produce a result.
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

# winget writes UTF-8 when its output is redirected. A new elevated console starts
# with the OEM code page, which garbles that output unless the decoder matches.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$packageIdPattern = '^[A-Za-z0-9][A-Za-z0-9._+-]*$'
$requestFileName = 'request.json'
$resultFileName = 'result.json'

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
    param([Parameter(Mandatory)] [string[]] $RawPackageIds)

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
    Upgrades packages sequentially and returns one result per package.
    .PARAMETER Ids
    The validated package IDs to upgrade.
    .PARAMETER LogDirectory
    The directory that receives one log file per package.
    .PARAMETER AttemptName
    A label added to each log file name, such as 'elevated' or 'user'.
    .OUTPUTS
    PSCustomObject[] produced by Invoke-PackageUpgrade.
    #>
    param(
        [Parameter(Mandatory)] [string[]] $Ids,
        [Parameter(Mandatory)] [string] $LogDirectory,
        [Parameter(Mandatory)] [string] $AttemptName
    )

    $results = foreach ($id in $Ids) {
        Write-Host "[$AttemptName] upgrading $id"
        $logPath = Join-Path $LogDirectory "$id.$AttemptName.log"
        Invoke-PackageUpgrade -Id $id -LogPath $logPath
    }
    return @($results)
}

function Invoke-ElevatedWorker {
    <#
    .SYNOPSIS
    Runs the elevated pass described by a request file and writes its results.
    .PARAMETER RequestPath
    The request.json file created by the non-elevated caller. Results and logs are
    written next to it, so the request never names arbitrary output paths.
    #>
    param([Parameter(Mandatory)] [string] $RequestPath)

    $workDirectory = Split-Path -Parent $RequestPath
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $ids = Get-NormalizedPackageIds -RawPackageIds @($request.packageIds)
    $results = Invoke-UpgradeBatch -Ids $ids -LogDirectory $workDirectory -AttemptName 'elevated'
    ConvertTo-Json -InputObject @($results) -Depth 3 |
        Set-Content -LiteralPath (Join-Path $workDirectory $resultFileName) -Encoding utf8
}

function Start-ElevatedWorker {
    <#
    .SYNOPSIS
    Starts this script elevated for the given IDs and waits for its results.
    .PARAMETER Ids
    The validated package IDs.
    .PARAMETER WorkDirectory
    The directory shared with the worker for the request, results, and logs.
    .OUTPUTS
    PSCustomObject[] read from the worker's result file.
    .NOTES
    Shows one UAC prompt. Throws when elevation is declined or no result exists.
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

    $resultPath = Join-Path $WorkDirectory $resultFileName
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "The elevated worker did not write $resultPath"
    }
    return @(Get-Content -LiteralPath $resultPath -Raw -Encoding utf8 | ConvertFrom-Json)
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

$isAlreadyElevated = Test-IsAdministrator
if ($isAlreadyElevated) {
    $firstPassResults = Invoke-UpgradeBatch -Ids $ids -LogDirectory $workDirectory -AttemptName 'elevated'
}
else {
    try {
        $firstPassResults = Start-ElevatedWorker -Ids $ids -WorkDirectory $workDirectory
    }
    catch {
        Write-Error -Message "Elevated upgrade did not complete: $($_.Exception.Message). Logs: $workDirectory" -ErrorAction Continue
        exit 2
    }
}

$summary = foreach ($firstPassResult in $firstPassResults) {
    $retryResult = $null
    # Only generic failures are retried: pinned, missing, or up-to-date packages
    # would return the same code again without elevation.
    if (-not $isAlreadyElevated -and $firstPassResult.Status -eq 'Failed') {
        $retryResult = (Invoke-UpgradeBatch -Ids @($firstPassResult.PackageId) -LogDirectory $workDirectory -AttemptName 'user')[0]
    }
    [pscustomobject]@{
        PackageId = $firstPassResult.PackageId
        Status = if ($retryResult) { $retryResult.Status } else { $firstPassResult.Status }
        ElevatedExitCode = $firstPassResult.ExitCode
        RetryExitCode = if ($retryResult) { $retryResult.ExitCode } else { '' }
    }
}

Write-Output ($summary | Format-Table -AutoSize | Out-String -Width 200).TrimEnd()
Write-Output "Logs: $workDirectory"
if ($isAlreadyElevated -and @($summary | Where-Object Status -eq 'Failed').Count -gt 0) {
    Write-Output 'Failed packages were not retried because this process is already elevated; rerun them from a non-elevated shell.'
}

$unsuccessfulCount = @($summary | Where-Object { $successStatuses -notcontains $_.Status }).Count
if ($unsuccessfulCount -gt 0) {
    exit 1
}
exit 0

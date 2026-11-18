# Run only this monitor's attach child and honor a separate stop request while waiting.
$ErrorActionPreference = 'Stop'
$dailyLogPath = Join-Path $env:DAILY_RUNTIME_DIRECTORY ($env:DAILY_RUN_NAME + '.attach.log')
$dailyStopPath = Join-Path $env:DAILY_RUNTIME_DIRECTORY 'stop.request'
$dailyRecreationPath = Join-Path $env:DAILY_RUNTIME_DIRECTORY 'recreate.request'

function Invoke-DailyControl {
    <# .SYNOPSIS
    Run and bound one owned control CLI without selecting or terminating server processes.
    #>
    param([string]$Arguments)
    $control = [Diagnostics.Process]::new()
    $started = $false
    try {
        $control.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $control.StartInfo.FileName = $env:DAILY_PSMUX_EXECUTABLE
        $control.StartInfo.Arguments = '-L ' + $env:DAILY_NAMESPACE + ' ' + $Arguments
        $control.StartInfo.UseShellExecute = $false
        $control.StartInfo.CreateNoWindow = $true
        $control.StartInfo.RedirectStandardOutput = $true
        $control.StartInfo.RedirectStandardError = $true
        if (-not $control.Start()) { throw 'Control CLI did not start.' }
        $started = $true
        $null = $control.Handle
        $outputTask = $control.StandardOutput.ReadToEndAsync()
        $errorTask = $control.StandardError.ReadToEndAsync()
        Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} control-start pid={1} windows-session-id={2} command={3}' -f [DateTimeOffset]::Now, $control.Id, $control.SessionId, $Arguments)
        if (-not $control.WaitForExit(7000)) { throw 'Control CLI timed out.' }
        if (-not $outputTask.Wait(1000) -or -not $errorTask.Wait(1000)) { throw 'Control CLI output did not close.' }
        Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} control-exit pid={1} exit={2} exited={3:o} stderr={4}' -f [DateTimeOffset]::Now, $control.Id, $control.ExitCode, $control.ExitTime, $errorTask.Result.TrimEnd())
        return [pscustomobject]@{ Exit = $control.ExitCode; Output = $outputTask.Result }
    }
    finally {
        if ($started -and -not $control.HasExited) {
            $control.Kill()
            $null = $control.WaitForExit(5000)
        }
        $control.Dispose()
    }
}

$dailyCurrentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} helper-pid={1} windows-session-id={2} stdin-redirected={3} stdout-redirected={4}' -f [DateTimeOffset]::Now, $dailyCurrentProcess.Id, $dailyCurrentProcess.SessionId, [Console]::IsInputRedirected, [Console]::IsOutputRedirected)
if (Test-Path -LiteralPath $dailyStopPath) { exit 0 }
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
    Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} refused-no-console exit=78' -f [DateTimeOffset]::Now)
    exit 78
}
if ($env:DOTFILES_PSMUX_OWNER -cnotmatch '^[0-9a-f]{32}$') { exit 80 }
$dailyOwnership = Invoke-DailyControl ('show-environment -t ' + $env:DAILY_SESSION + ' DOTFILES_PSMUX_OWNER')
if ($dailyOwnership.Exit -ne 0 -or $dailyOwnership.Output.Trim() -cne ('DOTFILES_PSMUX_OWNER=' + $env:DOTFILES_PSMUX_OWNER)) {
    Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} ownership-mismatch no-attach exit=80' -f [DateTimeOffset]::Now)
    exit 80
}

# A missing or stale PID anchor must never be interpreted as process zero.
$dailyServerProcess = $null
$dailyServerAnchorPath = Join-Path $env:PSMUX_DATA_DIR ($env:DAILY_NAMESPACE + '__' + $env:DAILY_SESSION + '.pid')
if (Test-Path -LiteralPath $dailyServerAnchorPath) {
    $dailyAnchorMatch = [regex]::Match([IO.File]::ReadAllText($dailyServerAnchorPath).Trim(), '^([1-9][0-9]*):([0-9]+)$')
    if ($dailyAnchorMatch.Success) {
        try {
            $dailyServerProcess = [System.Diagnostics.Process]::GetProcessById([int]$dailyAnchorMatch.Groups[1].Value)
            if ($dailyServerProcess.StartTime.ToFileTimeUtc() -eq [long]$dailyAnchorMatch.Groups[2].Value) {
                # Keep this exact server instance observable through its shutdown.
                $null = $dailyServerProcess.Handle
                Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} server-pid={1} windows-session-id={2} anchor-identity=matched' -f [DateTimeOffset]::Now, $dailyServerProcess.Id, $dailyServerProcess.SessionId)
            }
            else {
                $dailyServerProcess.Dispose()
                $dailyServerProcess = $null
            }
        }
        catch {
            if ($null -ne $dailyServerProcess) { $dailyServerProcess.Dispose() }
            $dailyServerProcess = $null
            Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} server-identity-unconfirmed={1}' -f [DateTimeOffset]::Now, $_.Exception.Message)
        }
    }
}

if ($null -eq $dailyServerProcess -or $dailyServerProcess.SessionId -ne 1 -or $dailyServerProcess.HasExited) {
    if ($null -ne $dailyServerProcess) { $dailyServerProcess.Dispose() }
    Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} refused-unconfirmed-session1-server exit=79' -f [DateTimeOffset]::Now)
    exit 79
}
$dailyOwnership = Invoke-DailyControl ('show-environment -t ' + $env:DAILY_SESSION + ' DOTFILES_PSMUX_OWNER')
if ($dailyOwnership.Exit -ne 0 -or $dailyOwnership.Output.Trim() -cne ('DOTFILES_PSMUX_OWNER=' + $env:DOTFILES_PSMUX_OWNER) -or [IO.File]::ReadAllText($dailyServerAnchorPath).Trim() -cne $dailyAnchorMatch.Value) {
    $dailyServerProcess.Dispose()
    exit 80
}

$dailyStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$dailyStartInfo.FileName = $env:DAILY_PSMUX_EXECUTABLE
# Keep config-driven new-session bootstrap out of this existing-server client.
$dailyStartInfo.Arguments = '-f NUL -L ' + $env:DAILY_NAMESPACE + ' attach -t ' + $env:DAILY_SESSION
$dailyStartInfo.UseShellExecute = $false
$dailyStartInfo.CreateNoWindow = $false
$dailyStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$dailyStartInfo.RedirectStandardError = $true
$dailyAttachProcess = [System.Diagnostics.Process]::new()
$dailyAttachProcess.StartInfo = $dailyStartInfo
$dailyTimer = [System.Diagnostics.Stopwatch]::StartNew()
$dailyAttachStarted = $false
$dailyCoordinatedKill = $false
try {
    if (-not $dailyAttachProcess.Start()) { throw 'Attach process did not start.' }
    $dailyAttachStarted = $true
    $dailyErrorRead = $dailyAttachProcess.StandardError.ReadToEndAsync()
    # Retain the creation handle; never reopen or select an unrelated process by PID.
    $null = $dailyAttachProcess.Handle
    Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} attach-pid={1} windows-session-id={2} started={3:o}' -f [DateTimeOffset]::Now, $dailyAttachProcess.Id, $dailyAttachProcess.SessionId, $dailyAttachProcess.StartTime)
    while (-not $dailyAttachProcess.WaitForExit(200)) {
        if (Test-Path -LiteralPath $dailyStopPath) {
            Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} stop-request observed; terminating owned attach only' -f [DateTimeOffset]::Now)
            $dailyAttachProcess.Kill()
            if (-not $dailyAttachProcess.WaitForExit(5000)) { throw 'Owned attach did not terminate.' }
            Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} stopped-owned-attach exit={1}' -f [DateTimeOffset]::Now, $dailyAttachProcess.ExitCode)
            exit 0
        }
        if (Test-Path -LiteralPath $dailyRecreationPath) {
            $requestOwner = [IO.File]::ReadAllText($dailyRecreationPath)
            if ($requestOwner -cnotmatch '\A[0-9a-f]{32}\z' -or $requestOwner -cne $env:DOTFILES_PSMUX_OWNER) {
                Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} stale-or-malformed-recreation-request exit=81' -f [DateTimeOffset]::Now)
                exit 81
            }
            if (Test-Path -LiteralPath $dailyStopPath) { exit 0 }
            if ($dailyServerProcess.HasExited) { throw 'Bound server exited before coordinated kill.' }
            $killResult = Invoke-DailyControl ('kill-session -t ' + $env:DAILY_SESSION)
            if ($killResult.Exit -ne 0) { throw 'Coordinated kill CLI failed.' }
            $dailyCoordinatedKill = $true
            if (-not $dailyAttachProcess.WaitForExit(5000)) { throw 'Attach did not end after coordinated kill.' }
        }
    }
    $dailyChildExit = $dailyAttachProcess.ExitCode
    $dailyErrorText = $dailyErrorRead.GetAwaiter().GetResult()
    if ($dailyErrorText.Length -gt 0) { Add-Content -LiteralPath $dailyLogPath -Value ('attach-stderr: ' + $dailyErrorText.TrimEnd()) }
    Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} attach-child-exit={1} elapsed-ms={2}' -f [DateTimeOffset]::Now, $dailyChildExit, $dailyTimer.ElapsedMilliseconds)
    # An immediately returning attach is not proof of a maintained client.
    if (-not $dailyCoordinatedKill -and $dailyChildExit -eq 0 -and $dailyTimer.ElapsedMilliseconds -lt 2000) { exit 78 }
    if ($dailyChildExit -eq 0) {
        # psmux sends DETACH before the old server finishes shutdown; do not race it.
        if ($null -eq $dailyServerProcess) {
            Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} recreation-refused server-identity-unconfirmed exit=79' -f [DateTimeOffset]::Now)
            exit 79
        }
        $dailyShutdownTimer = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $dailyServerProcess.WaitForExit(200)) {
            if (Test-Path -LiteralPath $dailyStopPath) { exit 0 }
            if ($dailyShutdownTimer.ElapsedMilliseconds -ge 5000) {
                Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} recreation-refused old-server-still-running exit=79' -f [DateTimeOffset]::Now)
                exit 79
            }
        }
        Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} old-server-exited-before-recreation waited-ms={1}' -f [DateTimeOffset]::Now, $dailyShutdownTimer.ElapsedMilliseconds)
        if ($dailyCoordinatedKill) {
            if (Test-Path -LiteralPath $dailyStopPath) { exit 0 }
            Remove-Item -LiteralPath $dailyRecreationPath -ErrorAction Stop
            Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} coordinated-recreation-ready killer-and-server-exited' -f [DateTimeOffset]::Now)
        }
    }
    if (Test-Path -LiteralPath $dailyStopPath) { exit 0 }
    exit $dailyChildExit
}
catch {
    Add-Content -LiteralPath $dailyLogPath -Value ('{0:o} helper-error={1}' -f [DateTimeOffset]::Now, $_.Exception.Message)
    exit 70
}
finally {
    if ($dailyAttachStarted -and -not $dailyAttachProcess.HasExited) {
        # An error must not leave this helper's own attach running unattended.
        $dailyAttachProcess.Kill()
        $null = $dailyAttachProcess.WaitForExit(5000)
    }
    $dailyAttachProcess.Dispose()
    if ($null -ne $dailyServerProcess) { $dailyServerProcess.Dispose() }
}

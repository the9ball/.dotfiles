# Publish a generation-bound request; the monitor alone executes the destructive command.
$ErrorActionPreference = 'Stop'
$runtimeDirectory = Join-Path $env:LOCALAPPDATA 'Dotfiles\PsmuxDaily'
$registryDirectory = Join-Path $runtimeDirectory 'registry'
$requestPath = Join-Path $runtimeDirectory 'recreate.request'
$anchorPath = Join-Path $registryDirectory 'dotfiles-session1__main.pid'
$stagingPath = Join-Path $runtimeDirectory ('recreate.' + [guid]::NewGuid().ToString('N') + '.tmp')
$control = [Diagnostics.Process]::new()
$started = $false
try {
    if ([IO.File]::Exists((Join-Path $runtimeDirectory 'stop.request'))) { throw 'Monitor stop is requested.' }
    if ([IO.File]::Exists($requestPath)) { throw 'A recreation request already exists; inspect it before proceeding.' }
    $anchorBefore = [IO.File]::ReadAllText($anchorPath)
    if ($anchorBefore.Trim() -notmatch '^[1-9][0-9]*:[0-9]+$') { throw 'Server anchor is malformed.' }
    $control.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $control.StartInfo.FileName = & (Join-Path $PSScriptRoot 'resolve-psmux.ps1')
    $control.StartInfo.Arguments = '-L dotfiles-session1 show-environment -t main DOTFILES_PSMUX_OWNER'
    $control.StartInfo.UseShellExecute = $false
    $control.StartInfo.CreateNoWindow = $true
    $control.StartInfo.RedirectStandardOutput = $true
    $control.StartInfo.RedirectStandardError = $true
    $control.StartInfo.EnvironmentVariables['PSMUX_DATA_DIR'] = $registryDirectory
    $control.StartInfo.EnvironmentVariables['PSMUX_NO_WARM'] = '1'
    foreach ($environmentName in @('PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_SESSION_DISPLAY_NAME', 'PSMUX_REMOTE_ATTACH', 'PSMUX_TARGET_SESSION', 'PSMUX_ACTIVE', 'TMUX', 'TMUX_PANE')) {
        $control.StartInfo.EnvironmentVariables.Remove($environmentName)
    }
    if (-not $control.Start()) { throw 'Owner query did not start.' }
    $started = $true
    $null = $control.Handle
    $outputTask = $control.StandardOutput.ReadToEndAsync()
    $errorTask = $control.StandardError.ReadToEndAsync()
    if (-not $control.WaitForExit(7000)) { throw 'Owner query timed out.' }
    if (-not $outputTask.Wait(1000) -or -not $errorTask.Wait(1000)) { throw 'Owner query output did not close.' }
    if ($control.ExitCode -ne 0) { throw ('Owner query failed: ' + $errorTask.Result.TrimEnd()) }
    $ownerMatch = [regex]::Match($outputTask.Result.Trim(), '\ADOTFILES_PSMUX_OWNER=([0-9a-f]{32})\z')
    if (-not $ownerMatch.Success) { throw 'Session owner cookie is missing or malformed.' }
    if ([IO.File]::ReadAllText($anchorPath) -cne $anchorBefore) { throw 'Server generation changed during owner query.' }
    if ([IO.File]::Exists((Join-Path $runtimeDirectory 'stop.request'))) { throw 'Monitor stop is requested.' }
    # Atomic publication prevents the helper from reading a partially written request.
    [IO.File]::WriteAllText($stagingPath, $ownerMatch.Groups[1].Value, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($stagingPath, $requestPath)
    # Publication is committed; a diagnostic failure must not invite another request.
    try {
        Add-Content -LiteralPath (Join-Path $runtimeDirectory 'recreation.requests.log') -Value ('{0:o} submitted owner-query-exit={1} caller-session={2}' -f [DateTimeOffset]::Now, $control.ExitCode, [Diagnostics.Process]::GetCurrentProcess().SessionId)
    }
    catch {
        [Console]::Error.WriteLine('Recreation request was submitted, but request logging failed. Do not resubmit; confirm completion in the monitor logs. ' + $_.Exception.Message)
    }
    Write-Output 'Recreation requested. Confirm completion in the monitor logs; this script does not kill a session.'
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
finally {
    if ($started -and -not $control.HasExited) {
        $control.Kill()
        $null = $control.WaitForExit(5000)
    }
    $control.Dispose()
    if ([IO.File]::Exists($stagingPath)) { [IO.File]::Delete($stagingPath) }
}

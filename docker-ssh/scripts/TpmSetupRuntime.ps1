<# .SYNOPSIS Shares the verified user-only transient stop event and bounded setup-child monitoring. #>
. (Join-Path $PSScriptRoot '../tests/ColdBootEnvironment.ps1')

function Invoke-TpmSetupProcess {
    <# .SYNOPSIS Runs an already path/hash-validated binary; signals before fallible logging on every post-start failure. #>
    param([string] $Executable,[string[]] $Arguments,[string] $KeyRoot,[string] $InstallationId,[hashtable] $EnvironmentValues=@{})
    $stopEvent=New-TpmBootStopEvent -FixtureId $InstallationId
    $process=$null
    try {
        $start=[Diagnostics.ProcessStartInfo]::new($Executable)
        $start.UseShellExecute=$false
        $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true
        $start.RedirectStandardError=$true
        foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        foreach ($name in $EnvironmentValues.Keys) { $start.Environment[$name]=$EnvironmentValues[$name] }
        $process=[Diagnostics.Process]::Start($start)
        $output=$process.StandardOutput.ReadToEndAsync()
        $errors=$process.StandardError.ReadToEndAsync()
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(100)) {
            $process.Refresh()
            if ($process.MainWindowHandle -ne [IntPtr]::Zero -or $timer.Elapsed.TotalSeconds -ge 60) { throw 'Child indeterminate; retain state and establish quiescence.' }
        }
        [void]$output.WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
        [void]$errors.WaitAsync([TimeSpan]::FromSeconds(5)).GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Child failed; preserve partial state; no automatic retry.' }
    } catch {
        # Signal the still-open kernel object before disk operations; it remains sticky while the tool holds its handle.
        [TpmBootStop]::Signal($stopEvent)
        try {
            $marker=Join-Path $KeyRoot 'stop-request.json'
            if (-not (Test-Path -LiteralPath $marker)) {
                $file=[IO.FileStream]::new($marker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read,4096,[IO.FileOptions]::WriteThrough)
                try { $file.Write([Text.Encoding]::UTF8.GetBytes('STOP'));$file.Flush($true) } finally { $file.Dispose() }
            }
        } catch { }
        throw
    } finally { if ($process) { $process.Dispose() };$stopEvent.Dispose() }
}

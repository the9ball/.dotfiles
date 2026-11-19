#requires -Version 7.4
<#
.SYNOPSIS
Checks production startup guards in isolated files without launching psmux or touching Startup.
#>
$ErrorActionPreference = 'Stop'
$repositoryDirectory = Split-Path $PSScriptRoot -Parent
$monitorSource = [IO.File]::ReadAllText((Join-Path $repositoryDirectory 'scripts/windows-psmux-daily/monitor.bat'))
$installerSource = [IO.File]::ReadAllText((Join-Path $repositoryDirectory 'scripts/windows-psmux-daily/install-startup.ps1'))
# Extraction boundaries fail closed if either production startup path changes shape.
$monitorMatch = [regex]::Match($monitorSource, '(?s):loop\r?\n(.*?)set "DOTFILES_PSMUX_OWNER="')
$refusalMatch = [regex]::Match($monitorSource, '(?s)\r?\n(:refuse_recreation\r?\n.*)\z')
$installerMatch = [regex]::Match($installerSource, '(?s)(\$runtimeDirectory = Join-Path \$env:LOCALAPPDATA ''Dotfiles\\PsmuxDaily''\r?\n)(.*?)\$shortcut.TargetPath = \$wscriptPath')
if (-not $monitorMatch.Success -or -not $refusalMatch.Success -or -not $installerMatch.Success) { throw 'Production guard boundaries changed.' }
if ($installerSource.IndexOf('$shortcut.Save()') -lt $installerMatch.Index + $installerMatch.Length) { throw 'Shortcut write precedes guard.' }
$installerGuard = [scriptblock]::Create('param($fixtureRuntime, $StartNow)' + "`n" + '$runtimeDirectory = $fixtureRuntime' + "`n" + $installerMatch.Groups[2].Value)
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('psmux-guards-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixtureRoot)
$fixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
if (-not $fixtureRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture escaped temporary directory.' }
$cases = @('clear', 'stop', 'recreate', 'both', 'malformed', 'request-directory', 'in-flight', 'missing-anchor')
try {
    foreach ($case in $cases) {
        $caseDirectory = Join-Path $fixtureRoot $case
        $null = [IO.Directory]::CreateDirectory($caseDirectory)
        $requestPath = Join-Path $caseDirectory 'recreate.request'
        $stopPath = Join-Path $caseDirectory 'stop.request'
        $hasRequest = $case -notin @('clear', 'stop')
        $hasStop = $case -in @('stop', 'both')
        if ($case -eq 'request-directory') { $null = [IO.Directory]::CreateDirectory($requestPath) }
        elseif ($hasRequest) { [IO.File]::WriteAllText($requestPath, $(if ($case -eq 'malformed') { 'invalid' } else { 'a' * 32 })) }
        if ($hasStop) { [IO.File]::WriteAllText($stopPath, 'keep-stop') }
        if ($case -eq 'in-flight') {
            # These inert markers model a generation and a publisher that must not be inferred stale.
            [IO.File]::WriteAllText((Join-Path $caseDirectory 'main.pid'), '123:456')
            [IO.File]::WriteAllText((Join-Path $caseDirectory 'publisher.fixture'), 'publication-pending')
        }
        $requestHash = if ($hasRequest -and $case -ne 'request-directory') { (Get-FileHash -LiteralPath $requestPath).Hash } else { $null }
        foreach ($startNow in @($false, $true)) {
            $failure = $null
            try { & $installerGuard $caseDirectory $startNow }
            catch { $failure = $_.Exception.Message }
            $shouldRefuse = $startNow -and ($hasRequest -or $hasStop)
            if (($null -ne $failure) -ne $shouldRefuse) { throw "Installer guard mismatch: $case StartNow=$startNow" }
            if ($shouldRefuse) {
                $expectedReason = if ($hasStop) { 'stop.request' } else { 'recreate.request' }
                if (-not $failure.Contains($expectedReason)) { throw "Installer missing reason: $case" }
            }
        }
        $batchPath = Join-Path $caseDirectory 'guard.bat'
        $batchSource = "@echo off`r`nsetlocal EnableExtensions DisableDelayedExpansion`r`n" + $monitorMatch.Groups[1].Value + "echo fixture-start-permitted`r`nexit /b 0`r`n" + $refusalMatch.Groups[1].Value
        $batchSource = $batchSource.Replace("`r`n", "`n").Replace("`n", "`r`n")
        [IO.File]::WriteAllText($batchPath, $batchSource, [Text.ASCIIEncoding]::new())
        $outputPath = Join-Path $caseDirectory 'stdout.txt'
        $errorPath = Join-Path $caseDirectory 'stderr.txt'
        $logPath = Join-Path $caseDirectory 'monitor.log'
        $process = $null
        try {
            $childEnvironment = @{ DAILY_RUNTIME_DIRECTORY = $caseDirectory; DAILY_STOP_FILE = $stopPath; DAILY_LOG = $logPath }
            $process = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c ""{0}""' -f $batchPath) -Environment $childEnvironment -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
            $null = $process.Handle
            if (-not $process.WaitForExit(5000)) { throw "Fixture guard timed out: $case" }
            $expectedExit = if ($hasRequest -and -not $hasStop) { 81 } else { 0 }
            if ($process.ExitCode -ne $expectedExit) { throw "Monitor exit mismatch: $case ($($process.ExitCode)): $([IO.File]::ReadAllText($errorPath))" }
            $permitted = [IO.File]::ReadAllText($outputPath).Contains('fixture-start-permitted')
            if ($permitted -ne (-not $hasRequest -and -not $hasStop)) { throw "Monitor bypassed guard: $case" }
            if ($expectedExit -eq 81 -and (-not (Test-Path -LiteralPath $logPath) -or
                    -not [IO.File]::ReadAllText($logPath).Contains('startup-refused recreate.request-present exit=81'))) { throw "Monitor missing diagnostic: $case" }
        }
        finally {
            if ($null -ne $process) {
                if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
                $process.Dispose()
            }
        }
        if ((Test-Path -LiteralPath $requestPath) -ne $hasRequest) { throw "Request presence changed: $case" }
        if ($null -ne $requestHash -and (Get-FileHash -LiteralPath $requestPath).Hash -cne $requestHash) { throw "Request generation changed: $case" }
        if ($hasStop -and [IO.File]::ReadAllText($stopPath) -cne 'keep-stop') { throw "Stop request changed: $case" }
        if ($case -eq 'in-flight' -and ([IO.File]::ReadAllText((Join-Path $caseDirectory 'publisher.fixture')) -cne 'publication-pending' -or
                [IO.File]::ReadAllText((Join-Path $caseDirectory 'main.pid')) -cne '123:456')) { throw 'In-flight markers changed.' }
        Write-Output "PASS $case (installer StartNow/registration and monitor guard)"
    }
    Write-Output '8 fixture states / 24 guard cases passed; no live psmux, Startup or request recovery invoked.'
}
finally {
    # The checked absolute target is the unique directory created by this fixture.
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}

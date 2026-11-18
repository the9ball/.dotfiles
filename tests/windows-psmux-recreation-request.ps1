#requires -Version 7.4
<#
.SYNOPSIS
Checks request publication boundaries using isolated files and an in-process owner-query facade.
#>
param([string]$FixtureDirectory)

$ErrorActionPreference = 'Stop'

class RequestTestProcess {
    [Diagnostics.ProcessStartInfo]$StartInfo
    [IO.StringReader]$StandardOutput = [IO.StringReader]::new(('DOTFILES_PSMUX_OWNER=' + ('a' * 32)))
    [IO.StringReader]$StandardError = [IO.StringReader]::new('fixture query failure')
    [int]$ExitCode = 0
    [bool]$HasExited = $true
    [IntPtr]$Handle = [IntPtr]::new(1)

    <#
    .SYNOPSIS
    Emulates an owner query without starting psmux or any other process.
    #>
    [bool] Start() {
        $runtime = [IO.Directory]::GetParent($this.StartInfo.EnvironmentVariables['PSMUX_DATA_DIR']).FullName
        if ($this.StartInfo.FileName -ne 'fixture-owner-query') { throw 'Unexpected query executable.' }
        if ($this.StartInfo.Arguments -ne '-L dotfiles-session1 show-environment -t main DOTFILES_PSMUX_OWNER') { throw 'Unexpected query arguments.' }
        if ([IO.File]::Exists((Join-Path $runtime 'query-failure.fixture'))) { $this.ExitCode = 1 }
        if ([IO.File]::Exists((Join-Path $runtime 'publication-conflict.fixture'))) {
            [IO.File]::WriteAllText((Join-Path $runtime 'recreate.request'), 'another-request')
        }
        return $true
    }

    <#
    .SYNOPSIS
    Reports the synchronous facade as exited for the production bounded wait.
    #>
    [bool] WaitForExit([int]$milliseconds) { return $true }

    <#
    .SYNOPSIS
    Rejects attempts to terminate a process because this facade creates none.
    #>
    [void] Kill() { throw 'The owner-query facade must never be killed.' }

    <#
    .SYNOPSIS
    Releases the two fixture output readers.
    #>
    [void] Dispose() {
        $this.StandardOutput.Dispose()
        $this.StandardError.Dispose()
    }
}

if ($FixtureDirectory) {
    $global:LASTEXITCODE = 0
    & (Join-Path $FixtureDirectory 'request-recreation.ps1')
    exit $LASTEXITCODE
}

$sourcePath = Join-Path $PSScriptRoot '..\scripts\windows-psmux-daily\request-recreation.ps1'
$source = [IO.File]::ReadAllText($sourcePath)
$processCreation = '$control = [Diagnostics.Process]::new()'
if ([regex]::Matches($source, [regex]::Escape($processCreation)).Count -ne 1) { throw 'Owner-query injection seam changed.' }
$fixtureSource = $source.Replace($processCreation, '$control = [RequestTestProcess]::new()')
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('psmux-request-test-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testDirectory)
$retainFixture = $false
$cases = @('success', 'log-failure', 'stop-before-publication', 'malformed-anchor', 'query-failure', 'publication-conflict', 'existing-request')
try {
    foreach ($case in $cases) {
        $fixture = Join-Path $testDirectory $case
        $runtime = Join-Path $fixture 'Dotfiles\PsmuxDaily'
        $registry = Join-Path $runtime 'registry'
        $null = [IO.Directory]::CreateDirectory($registry)
        [IO.File]::WriteAllText((Join-Path $fixture 'request-recreation.ps1'), $fixtureSource, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $fixture 'resolve-psmux.ps1'), "'fixture-owner-query'", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $registry 'dotfiles-session1__main.pid'), '123:456')
        switch ($case) {
            'log-failure' { $null = [IO.Directory]::CreateDirectory((Join-Path $runtime 'recreation.requests.log')) }
            'stop-before-publication' { [IO.File]::WriteAllText((Join-Path $runtime 'stop.request'), '') }
            'malformed-anchor' { [IO.File]::WriteAllText((Join-Path $registry 'dotfiles-session1__main.pid'), 'invalid') }
            'query-failure' { [IO.File]::WriteAllText((Join-Path $runtime 'query-failure.fixture'), '') }
            'publication-conflict' { [IO.File]::WriteAllText((Join-Path $runtime 'publication-conflict.fixture'), '') }
            'existing-request' { [IO.File]::WriteAllText((Join-Path $runtime 'recreate.request'), 'another-request') }
        }
        $process = $null
        try {
            $inputPath = Join-Path $fixture 'stdin.txt'
            $outputPath = Join-Path $fixture 'stdout.txt'
            $errorPath = Join-Path $fixture 'stderr.txt'
            [IO.File]::WriteAllText($inputPath, '')
            $arguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -FixtureDirectory "{1}"' -f $PSCommandPath, $fixture
            $retainFixture = $true
            $process = Start-Process -FilePath ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -ArgumentList $arguments -Environment @{ LOCALAPPDATA = $fixture } -WindowStyle Hidden -PassThru -RedirectStandardInput $inputPath -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
            $null = $process.Handle
            Write-Output ('Fixture {0}: pid={1} started={2:o} stdin=empty-file/EOF deadline=15000ms' -f $case, $process.Id, $process.StartTime)
            if (-not $process.WaitForExit(15000)) {
                # This retained handle owns only the noninteractive fixture, which creates no children.
                $process.Kill()
                if ($process.WaitForExit(5000)) { $retainFixture = $false }
                throw "Fixture timed out: $case"
            }
            $retainFixture = $false
            $output = [IO.File]::ReadAllText($outputPath)
            $errorOutput = [IO.File]::ReadAllText($errorPath)
            $request = Join-Path $runtime 'recreate.request'
            if ($case -in @('success', 'log-failure')) {
                if ($process.ExitCode -ne 0 -or [IO.File]::ReadAllText($request) -cne ('a' * 32)) { throw "Publication failed: $case" }
                if ($output -notmatch 'Recreation requested') { throw "Missing submission confirmation: $case" }
                if ($case -eq 'log-failure') {
                    if ($errorOutput -notmatch 'was submitted.*Do not resubmit') { throw 'Missing published-but-unlogged warning.' }
                }
                elseif ($errorOutput -or [IO.File]::ReadAllText((Join-Path $runtime 'recreation.requests.log')) -notmatch 'submitted') {
                    throw 'Successful publication was not logged cleanly.'
                }
            }
            else {
                if ($process.ExitCode -ne 1 -or $output -match 'Recreation requested') { throw "Pre-publication failure was not reported: $case" }
                if ($case -in @('publication-conflict', 'existing-request')) {
                    if ([IO.File]::ReadAllText($request) -cne 'another-request') { throw 'Existing request was replaced.' }
                }
                elseif ([IO.File]::Exists($request)) { throw "Failed request was published: $case" }
                if ([IO.File]::Exists((Join-Path $runtime 'recreation.requests.log'))) { throw 'Failed publication was logged as submitted.' }
            }
            if ([IO.Directory]::GetFiles($runtime, 'recreate.*.tmp').Length -ne 0) { throw 'Staging file leaked.' }
            Write-Output "PASS $case"
        }
        finally {
            if ($null -ne $process) { $process.Dispose() }
        }
    }
}
finally {
    $resolved = [IO.Path]::GetFullPath($testDirectory)
    if ([IO.Path]::GetDirectoryName($resolved).TrimEnd('\') -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($resolved) -notlike 'psmux-request-test-*') { throw 'Unexpected fixture cleanup path.' }
    if ($retainFixture) { Write-Warning "Fixture retained because child exit is unconfirmed: $resolved" }
    else { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

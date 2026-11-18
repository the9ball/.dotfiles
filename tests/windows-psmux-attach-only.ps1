#requires -Version 7.4
# Run against an installed psmux; no real session is created or terminated.
param(
    [Parameter(Mandatory = $true)][string]$PsmuxExecutable,
    [int]$RequiredSessionId = -1
)

$ErrorActionPreference = 'Stop'
$callerSessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
if ($RequiredSessionId -ge 0 -and $callerSessionId -ne $RequiredSessionId) {
    throw "Expected Windows Session $RequiredSessionId, got $callerSessionId."
}
if (-not [IO.Path]::IsPathRooted($PsmuxExecutable) -or
    -not [IO.File]::Exists($PsmuxExecutable)) {
    throw 'Supply the absolute path of the installed psmux executable.'
}

function Get-PsmuxProcessIdentities {
    <# .SYNOPSIS
    Snapshot process identities without contacting or terminating a psmux server.
    #>
    $identities = [Collections.Generic.List[string]]::new()
    foreach ($process in [Diagnostics.Process]::GetProcessesByName('psmux')) {
        try {
            $identities.Add(('{0}:{1}' -f $process.Id, $process.StartTime.ToFileTimeUtc()))
        }
        finally { $process.Dispose() }
    }
    return $identities.ToArray()
}

function Invoke-MissingSessionAttach {
    <# .SYNOPSIS
    Run the production attach arguments in an isolated home and registry.
    .DESCRIPTION
    Only a timed-out probe client may be terminated through its retained handle.
    Server processes and pre-existing clients are never selected for termination.
    #>
    param([string]$HomeDirectory, [string]$RegistryDirectory, [string]$Namespace, [bool]$OverrideConfig)
    $process = $null
    $outputPath = Join-Path $HomeDirectory 'attach.stdout'
    $errorPath = Join-Path $HomeDirectory 'attach.stderr'
    try {
        $childEnvironment = @{
            HOME = $HomeDirectory
            USERPROFILE = $HomeDirectory
            LOCALAPPDATA = $HomeDirectory
            PSMUX_DATA_DIR = $RegistryDirectory
            PSMUX_NO_WARM = '1'
            PSMUX_CONFIG_FILE = $null
        }
        # -f must override even an inherited configuration that requests creation.
        if ($OverrideConfig) {
            $childEnvironment['PSMUX_CONFIG_FILE'] = Join-Path $HomeDirectory 'override.conf'
        }
        foreach ($name in @('PSMUX_SESSION', 'PSMUX_SESSION_NAME', 'PSMUX_SESSION_DISPLAY_NAME',
                'PSMUX_REMOTE_ATTACH', 'PSMUX_TARGET_SESSION', 'PSMUX_ACTIVE', 'TMUX', 'TMUX_PANE')) {
            $childEnvironment[$name] = $null
        }
        # File redirection avoids the sandbox's unavailable named-pipe output transport.
        $arguments = '-f NUL -L ' + $Namespace + ' attach -t main'
        $process = Start-Process -FilePath $PsmuxExecutable -ArgumentList $arguments -Environment $childEnvironment `
            -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
        $null = $process.Handle
        if (-not $process.WaitForExit(10000)) { throw 'Probe client timed out.' }
        $response = [IO.File]::ReadAllText($outputPath) + [IO.File]::ReadAllText($errorPath)
        if ($process.ExitCode -ne 1 -or $response -notmatch "can't find session: main") {
            throw ('Expected missing-session exit 1, got {0}: {1}' -f $process.ExitCode, $response)
        }
    }
    finally {
        if ($null -ne $process) {
            if (-not $process.HasExited) {
                $process.Kill()
                $null = $process.WaitForExit(5000)
            }
            $process.Dispose()
        }
    }
}

$fixtureName = 'psmux-attach-only-' + [guid]::NewGuid().ToString('N')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) $fixtureName
$namespace = 'attach-only-' + [guid]::NewGuid().ToString('N')
$initialProcesses = @(Get-PsmuxProcessIdentities)
$completed = $false
try {
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    foreach ($configName in @('override.conf', '.psmux.conf', '.psmuxrc', '.tmux.conf', '.config/psmux/psmux.conf')) {
        $caseDirectory = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
        $homeDirectory = Join-Path $caseDirectory 'home'
        $registryDirectory = Join-Path $caseDirectory 'registry'
        $configPath = Join-Path $homeDirectory $configName
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($configPath))
        [void][IO.Directory]::CreateDirectory($registryDirectory)
        [IO.File]::WriteAllText($configPath, "new-session -d -s main`n", [Text.UTF8Encoding]::new($false))
        Invoke-MissingSessionAttach $homeDirectory $registryDirectory $namespace ($configName -eq 'override.conf')
        foreach ($registryEntry in [IO.Directory]::EnumerateFileSystemEntries($registryDirectory)) {
            # Listing sessions may touch its sweep stamp without creating a server.
            if ([IO.Path]::GetFileName($registryEntry) -cne '.registry_sweep' -or
                -not [IO.File]::Exists($registryEntry)) {
                throw 'Unexpected registry state; fixture retained for inspection.'
            }
        }
        foreach ($identity in @(Get-PsmuxProcessIdentities)) {
            if ($initialProcesses -notcontains $identity) {
                throw 'A new psmux process remains; no server will be terminated by this test.'
            }
        }
        Write-Output ('PASS config={0} session={1} exit=1 no-server-registry no-new-psmux' -f $configName, $callerSessionId)
    }
    $completed = $true
}
finally {
    if ($completed) {
        $resolvedFixture = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($fixtureRoot))
        $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($resolvedFixture.Parent.FullName -ine $temporaryRoot -or $resolvedFixture.Name -cne $fixtureName -or
            ($resolvedFixture.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Fixture cleanup boundary mismatch.'
        }
        foreach ($entry in Get-ChildItem -LiteralPath $fixtureRoot -Recurse -Force) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Unexpected reparse point; fixture retained.'
            }
        }
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
    else { [Console]::Error.WriteLine('Fixture retained: ' + $fixtureRoot) }
}

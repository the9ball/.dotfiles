[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$JobId,

    [Alias('f')]
    [switch]$Follow,

    [ValidateRange(1, 5000)]
    [int]$TailLineCount = 100,

    [ValidateRange(100, 60000)]
    [int]$PollIntervalMilliseconds = 2000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JobRecord {
    param(
        [Parameter(Mandatory)]
        [string]$JobRecordPath
    )

    for ($AttemptNumber = 1; $AttemptNumber -le 5; $AttemptNumber++) {
        try {
            return Get-Content -Raw -LiteralPath $JobRecordPath | ConvertFrom-Json
        }
        catch {
            if ($AttemptNumber -eq 5) {
                throw
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Find-JobRecordPath {
    param(
        [Parameter(Mandatory)]
        [string]$RequestedJobId
    )

    $SearchRootPaths = [System.Collections.Generic.List[string]]::new()

    if ($env:CLAUDE_PLUGIN_DATA) {
        $SearchRootPaths.Add($env:CLAUDE_PLUGIN_DATA)
    }

    $UserProfilePath = if ($env:USERPROFILE) {
        $env:USERPROFILE
    }
    else {
        [Environment]::GetFolderPath('UserProfile')
    }
    $ClaudePluginDataPath = Join-Path $UserProfilePath '.claude\plugins\data'
    if (Test-Path -LiteralPath $ClaudePluginDataPath) {
        $SearchRootPaths.Add($ClaudePluginDataPath)
    }

    $TemporaryRootPath = if ($env:TEMP) {
        $env:TEMP
    }
    else {
        [IO.Path]::GetTempPath()
    }
    $TemporaryCompanionPath = Join-Path $TemporaryRootPath 'codex-companion'
    if (Test-Path -LiteralPath $TemporaryCompanionPath) {
        $SearchRootPaths.Add($TemporaryCompanionPath)
    }

    $MatchingJobFiles = foreach ($SearchRootPath in $SearchRootPaths | Select-Object -Unique) {
        Get-ChildItem -LiteralPath $SearchRootPath -Recurse -File -Filter "$RequestedJobId.json" -ErrorAction SilentlyContinue
    }

    $VerifiedJobFiles = foreach ($MatchingJobFile in $MatchingJobFiles) {
        try {
            $JobRecord = Read-JobRecord -JobRecordPath $MatchingJobFile.FullName
            if ($JobRecord.id -eq $RequestedJobId) {
                $MatchingJobFile
            }
        }
        catch {
            continue
        }
    }

    $SelectedJobFile = $VerifiedJobFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $SelectedJobFile) {
        throw "No codex-companion job record found for '$RequestedJobId'."
    }

    return $SelectedJobFile.FullName
}

function Read-LogContent {
    param(
        [Parameter(Mandatory)]
        [string]$LogFilePath,

        [ValidateRange(0, [long]::MaxValue)]
        [long]$StartPosition = 0
    )

    if (-not (Test-Path -LiteralPath $LogFilePath)) {
        return [pscustomobject]@{
            Text = ''
            NextPosition = 0L
        }
    }

    $LogStream = [IO.File]::Open(
        $LogFilePath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )

    try {
        if ($LogStream.Length -lt $StartPosition) {
            $StartPosition = 0
        }

        [void]$LogStream.Seek($StartPosition, [IO.SeekOrigin]::Begin)
        $LogReader = [IO.StreamReader]::new($LogStream, [Text.UTF8Encoding]::new($false), $true, 4096, $true)
        try {
            $NewText = $LogReader.ReadToEnd()
        }
        finally {
            $LogReader.Dispose()
        }

        return [pscustomobject]@{
            Text = $NewText
            NextPosition = $LogStream.Length
        }
    }
    finally {
        $LogStream.Dispose()
    }
}

function Write-LogTail {
    param(
        [Parameter(Mandatory)]
        [string]$LogText,

        [Parameter(Mandatory)]
        [int]$LineCount
    )

    if (-not $LogText) {
        return
    }

    $LogLines = [regex]::Split($LogText, '\r?\n')
    if ($LogLines.Count -gt 0 -and $LogLines[-1] -eq '') {
        $LogLines = $LogLines[0..($LogLines.Count - 2)]
    }

    $FirstLineIndex = [Math]::Max(0, $LogLines.Count - $LineCount)
    for ($LineIndex = $FirstLineIndex; $LineIndex -lt $LogLines.Count; $LineIndex++) {
        [Console]::Out.WriteLine($LogLines[$LineIndex])
    }
}

function Test-TerminalStatus {
    param(
        [AllowNull()]
        [string]$Status
    )

    return $Status -in @('completed', 'failed', 'cancelled')
}

$JobRecordPath = Find-JobRecordPath -RequestedJobId $JobId
$JobRecord = Read-JobRecord -JobRecordPath $JobRecordPath

[Console]::Out.WriteLine("Job: $($JobRecord.id)")
[Console]::Out.WriteLine("Status: $($JobRecord.status)")
if ($JobRecord.phase) {
    [Console]::Out.WriteLine("Phase: $($JobRecord.phase)")
}

$LogFilePath = if ($JobRecord.logFile) { [string]$JobRecord.logFile } else { '' }
if ($LogFilePath) {
    [Console]::Out.WriteLine("Log: $LogFilePath")
}
else {
    [Console]::Out.WriteLine('Log: not created yet')
}
[Console]::Out.WriteLine('')

while (-not $LogFilePath -and $Follow -and -not (Test-TerminalStatus -Status $JobRecord.status)) {
    Start-Sleep -Milliseconds $PollIntervalMilliseconds
    $JobRecord = Read-JobRecord -JobRecordPath $JobRecordPath
    $LogFilePath = if ($JobRecord.logFile) { [string]$JobRecord.logFile } else { '' }
}

if (-not $LogFilePath -or -not (Test-Path -LiteralPath $LogFilePath)) {
    if ($Follow) {
        [Console]::Out.WriteLine("Job finished with status '$($JobRecord.status)' before a log file was created.")
    }
    exit 0
}

$InitialLogContent = Read-LogContent -LogFilePath $LogFilePath
Write-LogTail -LogText $InitialLogContent.Text -LineCount $TailLineCount
$NextLogPosition = $InitialLogContent.NextPosition

if (-not $Follow) {
    exit 0
}

while ($true) {
    Start-Sleep -Milliseconds $PollIntervalMilliseconds

    $NewLogContent = Read-LogContent -LogFilePath $LogFilePath -StartPosition $NextLogPosition
    if ($NewLogContent.Text) {
        [Console]::Out.Write($NewLogContent.Text)
    }
    $NextLogPosition = $NewLogContent.NextPosition

    $JobRecord = Read-JobRecord -JobRecordPath $JobRecordPath
    if (Test-TerminalStatus -Status $JobRecord.status) {
        Start-Sleep -Milliseconds 500
        $FinalLogContent = Read-LogContent -LogFilePath $LogFilePath -StartPosition $NextLogPosition
        if ($FinalLogContent.Text) {
            [Console]::Out.Write($FinalLogContent.Text)
        }
        [Console]::Out.WriteLine('')
        [Console]::Out.WriteLine("Job finished: $($JobRecord.status)")
        break
    }
}

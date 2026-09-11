#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateRange(100, 60000)]
    [int]$PollIntervalMilliseconds = 2000,

    [switch]$Once,

    [string]$HelperScriptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDirectory = Split-Path -Parent $ScriptDirectory

function Resolve-CodexHome {
    <#
    .SYNOPSIS
    Resolves the Codex home used by this watcher process.

    .OUTPUTS
    System.String. Returns an absolute Codex home path, or null when the
    configured path cannot be resolved.

    .NOTES
    The watcher inherits the active session's process environment and never
    selects a home from a target UUID or from another provider.
    #>
    $ConfiguredHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    if ([string]::IsNullOrWhiteSpace($ConfiguredHome)) {
        $UserProfile = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($UserProfile)) {
            return $null
        }

        $ConfiguredHome = Join-Path $UserProfile '.codex'
    }

    try {
        $ResolvedHome = [IO.Path]::GetFullPath($ConfiguredHome)
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($ResolvedHome)) {
        return $null
    }

    return $ResolvedHome
}

$CodexHome = Resolve-CodexHome
$StateDirectory = if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    Join-Path $SkillDirectory '.task-complete-notify.invalid'
}
else {
    Join-Path $CodexHome '.task-complete-notify'
}
$RequestDirectory = Join-Path $StateDirectory 'requests'
$LockDirectory = Join-Path $StateDirectory 'locks'
$CheckpointDirectory = Join-Path $StateDirectory 'checkpoints'
$TerminalDirectory = Join-Path $StateDirectory 'terminal'
$WatcherLockPath = Join-Path $StateDirectory 'watcher.lock'
$CoordinationLockPath = Join-Path $StateDirectory 'coordination.lock'
$HelperPath = if ([string]::IsNullOrWhiteSpace($HelperScriptPath)) {
    Join-Path $ScriptDirectory 'windows-helper.ps1'
}
else {
    [IO.Path]::GetFullPath($HelperScriptPath)
}

function Get-JsonProperty {
    <#
    .SYNOPSIS
    Reads one optional property from a JSON-derived object.

    .PARAMETER InputObject
    The parsed JSON object.

    .PARAMETER Name
    The exact property name to read.

    .OUTPUTS
    System.Object. Returns the property value or null when absent.
    #>
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [Collections.IDictionary] -and $InputObject.Contains($Name)) {
        return $InputObject[$Name]
    }

    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }

    return $Property.Value
}

function Normalize-CodexThreadId {
    <#
    .SYNOPSIS
    Normalizes a canonical Codex thread URI or raw UUID.

    .PARAMETER InputValue
    The canonical `codex://threads/<UUID>` value or raw UUID shorthand.

    .OUTPUTS
    System.String. Returns a lowercase UUID, or null for invalid input.
    #>
    param(
        [AllowNull()]
        [object]$InputValue
    )

    $TextValue = if ($null -eq $InputValue) { '' } else { [string]$InputValue }
    $UuidText = $null
    if ($TextValue -match '^codex://threads/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$') {
        $UuidText = $Matches[1]
    }
    elseif ($TextValue -match '^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$') {
        $UuidText = $Matches[1]
    }
    else {
        return $null
    }

    $GuidValue = [Guid]::Empty
    if (-not [Guid]::TryParse($UuidText, [ref]$GuidValue)) {
        return $null
    }

    return $GuidValue.ToString('D').ToLowerInvariant()
}

function Get-CodexSessionsDirectory {
    <#
    .SYNOPSIS
    Returns the sessions directory under the watcher home.

    .OUTPUTS
    System.String. Returns the resolved sessions path, or null for an invalid
    home.
    #>
    if ([string]::IsNullOrWhiteSpace($CodexHome)) {
        return $null
    }

    return (Join-Path $CodexHome 'sessions')
}

function Initialize-WatcherDirectories {
    <#
    .SYNOPSIS
    Creates the runtime state directories under the resolved Codex home.

    .OUTPUTS
    None. Directory creation is a local side effect.
    #>
    if ([string]::IsNullOrWhiteSpace($CodexHome) -or
        -not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
        throw 'codex_home_invalid'
    }

    foreach ($DirectoryPath in @($StateDirectory, $RequestDirectory, $LockDirectory, $CheckpointDirectory, $TerminalDirectory)) {
        New-Item -ItemType Directory -Force -Path $DirectoryPath | Out-Null
    }
}

function Acquire-WatcherLock {
    <#
    .SYNOPSIS
    Acquires the watcher process lifetime lock.

    .OUTPUTS
    System.IO.FileStream. Returns an exclusive stream, or null when another
    watcher already owns it.

    .NOTES
    The open stream is the ownership proof; marker-file existence alone is not.
    #>
    try {
        return [IO.File]::Open(
            $WatcherLockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        return $null
    }
    catch {
        return $null
    }
}

function Acquire-CoordinationLock {
    <#
    .SYNOPSIS
    Acquires the short-lived lock shared with arm operations.

    .PARAMETER TimeoutMilliseconds
    Maximum time to wait for the lock.

    .OUTPUTS
    System.IO.FileStream. Returns an exclusive stream, or null on timeout.
    #>
    param(
        [ValidateRange(0, 120000)]
        [int]$TimeoutMilliseconds = 10000
    )

    $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($Stopwatch.ElapsedMilliseconds -le $TimeoutMilliseconds) {
        try {
            return [IO.File]::Open(
                $CoordinationLockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
        catch {
            return $null
        }
    }

    return $null
}

function Get-ThreadLockPath {
    <#
    .SYNOPSIS
    Builds the per-thread lock path for checkpoint publication.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .OUTPUTS
    System.String. Returns the lock path.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    return (Join-Path $LockDirectory "$ThreadId.lock")
}

function Acquire-ThreadLock {
    <#
    .SYNOPSIS
    Acquires a short-lived exclusive lock for one checkpoint update.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .PARAMETER TimeoutMilliseconds
    Maximum time to wait for the lock.

    .OUTPUTS
    System.IO.FileStream. Returns an exclusive stream or null on timeout.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [ValidateRange(0, 120000)]
        [int]$TimeoutMilliseconds = 10000
    )

    $LockPath = Get-ThreadLockPath -ThreadId $ThreadId
    $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($Stopwatch.ElapsedMilliseconds -le $TimeoutMilliseconds) {
        try {
            return [IO.File]::Open(
                $LockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
        catch {
            return $null
        }
    }

    return $null
}

function Read-JsonDocument {
    <#
    .SYNOPSIS
    Reads one local JSON document without emitting its contents.

    .PARAMETER Path
    The JSON path to read.

    .OUTPUTS
    System.Object. Returns the parsed document or null when absent/invalid.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-AtomicJsonDocument {
    <#
    .SYNOPSIS
    Publishes one checkpoint JSON document atomically.

    .PARAMETER Path
    The destination JSON path.

    .PARAMETER Document
    The object to serialize.

    .OUTPUTS
    None. The destination is replaced atomically on success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Document
    )

    $DirectoryPath = Split-Path -Parent $Path
    $FileName = Split-Path -Leaf $Path
    $TemporaryPath = Join-Path $DirectoryPath ".${FileName}.$([Guid]::NewGuid().ToString('N')).tmp"
    $BackupPath = Join-Path $DirectoryPath ".${FileName}.$([Guid]::NewGuid().ToString('N')).bak"
    try {
        $JsonText = $Document | ConvertTo-Json -Depth 20 -Compress
        [IO.File]::WriteAllText(
            $TemporaryPath,
            "$JsonText`n",
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($TemporaryPath, $Path, $BackupPath, $true)
            Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
        else {
            [IO.File]::Move($TemporaryPath, $Path)
        }
    }
    catch {
        # A later rescan can recover a transient checkpoint write failure.
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
            Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ActiveRequests {
    <#
    .SYNOPSIS
    Loads all currently armed Codex request documents.

    .OUTPUTS
    PSCustomObject[]. Returns sanitized request metadata for local processing.
    #>
    $Requests = @()
    if (-not (Test-Path -LiteralPath $RequestDirectory -PathType Container)) {
        return $Requests
    }

    foreach ($RequestFile in Get-ChildItem -LiteralPath $RequestDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        $State = Read-JsonDocument -Path $RequestFile.FullName
        if ($null -eq $State) {
            continue
        }

        if ([string](Get-JsonProperty -InputObject $State -Name 'provider') -ne 'codex' -or
            [string](Get-JsonProperty -InputObject $State -Name 'status') -ne 'armed') {
            continue
        }

        $Target = Get-JsonProperty -InputObject $State -Name 'target'
        $ThreadId = Normalize-CodexThreadId -InputValue (Get-JsonProperty -InputObject $Target -Name 'threadId')
        if ($null -eq $ThreadId) {
            continue
        }

        $Requests += [pscustomobject]@{
            ThreadId = $ThreadId
            State = $State
            RequestPath = $RequestFile.FullName
            CheckpointPath = Join-Path $CheckpointDirectory "$ThreadId.json"
        }
    }

    return $Requests
}

function Read-Checkpoint {
    <#
    .SYNOPSIS
    Reads one thread's persistent rollout offsets and arm timestamp.

    .PARAMETER Request
    An active request object from Get-ActiveRequests.

    .OUTPUTS
    PSCustomObject. Returns thread ID, arm timestamp, and a case-insensitive
    path-to-offset map.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Request
    )

    $Offsets = [Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    $Checkpoint = Read-JsonDocument -Path $Request.CheckpointPath
    $ArmedAtUtc = [string](Get-JsonProperty -InputObject $Request.State -Name 'armedAtUtc')
    $Generation = [string](Get-JsonProperty -InputObject $Request.State -Name 'generation')

    if ($null -ne $Checkpoint) {
        $CheckpointProvider = [string](Get-JsonProperty -InputObject $Checkpoint -Name 'provider')
        $CheckpointGeneration = [string](Get-JsonProperty -InputObject $Checkpoint -Name 'generation')
        $CheckpointTarget = Get-JsonProperty -InputObject $Checkpoint -Name 'target'
        $CheckpointThreadId = Normalize-CodexThreadId -InputValue (Get-JsonProperty -InputObject $CheckpointTarget -Name 'threadId')
        if ($CheckpointProvider -eq 'codex' -and
            $CheckpointGeneration -eq $Generation -and
            $CheckpointThreadId -eq $Request.ThreadId) {
            $CheckpointArmedAt = [string](Get-JsonProperty -InputObject $Checkpoint -Name 'armedAtUtc')
            if (-not [string]::IsNullOrWhiteSpace($CheckpointArmedAt)) {
                $ArmedAtUtc = $CheckpointArmedAt
            }

            foreach ($FileEntry in @((Get-JsonProperty -InputObject $Checkpoint -Name 'files'))) {
                $FilePath = [string](Get-JsonProperty -InputObject $FileEntry -Name 'path')
                $OffsetValue = Get-JsonProperty -InputObject $FileEntry -Name 'offset'
                $Offset = 0L
                if ([string]::IsNullOrWhiteSpace($FilePath) -or
                    $null -eq $OffsetValue -or
                    -not [long]::TryParse([string]$OffsetValue, [ref]$Offset) -or
                    $Offset -lt 0) {
                    continue
                }
                $Offsets[$FilePath] = $Offset
            }
        }
    }

    return [pscustomobject]@{
        ThreadId = $Request.ThreadId
        Generation = $Generation
        ArmedAtUtc = $ArmedAtUtc
        Offsets = $Offsets
    }
}

function Save-Checkpoint {
    <#
    .SYNOPSIS
    Persists the current rollout offsets for one active request.

    .PARAMETER Request
    The active request metadata.

    .PARAMETER Checkpoint
    The checkpoint object returned by Read-Checkpoint.

    .OUTPUTS
    None. The checkpoint is atomically written to the resolved home state directory.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Request,

        [Parameter(Mandatory)]
        [object]$Checkpoint
    )

    $ThreadLockStream = $null
    try {
        $ThreadLockStream = Acquire-ThreadLock -ThreadId $Request.ThreadId
        if ($null -eq $ThreadLockStream) {
            return
        }

        $CurrentState = Read-JsonDocument -Path $Request.RequestPath
        if ($null -eq $CurrentState) {
            return
        }

        $CurrentProvider = [string](Get-JsonProperty -InputObject $CurrentState -Name 'provider')
        $CurrentStatus = [string](Get-JsonProperty -InputObject $CurrentState -Name 'status')
        $CurrentTarget = Get-JsonProperty -InputObject $CurrentState -Name 'target'
        $CurrentThreadId = Normalize-CodexThreadId -InputValue (Get-JsonProperty -InputObject $CurrentTarget -Name 'threadId')
        $CurrentGeneration = [string](Get-JsonProperty -InputObject $CurrentState -Name 'generation')
        if ($CurrentProvider -ne 'codex' -or
            $CurrentStatus -ne 'armed' -or
            $CurrentThreadId -ne $Request.ThreadId -or
            $CurrentGeneration -ne $Checkpoint.Generation) {
            return
        }

        $Entries = @(
            foreach ($Key in $Checkpoint.Offsets.Keys) {
                [ordered]@{
                    path = [string]$Key
                    offset = [long]$Checkpoint.Offsets[$Key]
                }
            }
        )
        $Document = [ordered]@{
            schemaVersion = 1
            provider = 'codex'
            generation = $Checkpoint.Generation
            target = [ordered]@{
                threadId = $Request.ThreadId
            }
            armedAtUtc = $Checkpoint.ArmedAtUtc
            files = $Entries
        }
        Write-AtomicJsonDocument -Path $Request.CheckpointPath -Document $Document
    }
    catch {
        # A concurrent arm/claim or transient state failure is retried by the
        # next scan; stale checkpoint data is never republished.
    }
    finally {
        if ($null -ne $ThreadLockStream) {
            $ThreadLockStream.Dispose()
        }
    }
}

function Read-FirstLine {
    <#
    .SYNOPSIS
    Reads only the first UTF-8 line of a rollout file.

    .PARAMETER Path
    The rollout path.

    .OUTPUTS
    System.String. Returns the first line or null when unavailable.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Stream = $null
    $Reader = $null
    try {
        $Stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $Reader = [IO.StreamReader]::new($Stream, [Text.UTF8Encoding]::new($false, $false), $true, 4096, $true)
        return $Reader.ReadLine()
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $Reader) {
            $Reader.Dispose()
        }
        if ($null -ne $Stream) {
            $Stream.Dispose()
        }
    }
}

function Get-UserSessionId {
    <#
    .SYNOPSIS
    Validates rollout session metadata and returns its user session UUID.

    .PARAMETER Path
    The rollout file whose first record is inspected.

    .OUTPUTS
    System.String. Returns the normalized user session ID, or null when the
    rollout is a subagent/guardian, malformed, or not yet fully written.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $FirstLine = Read-FirstLine -Path $Path
    if ([string]::IsNullOrWhiteSpace($FirstLine)) {
        return $null
    }

    try {
        $Record = $FirstLine | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if ([string](Get-JsonProperty -InputObject $Record -Name 'type') -ne 'session_meta') {
        return $null
    }

    $Payload = Get-JsonProperty -InputObject $Record -Name 'payload'
    if ($null -eq $Payload) {
        return $null
    }
    $SessionId = Normalize-CodexThreadId -InputValue (Get-JsonProperty -InputObject $Payload -Name 'session_id')
    $RecordId = Normalize-CodexThreadId -InputValue (Get-JsonProperty -InputObject $Payload -Name 'id')
    if ($null -eq $SessionId -or $SessionId -ne $RecordId) {
        return $null
    }

    if ([string](Get-JsonProperty -InputObject $Payload -Name 'thread_source') -ne 'user') {
        return $null
    }

    foreach ($Property in $Payload.PSObject.Properties) {
        if ($Property.Name -match '^parent' -and -not [string]::IsNullOrWhiteSpace([string]$Property.Value)) {
            return $null
        }
    }

    return $SessionId
}

function Read-CompleteJsonLines {
    <#
    .SYNOPSIS
    Reads only newline-terminated JSONL records from a byte offset.

    .PARAMETER Path
    The rollout file to read.

    .PARAMETER StartOffset
    The byte offset immediately after the last confirmed complete line.

    .OUTPUTS
    PSCustomObject[]. Each item contains the parsed record (or null for a
    malformed complete line) and the next safe byte offset.

    .NOTES
    A partial final line is retained by leaving the checkpoint at its prior
    offset. UTF-8 decoding is strict for complete lines.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(0, [long]::MaxValue)]
        [long]$StartOffset = 0
    )

    $Stream = $null
    try {
        $Stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        if ($Stream.Length -lt $StartOffset) {
            $StartOffset = 0L
        }
        [void]$Stream.Seek($StartOffset, [IO.SeekOrigin]::Begin)

        $Buffer = [byte[]]::new(8192)
        $LineBytes = [Collections.Generic.List[byte]]::new()
        $CurrentOffset = $StartOffset
        $StrictUtf8 = [Text.UTF8Encoding]::new($false, $true)

        while (($ReadCount = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            for ($Index = 0; $Index -lt $ReadCount; $Index++) {
                $LineBytes.Add($Buffer[$Index])
                $CurrentOffset++
                if ($Buffer[$Index] -ne 0x0A) {
                    continue
                }

                $Bytes = $LineBytes.ToArray()
                if ($Bytes.Length -gt 0 -and $Bytes[-1] -eq 0x0A) {
                    $Bytes = if ($Bytes.Length -gt 1) { $Bytes[0..($Bytes.Length - 2)] } else { [byte[]]::new(0) }
                }
                if ($Bytes.Length -gt 0 -and $Bytes[-1] -eq 0x0D) {
                    $Bytes = if ($Bytes.Length -gt 1) { $Bytes[0..($Bytes.Length - 2)] } else { [byte[]]::new(0) }
                }

                $Record = $null
                try {
                    $LineText = $StrictUtf8.GetString($Bytes)
                    if (-not [string]::IsNullOrWhiteSpace($LineText)) {
                        $Record = $LineText | ConvertFrom-Json
                    }
                }
                catch {
                    $Record = $null
                }

                [pscustomobject]@{
                    Record = $Record
                    NextOffset = $CurrentOffset
                }
                $LineBytes.Clear()
            }
        }
    }
    catch {
        # A locked or disappearing rollout is retried on the next rescan.
    }
    finally {
        if ($null -ne $Stream) {
            $Stream.Dispose()
        }
    }
}

function Get-TaskCompleteEvent {
    <#
    .SYNOPSIS
    Extracts a Codex task_complete event from one parsed JSONL record.

    .PARAMETER Record
    The parsed outer rollout record.

    .OUTPUTS
    PSCustomObject. Returns event timestamp and sanitized turn ID, or null.
    #>
    param(
        [AllowNull()]
        [object]$Record
    )

    if ($null -eq $Record -or [string](Get-JsonProperty -InputObject $Record -Name 'type') -ne 'event_msg') {
        return $null
    }

    $Payload = Get-JsonProperty -InputObject $Record -Name 'payload'
    if ([string](Get-JsonProperty -InputObject $Payload -Name 'type') -ne 'task_complete') {
        return $null
    }

    $Timestamp = [string](Get-JsonProperty -InputObject $Record -Name 'timestamp')
    $ParsedTimestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Timestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ParsedTimestamp)) {
        return $null
    }

    $TurnId = Normalize-CodexThreadId -InputValue (Get-JsonProperty -InputObject $Payload -Name 'turn_id')
    if ($null -eq $TurnId) {
        $TurnId = 'unknown'
    }

    return [pscustomobject]@{
        Timestamp = $ParsedTimestamp
        TurnId = $TurnId
    }
}

function Invoke-StopHelper {
    <#
    .SYNOPSIS
    Sends one synthetic Stop envelope to the Windows helper through stdin.

    .PARAMETER ThreadId
    The normalized user session UUID.

    .PARAMETER TranscriptPath
    The validated rollout path.

    .PARAMETER TurnId
    The sanitized completion turn UUID.

    .PARAMETER Generation
    The generation observed by this watcher scan. The helper rejects the
    envelope when a newer explicit arm has replaced it.

    .OUTPUTS
    PSCustomObject. Returns `Handled` with a terminal status, or a generic
    `not_handled`/`transient_failure` classification.

    .NOTES
    The helper owns the per-thread claim and notification attempt. This process
    never places message or topic data on the command line or in output.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [Parameter(Mandatory)]
        [string]$TranscriptPath,

        [Parameter(Mandatory)]
        [string]$TurnId,

        [Parameter(Mandatory)]
        [string]$Generation
    )

    if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) {
        return [pscustomobject]@{
            Handled = $false
            Status = 'transient_failure'
        }
    }

    $PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        return [pscustomobject]@{
            Handled = $false
            Status = 'transient_failure'
        }
    }

    $Envelope = [ordered]@{
        operation = 'stop'
        hook = [ordered]@{
            hook_event_name = 'Stop'
            session_id = $ThreadId
            transcript_path = $TranscriptPath
            turn_id = $TurnId
            stop_hook_active = $false
            expected_generation = $Generation
        }
    }
    $RequestJson = $Envelope | ConvertTo-Json -Compress
    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $PowerShellExecutable
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardInput = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $StartInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $StartInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    [void]$StartInfo.ArgumentList.Add('-NoProfile')
    [void]$StartInfo.ArgumentList.Add('-NonInteractive')
    [void]$StartInfo.ArgumentList.Add('-File')
    [void]$StartInfo.ArgumentList.Add($HelperPath)

    $Process = $null
    try {
        $Process = [Diagnostics.Process]::new()
        $Process.StartInfo = $StartInfo
        if (-not $Process.Start()) {
            return [pscustomobject]@{
                Handled = $false
                Status = 'transient_failure'
            }
        }

        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.StandardInput.Write($RequestJson)
        $Process.StandardInput.Close()
        if (-not $Process.WaitForExit(60000)) {
            try {
                $Process.Kill($true)
            }
            catch {
                # The helper is already terminating; no retry is attempted.
            }
            return [pscustomobject]@{
                Handled = $false
                Status = 'transient_failure'
            }
        }

        $OutputText = $OutputTask.GetAwaiter().GetResult()
        [void]$ErrorTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($OutputText)) {
            return [pscustomobject]@{
                Handled = $false
                Status = 'transient_failure'
            }
        }

        $Result = $OutputText | ConvertFrom-Json
        if ($Result.Handled -eq $true) {
            $ResultStatus = [string](Get-JsonProperty -InputObject $Result -Name 'Status')
            if ([string]::IsNullOrWhiteSpace($ResultStatus)) {
                $ResultStatus = 'failure'
            }
            return [pscustomobject]@{
                Handled = $true
                Status = $ResultStatus
            }
        }

        if ($Result.Ok -eq $true) {
            return [pscustomobject]@{
                Handled = $false
                Status = 'not_handled'
            }
        }

        return [pscustomobject]@{
            Handled = $false
            Status = 'transient_failure'
        }
    }
    catch {
        return [pscustomobject]@{
            Handled = $false
            Status = 'transient_failure'
        }
    }
    finally {
        if ($null -ne $Process) {
            $Process.Dispose()
        }
    }
}

function Process-ActiveRequest {
    <#
    .SYNOPSIS
    Scans validated user rollouts and handles the first eligible completion.

    .PARAMETER Request
    An active request object from Get-ActiveRequests.

    .OUTPUTS
    System.Boolean. Returns true when the helper consumed the request.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Request
    )

    $Checkpoint = Read-Checkpoint -Request $Request
    $ArmedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            $Checkpoint.ArmedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$ArmedAt)) {
        $ArmedAt = [DateTimeOffset]::UtcNow
    }

    $SessionsDirectory = Get-CodexSessionsDirectory
    if ([string]::IsNullOrWhiteSpace($SessionsDirectory) -or
        -not (Test-Path -LiteralPath $SessionsDirectory -PathType Container)) {
        return $false
    }

    $RolloutFiles = @(Get-ChildItem -LiteralPath $SessionsDirectory -Recurse -File -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue)
    foreach ($RolloutFile in $RolloutFiles) {
        $SessionId = Get-UserSessionId -Path $RolloutFile.FullName
        if ($SessionId -ne $Request.ThreadId) {
            continue
        }

        $Offset = 0L
        if ($Checkpoint.Offsets.ContainsKey($RolloutFile.FullName)) {
            $Offset = [long]$Checkpoint.Offsets[$RolloutFile.FullName]
        }

        $Handled = $false
        $CurrentOffset = $Offset
        foreach ($Line in @(Read-CompleteJsonLines -Path $RolloutFile.FullName -StartOffset $Offset)) {
            $LineStartOffset = $CurrentOffset
            $NextOffset = [long]$Line.NextOffset
            if ($null -eq $Line.Record) {
                $Checkpoint.Offsets[$RolloutFile.FullName] = $NextOffset
                $CurrentOffset = $NextOffset
                continue
            }

            $CompleteEvent = Get-TaskCompleteEvent -Record $Line.Record
            if ($null -eq $CompleteEvent -or $CompleteEvent.Timestamp -lt $ArmedAt) {
                $Checkpoint.Offsets[$RolloutFile.FullName] = $NextOffset
                $CurrentOffset = $NextOffset
                continue
            }

            $HelperResult = Invoke-StopHelper `
                    -ThreadId $Request.ThreadId `
                    -TranscriptPath $RolloutFile.FullName `
                    -TurnId $CompleteEvent.TurnId `
                    -Generation $Checkpoint.Generation
            if ($null -eq $HelperResult) {
                $HelperResult = [pscustomobject]@{
                    Handled = $false
                    Status = 'transient_failure'
                }
            }

            if ($HelperResult.Handled -eq $true) {
                $Handled = $true
                break
            }

            # An eligible event is never checkpointed past unless the helper
            # reports that this generation was claimed. This preserves the
            # event for a later scan after either a transient helper failure or
            # a benign no-op result; stale generations are rejected by the
            # checkpoint revalidation and expected-generation guard.
            $Checkpoint.Offsets[$RolloutFile.FullName] = $LineStartOffset
            Save-Checkpoint -Request $Request -Checkpoint $Checkpoint
            return $false
        }

        if ($Handled) {
            return $true
        }

        Save-Checkpoint -Request $Request -Checkpoint $Checkpoint
    }

    return $false
}

function Start-RolloutWakeupWatcher {
    <#
    .SYNOPSIS
    Creates an optional FileSystemWatcher used only to wake periodic scans.

    .PARAMETER SessionsDirectory
    The Codex sessions directory to observe.

    .OUTPUTS
    PSCustomObject. Returns the watcher and event source identifiers, or null
    when the directory or watcher API is unavailable.

    .NOTES
    Detection remains driven by periodic rescan and persistent offsets; events
    are hints and are never treated as completion records.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SessionsDirectory
    )

    if ([string]::IsNullOrWhiteSpace($SessionsDirectory) -or
        -not (Test-Path -LiteralPath $SessionsDirectory -PathType Container)) {
        return $null
    }

    $Watcher = $null
    $SourceIdentifiers = @(
        "TaskCompleteNotifyChanged-$([Guid]::NewGuid().ToString('N'))"
        "TaskCompleteNotifyCreated-$([Guid]::NewGuid().ToString('N'))"
        "TaskCompleteNotifyRenamed-$([Guid]::NewGuid().ToString('N'))"
    )
    try {
        $Watcher = [IO.FileSystemWatcher]::new()
        $Watcher.Path = $SessionsDirectory
        $Watcher.Filter = 'rollout-*.jsonl'
        $Watcher.IncludeSubdirectories = $true
        $Watcher.NotifyFilter = [IO.NotifyFilters]::LastWrite -bor [IO.NotifyFilters]::FileName -bor [IO.NotifyFilters]::Size
        $Watcher.EnableRaisingEvents = $true
        Register-ObjectEvent -InputObject $Watcher -EventName Changed -SourceIdentifier $SourceIdentifiers[0] | Out-Null
        Register-ObjectEvent -InputObject $Watcher -EventName Created -SourceIdentifier $SourceIdentifiers[1] | Out-Null
        Register-ObjectEvent -InputObject $Watcher -EventName Renamed -SourceIdentifier $SourceIdentifiers[2] | Out-Null
        return [pscustomobject]@{
            Watcher = $Watcher
            SourceIdentifiers = $SourceIdentifiers
        }
    }
    catch {
        if ($null -ne $Watcher) {
            $Watcher.Dispose()
        }
        return $null
    }
}

function Stop-RolloutWakeupWatcher {
    <#
    .SYNOPSIS
    Disposes the optional FileSystemWatcher and its event subscriptions.

    .PARAMETER WatchContext
    The object returned by Start-RolloutWakeupWatcher.

    .OUTPUTS
    None. Event registrations and the watcher are released.
    #>
    param(
        [AllowNull()]
        [object]$WatchContext
    )

    if ($null -eq $WatchContext) {
        return
    }

    foreach ($SourceIdentifier in @($WatchContext.SourceIdentifiers)) {
        Unregister-Event -SourceIdentifier $SourceIdentifier -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $SourceIdentifier -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    }

    if ($null -ne $WatchContext.Watcher) {
        $WatchContext.Watcher.Dispose()
    }
}

function Wait-ForRolloutWakeup {
    <#
    .SYNOPSIS
    Waits for a watcher hint while preserving a periodic rescan cadence.

    .PARAMETER WatchContext
    The optional watcher context.

    .PARAMETER TimeoutMilliseconds
    Maximum wait before the next periodic scan.

    .OUTPUTS
    None. Pending events are discarded after waking because offsets are the
    source of truth.
    #>
    param(
        [AllowNull()]
        [object]$WatchContext,

        [ValidateRange(100, 60000)]
        [int]$TimeoutMilliseconds
    )

    if ($null -eq $WatchContext) {
        Start-Sleep -Milliseconds $TimeoutMilliseconds
        return
    }

    # Wait-Event accepts a single string source and an integer timeout. This
    # isolated process owns only the registrations below, so wait without a
    # source filter and drain each known source individually afterward.
    $WholeSeconds = [int][Math]::Floor([double]$TimeoutMilliseconds / 1000.0)
    $RemainderMilliseconds = $TimeoutMilliseconds - ($WholeSeconds * 1000)
    $Event = Wait-Event -Timeout $WholeSeconds
    if ($null -ne $Event) {
        Remove-Event -EventIdentifier $Event.EventIdentifier -ErrorAction SilentlyContinue
    }
    elseif ($RemainderMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $RemainderMilliseconds
    }

    foreach ($SourceIdentifier in @($WatchContext.SourceIdentifiers)) {
        foreach ($PendingEvent in @(Get-Event -SourceIdentifier $SourceIdentifier -ErrorAction SilentlyContinue)) {
            Remove-Event -EventIdentifier $PendingEvent.EventIdentifier -ErrorAction SilentlyContinue
        }
    }
}

function Get-ActiveRequestCount {
    <#
    .SYNOPSIS
    Returns the number of armed requests visible at a coordination point.

    .OUTPUTS
    System.Int32. Returns the current active request count.
    #>
    return @((Get-ActiveRequests)).Count
}

$WatcherStream = $null
$WatchContext = $null
Initialize-WatcherDirectories
$WatcherStream = Acquire-WatcherLock
if ($null -eq $WatcherStream) {
    exit 0
}

try {
    $InitialSessionsDirectory = Get-CodexSessionsDirectory
    $WatchContext = Start-RolloutWakeupWatcher -SessionsDirectory $InitialSessionsDirectory

    while ($true) {
        $ActiveRequests = @(Get-ActiveRequests)
        if ($ActiveRequests.Count -eq 0) {
            $CoordinationStream = Acquire-CoordinationLock
            if ($null -eq $CoordinationStream) {
                if ($Once) {
                    break
                }
                Start-Sleep -Milliseconds $PollIntervalMilliseconds
                continue
            }

            try {
                if ((Get-ActiveRequestCount) -eq 0) {
                    # Release the lifetime lock while still holding coordination.
                    # arm cannot publish a request until this stream is closed.
                    Stop-RolloutWakeupWatcher -WatchContext $WatchContext
                    $WatchContext = $null
                    $WatcherStream.Dispose()
                    $WatcherStream = $null
                    break
                }
            }
            finally {
                $CoordinationStream.Dispose()
            }
            continue
        }

        foreach ($Request in $ActiveRequests) {
            [void](Process-ActiveRequest -Request $Request)
        }

        if ($Once) {
            break
        }
        Wait-ForRolloutWakeup -WatchContext $WatchContext -TimeoutMilliseconds $PollIntervalMilliseconds
    }
}
finally {
    Stop-RolloutWakeupWatcher -WatchContext $WatchContext
    if ($null -ne $WatcherStream) {
        $WatcherStream.Dispose()
    }
}

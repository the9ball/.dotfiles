#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillDirectory = Split-Path -Parent $ScriptDirectory

function Resolve-CodexHome {
    <#
    .SYNOPSIS
    Resolves the Codex home used by this helper process.

    .OUTPUTS
    System.String. Returns an absolute Codex home path, or null when the
    configured path cannot be resolved.

    .NOTES
    The process environment is the only selector. The caller must not infer a
    different home from the target text or from another provider's settings.
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
    # Keep invalid-home failures from creating any user-visible runtime path.
    Join-Path $SkillDirectory '.task-complete-notify.invalid'
}
else {
    Join-Path $CodexHome '.task-complete-notify'
}
$RequestDirectory = Join-Path $StateDirectory 'requests'
$LockDirectory = Join-Path $StateDirectory 'locks'
$CheckpointDirectory = Join-Path $StateDirectory 'checkpoints'
$TerminalDirectory = Join-Path $StateDirectory 'terminal'
$CoordinationLockPath = Join-Path $StateDirectory 'coordination.lock'
$WatcherLockPath = Join-Path $StateDirectory 'watcher.lock'
$NotifyScriptPath = Join-Path $ScriptDirectory 'notify.ps1'
$WatcherScriptPath = Join-Path $ScriptDirectory 'codex-watcher.ps1'

function Get-ObjectPropertyValue {
    <#
    .SYNOPSIS
    Reads a property from an arbitrary JSON-derived object without strict-mode errors.

    .PARAMETER InputObject
    The object whose property should be read.

    .PARAMETER PropertyName
    The exact property name to read.

    .OUTPUTS
    System.Object. Returns the property value or null when it is absent.
    #>
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [Collections.IDictionary] -and $InputObject.Contains($PropertyName)) {
        return $InputObject[$PropertyName]
    }

    $Property = $InputObject.PSObject.Properties[$PropertyName]
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
    System.String. Returns a lowercase UUID in dashed form.

    .NOTES
    The legacy `codex://<UUID>` form and URI decorations are intentionally rejected.
    #>
    param(
        [AllowNull()]
        [string]$InputValue
    )

    if ([string]::IsNullOrWhiteSpace($InputValue)) {
        throw 'thread_invalid'
    }

    $UuidText = $null
    if ($InputValue -match '^codex://threads/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$') {
        $UuidText = $Matches[1]
    }
    elseif ($InputValue -match '^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$') {
        $UuidText = $Matches[1]
    }
    else {
        throw 'thread_invalid'
    }

    $GuidValue = [Guid]::Empty
    if (-not [Guid]::TryParse($UuidText, [ref]$GuidValue)) {
        throw 'thread_invalid'
    }

    return $GuidValue.ToString('D').ToLowerInvariant()
}

function Extract-ArmThreadId {
    <#
    .SYNOPSIS
    Extracts one explicit Codex thread UUID from an arm input string.

    .PARAMETER InputValue
    Text containing a raw UUID or a canonical Codex thread URI.

    .OUTPUTS
    System.String. Returns one lowercase UUID.

    .NOTES
    This relaxed parser is intentionally limited to the external arm boundary.
    Internal hook, metadata, and state values continue to use the strict
    normalizer. Zero candidates, multiple distinct candidates, malformed
    Codex URIs, and inputs over 4 KiB UTF-8 are rejected without echoing text.
    #>
    param(
        [AllowNull()]
        [string]$InputValue
    )

    if ([string]::IsNullOrWhiteSpace($InputValue)) {
        throw 'thread_invalid'
    }

    try {
        $Utf8Encoding = [Text.UTF8Encoding]::new($false, $true)
        if ($Utf8Encoding.GetByteCount($InputValue) -gt 4096) {
            throw 'thread_invalid'
        }
    }
    catch {
        throw 'thread_invalid'
    }

    $UuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $UuidBoundaryPattern = "(?<![0-9A-Za-z_-])($UuidPattern)(?![0-9A-Za-z_-])"
    $CodexUriMatches = [regex]::Matches($InputValue, 'codex://')
    foreach ($CodexUriMatch in $CodexUriMatches) {
        $UriSuffix = $InputValue.Substring($CodexUriMatch.Index)
        if ($UriSuffix -notmatch ("^codex://threads/" + $UuidPattern + '(?![0-9A-Za-z_/?#-])')) {
            throw 'thread_invalid'
        }
    }

    $Candidates = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($UuidMatch in [regex]::Matches($InputValue, $UuidBoundaryPattern)) {
        $GuidValue = [Guid]::Empty
        if (-not [Guid]::TryParse($UuidMatch.Groups[1].Value, [ref]$GuidValue)) {
            throw 'thread_invalid'
        }

        [void]$Candidates.Add($GuidValue.ToString('D').ToLowerInvariant())
    }

    if ($Candidates.Count -eq 0) {
        throw 'thread_invalid'
    }

    if ($Candidates.Count -gt 1) {
        throw 'thread_ambiguous'
    }

    foreach ($Candidate in $Candidates) {
        return $Candidate
    }

    throw 'thread_invalid'
}

function Assert-NotificationMessage {
    <#
    .SYNOPSIS
    Validates an explicit or default notification message.

    .PARAMETER Message
    The literal message to validate.

    .OUTPUTS
    System.String. Returns the unchanged message after validation.

    .NOTES
    The validation rejects line breaks, controls, invalid Unicode, edge
    whitespace, and messages over 256 UTF-8 bytes without echoing the value.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrEmpty($Message) -or [string]::IsNullOrWhiteSpace($Message)) {
        throw 'message_invalid'
    }

    if ([char]::IsWhiteSpace($Message[0]) -or [char]::IsWhiteSpace($Message[$Message.Length - 1])) {
        throw 'message_invalid'
    }

    for ($CharacterIndex = 0; $CharacterIndex -lt $Message.Length; $CharacterIndex++) {
        $Character = $Message[$CharacterIndex]
        $CodePoint = [int][char]$Character

        if ($CodePoint -eq 0x2028 -or $CodePoint -eq 0x2029) {
            throw 'message_invalid'
        }

        if ([char]::IsHighSurrogate($Character)) {
            if ($CharacterIndex + 1 -ge $Message.Length -or -not [char]::IsLowSurrogate($Message[$CharacterIndex + 1])) {
                throw 'message_invalid'
            }

            $CharacterIndex++
            continue
        }

        if ([char]::IsLowSurrogate($Character) -or [char]::IsControl($Character)) {
            throw 'message_invalid'
        }
    }

    try {
        $Utf8Encoding = [Text.UTF8Encoding]::new($false, $true)
        $Utf8Bytes = $Utf8Encoding.GetBytes($Message)
    }
    catch {
        throw 'message_invalid'
    }

    if ($Utf8Bytes.Length -gt 256) {
        throw 'message_invalid'
    }

    return $Message
}

function Initialize-StateDirectories {
    <#
    .SYNOPSIS
    Creates the runtime directories under the resolved Codex home.

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

function Get-RequestPath {
    <#
    .SYNOPSIS
    Builds the active request path for a normalized thread UUID.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .OUTPUTS
    System.String. Returns the request JSON path.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    return (Join-Path $RequestDirectory "$ThreadId.json")
}

function Get-TerminalPath {
    <#
    .SYNOPSIS
    Builds the latest terminal-result path for a normalized thread UUID.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .OUTPUTS
    System.String. Returns the terminal result JSON path.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    return (Join-Path $TerminalDirectory "$ThreadId.json")
}

function Get-LockPath {
    <#
    .SYNOPSIS
    Builds the per-thread lock path.

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

function Get-CheckpointPath {
    <#
    .SYNOPSIS
    Builds the fallback-watcher checkpoint path for a normalized thread UUID.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .OUTPUTS
    System.String. Returns the checkpoint JSON path.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    return (Join-Path $CheckpointDirectory "$ThreadId.json")
}

function Enter-CoordinationLock {
    <#
    .SYNOPSIS
    Acquires the short-lived lock shared by arm and watcher shutdown checks.

    .PARAMETER TimeoutMilliseconds
    Maximum time to wait for the coordination lock.

    .OUTPUTS
    System.IO.FileStream. Returns an exclusive stream, or null on timeout.

    .NOTES
    The caller must dispose the stream. The watcher closes its lifetime lock
    while holding this lock before exiting, so arm cannot lose a wake-up.
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

function Enter-ThreadLock {
    <#
    .SYNOPSIS
    Acquires a Windows OS-lifetime exclusive lock for one thread.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .PARAMETER TimeoutMilliseconds
    Maximum time to wait for another helper to release the lock.

    .OUTPUTS
    System.IO.FileStream. Returns an exclusive stream, or null on timeout.

    .NOTES
    The caller must dispose the returned stream. The open handle, not the
    marker file's existence, is the ownership proof.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [ValidateRange(0, 120000)]
        [int]$TimeoutMilliseconds = 10000
    )

    $LockPath = Get-LockPath -ThreadId $ThreadId
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
    Reads one local JSON document without exposing its contents.

    .PARAMETER Path
    The local JSON path to read.

    .OUTPUTS
    System.Object. Returns the parsed document, or null if the file is absent.

    .NOTES
    Parse failures are reported as a generic state error without the path.
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
        throw 'state_invalid'
    }
}

function Write-AtomicJsonDocument {
    <#
    .SYNOPSIS
    Publishes a JSON document atomically within its destination directory.

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
        $Utf8Encoding = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($TemporaryPath, "$JsonText`n", $Utf8Encoding)

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($TemporaryPath, $Path, $BackupPath, $true)
            Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
        else {
            [IO.File]::Move($TemporaryPath, $Path)
        }
    }
    catch {
        throw 'state_write_failed'
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

function Remove-ActiveRequest {
    <#
    .SYNOPSIS
    Removes an active request after its terminal result is recorded.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .OUTPUTS
    System.Boolean. Returns true when the request is absent after the call.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    $RequestPath = Get-RequestPath -ThreadId $ThreadId
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        return $true
    }

    try {
        Remove-Item -LiteralPath $RequestPath -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-CodexSessionsDirectory {
    <#
    .SYNOPSIS
    Resolves the local Codex sessions directory for the fallback watcher.

    .OUTPUTS
    System.String. Returns the sessions path without exposing it in diagnostics.

    .NOTES
    The path is derived from the process-lifetime home resolution used by all
    state operations, so state and transcript detection cannot diverge.
    #>
    if ([string]::IsNullOrWhiteSpace($CodexHome)) {
        return $null
    }

    return (Join-Path $CodexHome 'sessions')
}

function Test-PathWithinDirectory {
    <#
    .SYNOPSIS
    Confirms that a path resolves beneath a specified directory.

    .PARAMETER Path
    The candidate path to validate.

    .PARAMETER Directory
    The directory that must contain the candidate path.

    .OUTPUTS
    System.Boolean. Returns true only for a descendant path under the
    specified directory.

    .NOTES
    The comparison is lexical and case-insensitive for Windows paths. The
    caller must still require the expected file type before reading the path.
    #>
    param(
        [AllowNull()]
        [string]$Path,

        [AllowNull()]
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Directory)) {
        return $false
    }

    try {
        $ResolvedPath = [IO.Path]::GetFullPath($Path)
        $ResolvedDirectory = [IO.Path]::GetFullPath($Directory)
        $RelativePath = [IO.Path]::GetRelativePath($ResolvedDirectory, $ResolvedPath)
    }
    catch {
        return $false
    }

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -eq '.') {
        return $false
    }

    return ($RelativePath -notmatch '^\.\.(?:[\\/]|$)')
}

function Get-LastCompleteLineOffset {
    <#
    .SYNOPSIS
    Finds the byte offset immediately after the last complete JSONL line.

    .PARAMETER Path
    The rollout file to inspect.

    .OUTPUTS
    System.Int64. Returns zero for an absent or line-less file.

    .NOTES
    The fallback watcher never begins in the middle of a partial UTF-8 line.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Stream = $null
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return 0L
        }

        $Stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        $Position = $Stream.Length
        $Buffer = [byte[]]::new(4096)
        while ($Position -gt 0) {
            $ReadStart = [Math]::Max(0L, $Position - $Buffer.Length)
            [void]$Stream.Seek($ReadStart, [IO.SeekOrigin]::Begin)
            $ReadLength = [int]($Position - $ReadStart)
            $ReadCount = $Stream.Read($Buffer, 0, $ReadLength)
            for ($Index = $ReadCount - 1; $Index -ge 0; $Index--) {
                if ($Buffer[$Index] -eq 0x0A) {
                    return ($ReadStart + $Index + 1)
                }
            }
            $Position = $ReadStart
        }

        return 0L
    }
    catch {
        return 0L
    }
    finally {
        if ($null -ne $Stream) {
            $Stream.Dispose()
        }
    }
}

function New-ArmCheckpoint {
    <#
    .SYNOPSIS
    Captures append offsets for rollout files that exist when a request is armed.

    .PARAMETER ThreadId
    The normalized target UUID.

    .PARAMETER ArmedAtUtc
    The UTC timestamp assigned to the new active request.

    .PARAMETER Generation
    The generation identifier assigned to the new active request.

    .OUTPUTS
    PSCustomObject. Returns a checkpoint document for the JSONL fallback.

    .NOTES
    Existing files start immediately after their last complete newline; newly
    created files start at zero. The watcher still verifies session metadata and
    event timestamps.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [Parameter(Mandatory)]
        [string]$ArmedAtUtc,

        [Parameter(Mandatory)]
        [string]$Generation
    )

    $FileEntries = @(
        try {
            $SessionsDirectory = Get-CodexSessionsDirectory
            if (Test-Path -LiteralPath $SessionsDirectory -PathType Container) {
                Get-ChildItem -LiteralPath $SessionsDirectory -Recurse -File -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        [ordered]@{
                            path = $_.FullName
                            offset = Get-LastCompleteLineOffset -Path $_.FullName
                        }
                    }
            }
        }
        catch {
            # An unavailable sessions directory is represented by an empty baseline.
        }
    )

    return [ordered]@{
        schemaVersion = 1
        provider = 'codex'
        generation = $Generation
        target = [ordered]@{
            threadId = $ThreadId
        }
        armedAtUtc = $ArmedAtUtc
        files = $FileEntries
    }
}

function Remove-Checkpoint {
    <#
    .SYNOPSIS
    Removes a consumed fallback-watcher checkpoint.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .OUTPUTS
    System.Boolean. Returns true when the checkpoint is absent after the call.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    $CheckpointPath = Get-CheckpointPath -ThreadId $ThreadId
    if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) {
        return $true
    }

    try {
        Remove-Item -LiteralPath $CheckpointPath -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-WatcherRunning {
    <#
    .SYNOPSIS
    Probes whether another fallback watcher owns the lifetime lock.

    .OUTPUTS
    System.Boolean. Returns true when the lock is currently held by another
    process.
    #>
    $ProbeStream = $null
    try {
        $ProbeStream = [IO.File]::Open(
            $WatcherLockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
        return $false
    }
    catch [IO.IOException] {
        return $true
    }
    catch {
        return $true
    }
    finally {
        if ($null -ne $ProbeStream) {
            $ProbeStream.Dispose()
        }
    }
}

function Start-FallbackWatcher {
    <#
    .SYNOPSIS
    Starts the JSONL fallback watcher when fallback mode is explicitly enabled.

    .OUTPUTS
    None. The detached detector inherits the environment but receives no
    notification content in its command line.

    .NOTES
    Set `TASK_COMPLETE_NOTIFY_WATCHER=1` only after the Stop-hook canary fails.
    The watcher itself owns an OS-lifetime lock and exits when no requests remain.
    #>
    $FallbackEnabled = [Environment]::GetEnvironmentVariable('TASK_COMPLETE_NOTIFY_WATCHER', 'Process')
    if ($FallbackEnabled -ne '1') {
        return
    }

    if (-not (Test-Path -LiteralPath $WatcherScriptPath -PathType Leaf)) {
        return
    }

    if (Test-WatcherRunning) {
        return
    }

    $PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        return
    }

    $PreviousConfiguredCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    try {
        # Normalize the child environment so a relative CODEX_HOME resolves to
        # the same home even though the detached watcher changes its cwd.
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $CodexHome, 'Process')
        Start-Process -FilePath $PowerShellExecutable `
            -WindowStyle Hidden `
            -WorkingDirectory $ScriptDirectory `
            -ArgumentList @(
                '-NoProfile',
                '-NonInteractive',
                '-File',
                $WatcherScriptPath
            ) | Out-Null
    }
    catch {
        # Detector startup is best effort; arm remains a valid state operation.
    }
    finally {
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $PreviousConfiguredCodexHome, 'Process')
    }
}

function Get-SafeTurnId {
    <#
    .SYNOPSIS
    Normalizes a hook turn identifier for a terminal record.

    .PARAMETER InputValue
    An optional turn identifier from hook input.

    .OUTPUTS
    System.String. Returns a lowercase UUID or the fixed value `unknown`.
    #>
    param(
        [AllowNull()]
        [object]$InputValue
    )

    $TextValue = if ($null -eq $InputValue) { '' } else { [string]$InputValue }
    if ($TextValue -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return $TextValue.ToLowerInvariant()
    }

    return 'unknown'
}

function Write-TerminalResult {
    <#
    .SYNOPSIS
    Writes a minimal terminal result that contains no message or topic.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .PARAMETER State
    The active or attempting state whose identity is being finalized.

    .PARAMETER Status
    One of `success`, `failure`, or `abandoned`.

    .PARAMETER TurnId
    The sanitized turn UUID or `unknown`.

    .OUTPUTS
    None. The latest terminal result is atomically published.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [ValidateSet('success', 'failure', 'abandoned')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$TurnId
    )

    $Generation = [string](Get-ObjectPropertyValue -InputObject $State -PropertyName 'generation')
    $TerminalDocument = [ordered]@{
        schemaVersion = 1
        provider = 'codex'
        generation = $Generation
        target = [ordered]@{
            threadId = $ThreadId
        }
        event = [ordered]@{
            turnId = $TurnId
        }
        status = $Status
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }

    Write-AtomicJsonDocument -Path (Get-TerminalPath -ThreadId $ThreadId) -Document $TerminalDocument
}

function Invoke-NotificationScript {
    <#
    .SYNOPSIS
    Performs exactly one message-body notification attempt via notify.ps1.

    .PARAMETER Message
    The already validated message body.

    .OUTPUTS
    PSCustomObject. Returns only `Ok` and a generic `Reason`.

    .NOTES
    The message is sent through child-process stdin, never through arguments.
    This function performs no retry and never returns topic or response data.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    try {
        $PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
            return [pscustomobject]@{
                Ok = $false
                Reason = 'transport_failure'
            }
        }

        $RequestJson = [ordered]@{
            message = $Message
        } | ConvertTo-Json -Compress

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
        [void]$StartInfo.ArgumentList.Add($NotifyScriptPath)

        $NotifierProcess = [Diagnostics.Process]::new()
        try {
            $NotifierProcess.StartInfo = $StartInfo
            if (-not $NotifierProcess.Start()) {
                return [pscustomobject]@{
                    Ok = $false
                    Reason = 'transport_failure'
                }
            }

            $OutputTask = $NotifierProcess.StandardOutput.ReadToEndAsync()
            $ErrorTask = $NotifierProcess.StandardError.ReadToEndAsync()
            $NotifierProcess.StandardInput.Write($RequestJson)
            $NotifierProcess.StandardInput.Close()
            if (-not $NotifierProcess.WaitForExit(30000)) {
                try {
                    $NotifierProcess.Kill($true)
                }
                catch {
                    # The notifier is already terminating; the attempt is terminal.
                }
                return [pscustomobject]@{
                    Ok = $false
                    Reason = 'transport_failure'
                }
            }

            $NotifierOutput = $OutputTask.GetAwaiter().GetResult()
            [void]$ErrorTask.GetAwaiter().GetResult()
            if ($NotifierProcess.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($NotifierOutput)) {
                return [pscustomobject]@{
                    Ok = $false
                    Reason = 'transport_failure'
                }
            }

            $NotifierResult = $NotifierOutput | ConvertFrom-Json
        }
        finally {
            $NotifierProcess.Dispose()
        }

        if ($NotifierResult.ok -eq $true) {
            return [pscustomobject]@{
                Ok = $true
                Reason = 'success'
            }
        }

        return [pscustomobject]@{
            Ok = $false
            Reason = 'delivery_failure'
        }
    }
    catch {
        return [pscustomobject]@{
            Ok = $false
            Reason = 'transport_failure'
        }
    }
}

function Read-TranscriptFirstLine {
    <#
    .SYNOPSIS
    Reads only the first line of a Codex transcript for metadata validation.

    .PARAMETER TranscriptPath
    The transcript path supplied by the Stop hook.

    .OUTPUTS
    System.String. Returns the first line, or null when it cannot be read.

    .NOTES
    The line is parsed in memory and never emitted to output or state.
    #>
    param(
        [AllowNull()]
        [string]$TranscriptPath
    )

    if ([string]::IsNullOrWhiteSpace($TranscriptPath) -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) {
        return $null
    }

    $TranscriptStream = $null
    $TranscriptReader = $null
    try {
        $TranscriptStream = [IO.File]::Open(
            $TranscriptPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite
        )
        $TranscriptReader = [IO.StreamReader]::new(
            $TranscriptStream,
            [Text.UTF8Encoding]::new($false, $false),
            $true,
            4096,
            $true
        )
        $FirstLine = $TranscriptReader.ReadLine()
        if ($null -ne $FirstLine -and $FirstLine.Length -gt 1048576) {
            return $null
        }

        return $FirstLine
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $TranscriptReader) {
            $TranscriptReader.Dispose()
        }
        if ($null -ne $TranscriptStream) {
            $TranscriptStream.Dispose()
        }
    }
}

function Test-CodexTranscriptMetadata {
    <#
    .SYNOPSIS
    Validates the first metadata record for one local Codex rollout.

    .PARAMETER TranscriptPath
    The rollout path to inspect.

    .PARAMETER SessionId
    The normalized UUID that must identify the session.

    .OUTPUTS
    System.Boolean. Returns true only for a user-created root session whose
    metadata identifiers match the requested UUID.

    .NOTES
    Only the first line is read. Parent fields, malformed IDs, and non-user
    sources fail closed; transcript content is never emitted or persisted.
    #>
    param(
        [AllowNull()]
        [string]$TranscriptPath,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    $FirstLine = Read-TranscriptFirstLine -TranscriptPath $TranscriptPath
    if ([string]::IsNullOrWhiteSpace($FirstLine)) {
        return $false
    }

    try {
        $MetadataRecord = $FirstLine | ConvertFrom-Json
    }
    catch {
        return $false
    }

    if ([string](Get-ObjectPropertyValue -InputObject $MetadataRecord -PropertyName 'type') -ne 'session_meta') {
        return $false
    }

    $MetadataPayload = Get-ObjectPropertyValue -InputObject $MetadataRecord -PropertyName 'payload'
    if ($null -eq $MetadataPayload) {
        return $false
    }

    $MetadataSessionId = $null
    try {
        $MetadataSessionId = Normalize-CodexThreadId -InputValue ([string](Get-ObjectPropertyValue -InputObject $MetadataPayload -PropertyName 'session_id'))
    }
    catch {
        return $false
    }

    $MetadataId = $null
    try {
        $MetadataId = Normalize-CodexThreadId -InputValue ([string](Get-ObjectPropertyValue -InputObject $MetadataPayload -PropertyName 'id'))
    }
    catch {
        return $false
    }

    if ($MetadataSessionId -ne $SessionId -or $MetadataId -ne $SessionId) {
        return $false
    }

    if ([string](Get-ObjectPropertyValue -InputObject $MetadataPayload -PropertyName 'thread_source') -ne 'user') {
        return $false
    }

    foreach ($Property in $MetadataPayload.PSObject.Properties) {
        if ($Property.Name -match '^parent' -and -not [string]::IsNullOrWhiteSpace([string]$Property.Value)) {
            return $false
        }
    }

    return $true
}

function Test-CodexSessionMetadata {
    <#
    .SYNOPSIS
    Confirms that Stop input belongs to a user-created Codex session.

    .PARAMETER HookInput
    The parsed Stop-hook input object.

    .PARAMETER SessionId
    The normalized session UUID from hook input.

    .OUTPUTS
    System.Boolean. Returns true only when the first session_meta record matches.

    .NOTES
    Unknown, missing, or malformed metadata fails closed to prevent source
    confusion with subagents, resumes, or guardian sessions.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$HookInput,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    $TranscriptPath = [string](Get-ObjectPropertyValue -InputObject $HookInput -PropertyName 'transcript_path')
    $SessionsDirectory = Get-CodexSessionsDirectory
    if (-not (Test-PathWithinDirectory -Path $TranscriptPath -Directory $SessionsDirectory)) {
        return $false
    }

    return (Test-CodexTranscriptMetadata -TranscriptPath $TranscriptPath -SessionId $SessionId)
}

function Test-CodexSessionIndexContains {
    <#
    .SYNOPSIS
    Checks whether the resolved Codex home indexes one target session.

    .PARAMETER ThreadId
    The normalized target UUID.

    .OUTPUTS
    System.Boolean. Returns true only for an exact `id` field match in the
    local `session_index.jsonl` file.

    .NOTES
    Index records are a fast same-home candidate check; their names and values
    are never logged. Transcript metadata remains the authoritative gate.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    if ([string]::IsNullOrWhiteSpace($CodexHome) -or
        -not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
        return $false
    }

    $IndexPath = Join-Path $CodexHome 'session_index.jsonl'
    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return $false
    }

    try {
        foreach ($Line in Get-Content -LiteralPath $IndexPath) {
            if ([string]::IsNullOrWhiteSpace($Line)) {
                continue
            }

            try {
                $IndexRecord = $Line | ConvertFrom-Json
                $IndexedId = Normalize-CodexThreadId -InputValue ([string](Get-ObjectPropertyValue -InputObject $IndexRecord -PropertyName 'id'))
                if ($IndexedId -eq $ThreadId) {
                    return $true
                }
            }
            catch {
                # Ignore malformed or unrelated index lines and keep scanning.
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function Test-CodexThreadOwnership {
    <#
    .SYNOPSIS
    Confirms that a target belongs to the current local Codex home.

    .PARAMETER ThreadId
    The normalized target UUID.

    .OUTPUTS
    System.Boolean. Returns true only when the local index and a matching
    active rollout's root-session metadata both validate the target.

    .NOTES
    The check is performed before state directories are initialized. Archived
    rollouts are not accepted because this notification targets a next active
    completion. A filename match alone is never sufficient.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId
    )

    if (-not (Test-CodexSessionIndexContains -ThreadId $ThreadId)) {
        return $false
    }

    $SessionsDirectory = Get-CodexSessionsDirectory
    if ([string]::IsNullOrWhiteSpace($SessionsDirectory) -or
        -not (Test-Path -LiteralPath $SessionsDirectory -PathType Container)) {
        return $false
    }

    try {
        $RolloutFiles = @(Get-ChildItem -LiteralPath $SessionsDirectory -Recurse -File -Filter "*-$ThreadId.jsonl" -ErrorAction SilentlyContinue)
        foreach ($RolloutFile in $RolloutFiles) {
            if (Test-CodexTranscriptMetadata -TranscriptPath $RolloutFile.FullName -SessionId $ThreadId) {
                return $true
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function New-ArmedState {
    <#
    .SYNOPSIS
    Creates a versioned active request document for one generation.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .PARAMETER Message
    The validated literal notification message.

    .PARAMETER ArmedAtUtc
    Optional timestamp used as the fallback-watcher baseline. When omitted,
    the current UTC time is used.

    .OUTPUTS
    PSCustomObject. Returns the state document to publish atomically.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [Parameter(Mandatory)]
        [string]$Message,

        [AllowNull()]
        [string]$ArmedAtUtc
    )

    $EffectiveArmedAtUtc = if ([string]::IsNullOrWhiteSpace($ArmedAtUtc)) {
        [DateTimeOffset]::UtcNow.ToString('o')
    }
    else {
        $ArmedAtUtc
    }

    return [ordered]@{
        schemaVersion = 1
        provider = 'codex'
        generation = ([Guid]::NewGuid().ToString('D').ToLowerInvariant())
        status = 'armed'
        target = [ordered]@{
            threadId = $ThreadId
        }
        notification = [ordered]@{
            message = $Message
        }
        armedAtUtc = $EffectiveArmedAtUtc
    }
}

function New-AttemptingState {
    <#
    .SYNOPSIS
    Creates the pre-send claim document without message content.

    .PARAMETER ThreadId
    A normalized lowercase UUID.

    .PARAMETER State
    The armed state being claimed.

    .PARAMETER TurnId
    The sanitized completion turn UUID.

    .OUTPUTS
    PSCustomObject. Returns the attempting state document.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [string]$TurnId
    )

    return [ordered]@{
        schemaVersion = 1
        provider = 'codex'
        generation = [string](Get-ObjectPropertyValue -InputObject $State -PropertyName 'generation')
        status = 'attempting'
        target = [ordered]@{
            threadId = $ThreadId
        }
        event = [ordered]@{
            turnId = $TurnId
        }
        claimedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Invoke-ArmOperation {
    <#
    .SYNOPSIS
    Registers one idempotent notification request under the thread lock.

    .PARAMETER Request
    The parsed arm envelope containing `thread` and optional `message`.

    .OUTPUTS
    PSCustomObject. Returns a sanitized operation result.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Request
    )

    $CoordinationStream = $null
    $LockStream = $null
    try {
        $ThreadId = Extract-ArmThreadId -InputValue ([string](Get-ObjectPropertyValue -InputObject $Request -PropertyName 'thread'))
        $MessageProperty = Get-ObjectPropertyValue -InputObject $Request -PropertyName 'message'
        $Message = if ($null -eq $MessageProperty) { 'Task completed' } else { [string]$MessageProperty }
        [void](Assert-NotificationMessage -Message $Message)

        # Refuse unknown or foreign-home IDs before creating any notification
        # state. The resolved home is selected only from this process's env.
        if (-not (Test-CodexThreadOwnership -ThreadId $ThreadId)) {
            return [pscustomobject]@{
                Ok = $false
                Status = 'thread_not_managed'
            }
        }

        Initialize-StateDirectories

        $CoordinationStream = Enter-CoordinationLock
        if ($null -eq $CoordinationStream) {
            return [pscustomobject]@{
                Ok = $false
                Status = 'busy'
            }
        }

        $LockStream = Enter-ThreadLock -ThreadId $ThreadId
        if ($null -eq $LockStream) {
            return [pscustomobject]@{
                Ok = $false
                Status = 'busy'
            }
        }

        try {
            $RequestPath = Get-RequestPath -ThreadId $ThreadId
            $ExistingState = Read-JsonDocument -Path $RequestPath
            if ($null -ne $ExistingState) {
                $ExistingStatus = [string](Get-ObjectPropertyValue -InputObject $ExistingState -PropertyName 'status')
                if ($ExistingStatus -eq 'armed') {
                    Start-FallbackWatcher
                    return [pscustomobject]@{
                        Ok = $true
                        Status = 'already_armed'
                    }
                }

                if ($ExistingStatus -eq 'attempting') {
                    $ExistingTurnId = Get-SafeTurnId -InputValue (Get-ObjectPropertyValue -InputObject (Get-ObjectPropertyValue -InputObject $ExistingState -PropertyName 'event') -PropertyName 'turnId')
                    Write-TerminalResult -ThreadId $ThreadId -State $ExistingState -Status 'abandoned' -TurnId $ExistingTurnId
                    if (-not (Remove-ActiveRequest -ThreadId $ThreadId)) {
                        return [pscustomobject]@{
                            Ok = $false
                            Status = 'state_error'
                        }
                    }
                    [void](Remove-Checkpoint -ThreadId $ThreadId)
                }
                else {
                    return [pscustomobject]@{
                        Ok = $false
                        Status = 'state_invalid'
                    }
                }
            }

            $InitialArmedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            $NewState = New-ArmedState `
                -ThreadId $ThreadId `
                -Message $Message `
                -ArmedAtUtc $InitialArmedAtUtc
            $Generation = [string](Get-ObjectPropertyValue -InputObject $NewState -PropertyName 'generation')
            $Checkpoint = New-ArmCheckpoint `
                -ThreadId $ThreadId `
                -Generation $Generation `
                -ArmedAtUtc $InitialArmedAtUtc
            # Publish time is after the baseline scan; events observed before it
            # are intentionally outside this generation's completion window.
            $ArmedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            $NewState['armedAtUtc'] = $ArmedAtUtc
            $Checkpoint['armedAtUtc'] = $ArmedAtUtc
            $Checkpoint['generation'] = $Generation
            Write-AtomicJsonDocument -Path (Get-CheckpointPath -ThreadId $ThreadId) -Document $Checkpoint
            Write-AtomicJsonDocument -Path $RequestPath -Document $NewState
            Start-FallbackWatcher
            return [pscustomobject]@{
                Ok = $true
                Status = 'armed'
            }
        }
        finally {
            $LockStream.Dispose()
        }
    }
    catch {
        $FailureStatus = [string]$_.Exception.Message
        if ($FailureStatus -in @('thread_invalid', 'thread_ambiguous', 'message_invalid', 'codex_home_invalid')) {
            return [pscustomobject]@{
                Ok = $false
                Status = $FailureStatus
            }
        }

        return [pscustomobject]@{
            Ok = $false
            Status = 'error'
        }
    }
    finally {
        if ($null -ne $CoordinationStream) {
            $CoordinationStream.Dispose()
        }
    }
}

function Invoke-StopOperation {
    <#
    .SYNOPSIS
    Claims and consumes one matching Codex Stop event.

    .PARAMETER HookInput
    The parsed Codex Stop-hook input object.

    .OUTPUTS
    PSCustomObject. Returns a sanitized result; the caller may discard it.

    .NOTES
    The operation never retries. Once `attempting` is atomically published,
    every send outcome is terminal and later Stop events cannot resend it.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$HookInput
    )

    $Claimed = $false
    $ClaimedState = $null
    $ThreadId = $null
    $TurnId = 'unknown'
    $LockStream = $null

    try {
        if ([string](Get-ObjectPropertyValue -InputObject $HookInput -PropertyName 'hook_event_name') -ne 'Stop') {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $StopHookActive = Get-ObjectPropertyValue -InputObject $HookInput -PropertyName 'stop_hook_active'
        if ($StopHookActive -isnot [bool]) {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        if ($StopHookActive) {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $ThreadId = Normalize-CodexThreadId -InputValue ([string](Get-ObjectPropertyValue -InputObject $HookInput -PropertyName 'session_id'))
        if (-not (Test-CodexSessionMetadata -HookInput $HookInput -SessionId $ThreadId)) {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $TurnId = Get-SafeTurnId -InputValue (Get-ObjectPropertyValue -InputObject $HookInput -PropertyName 'turn_id')
        $RequestPath = Get-RequestPath -ThreadId $ThreadId
        if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
            # A normal unarmed Stop must not create a runtime directory. An
            # arm racing immediately after this check will be observed by a
            # later Stop event or by the fallback watcher.
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        Initialize-StateDirectories
        $LockStream = Enter-ThreadLock -ThreadId $ThreadId
        if ($null -eq $LockStream) {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $ArmedState = Read-JsonDocument -Path $RequestPath
        if ($null -eq $ArmedState -or [string](Get-ObjectPropertyValue -InputObject $ArmedState -PropertyName 'status') -ne 'armed') {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $TargetObject = Get-ObjectPropertyValue -InputObject $ArmedState -PropertyName 'target'
        if ([string](Get-ObjectPropertyValue -InputObject $TargetObject -PropertyName 'threadId') -ne $ThreadId) {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $ExpectedGeneration = [string](Get-ObjectPropertyValue -InputObject $HookInput -PropertyName 'expected_generation')
        $ActualGeneration = [string](Get-ObjectPropertyValue -InputObject $ArmedState -PropertyName 'generation')
        if (-not [string]::IsNullOrWhiteSpace($ExpectedGeneration) -and
            $ExpectedGeneration -ne $ActualGeneration) {
            return [pscustomobject]@{
                Ok = $true
                Handled = $false
            }
        }

        $ClaimedState = New-AttemptingState -ThreadId $ThreadId -State $ArmedState -TurnId $TurnId
        Write-AtomicJsonDocument -Path $RequestPath -Document $ClaimedState
        $Claimed = $true

        $NotificationObject = Get-ObjectPropertyValue -InputObject $ArmedState -PropertyName 'notification'
        $Message = [string](Get-ObjectPropertyValue -InputObject $NotificationObject -PropertyName 'message')
        $MessageIsValid = $true
        try {
            [void](Assert-NotificationMessage -Message $Message)
        }
        catch {
            $MessageIsValid = $false
        }

        if ($MessageIsValid) {
            $NotificationResult = Invoke-NotificationScript -Message $Message
            $TerminalStatus = if ($NotificationResult.Ok -eq $true) { 'success' } else { 'failure' }
        }
        else {
            $TerminalStatus = 'failure'
        }

        Write-TerminalResult -ThreadId $ThreadId -State $ClaimedState -Status $TerminalStatus -TurnId $TurnId
        [void](Remove-ActiveRequest -ThreadId $ThreadId)
        [void](Remove-Checkpoint -ThreadId $ThreadId)
        return [pscustomobject]@{
            Ok = $true
            Handled = $true
            Status = $TerminalStatus
        }
    }
    catch {
        if ($Claimed -and $null -ne $ClaimedState -and $null -ne $ThreadId) {
            try {
                Write-TerminalResult -ThreadId $ThreadId -State $ClaimedState -Status 'failure' -TurnId $TurnId
                [void](Remove-ActiveRequest -ThreadId $ThreadId)
                [void](Remove-Checkpoint -ThreadId $ThreadId)
            }
            catch {
                # Keep the attempting claim if terminal publication itself fails.
            }
        }

        return [pscustomobject]@{
            Ok = $false
            Handled = $Claimed
        }
    }
    finally {
        if ($null -ne $LockStream) {
            $LockStream.Dispose()
        }
    }
}

function Invoke-HelperRequest {
    <#
    .SYNOPSIS
    Dispatches one stdin JSON operation to the arm or Stop handler.

    .PARAMETER Request
    The parsed helper request envelope.

    .OUTPUTS
    PSCustomObject. Returns a sanitized result suitable for JSON output.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Request
    )

    $Operation = [string](Get-ObjectPropertyValue -InputObject $Request -PropertyName 'operation')
    switch ($Operation) {
        'arm' {
            return (Invoke-ArmOperation -Request $Request)
        }
        'stop' {
            $HookInput = Get-ObjectPropertyValue -InputObject $Request -PropertyName 'hook'
            if ($null -eq $HookInput) {
                return [pscustomobject]@{
                    Ok = $false
                    Status = 'request_invalid'
                }
            }

            return (Invoke-StopOperation -HookInput $HookInput)
        }
        default {
            return [pscustomobject]@{
                Ok = $false
                Status = 'request_invalid'
            }
        }
    }
}

$HelperResult = $null
try {
    $RequestText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($RequestText)) {
        throw 'request_invalid'
    }

    $RequestObject = $RequestText | ConvertFrom-Json
    $HelperResult = Invoke-HelperRequest -Request $RequestObject
}
catch {
    $HelperResult = [pscustomobject]@{
        Ok = $false
        Status = 'request_invalid'
    }
}

[Console]::Out.WriteLine(($HelperResult | ConvertTo-Json -Compress))

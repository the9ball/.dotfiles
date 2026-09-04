<#
.SYNOPSIS
Extracts the latest completed Unity Player Build or Script Compilation block.

.DESCRIPTION
Reads an Editor.log snapshot with shared read access, detects typed Player Build
and Script Compilation start/end events in one deterministic pass, and emits the
latest completed block with sensitive values redacted. The input file is bounded
by MaximumInputBytes and read line by line so a growing Unity log cannot cause an
unbounded allocation. Output line and character limits retain both ends of the
block when truncation is required.

.PARAMETER LogFilePath
Path to the Unity Editor.log file. The default is Unity's standard Windows path.

.PARAMETER MaximumOutputLines
Maximum number of log lines emitted for the selected block, including a compact
omission marker when there is room for one.

.PARAMETER MaximumOutputCharacters
Maximum number of characters emitted for the selected block. Both the beginning
and end are retained when the limit is large enough for the omission marker.

.PARAMETER MaximumInputBytes
Maximum file size accepted for one snapshot. This protects memory use while the
file is read line by line.

.EXAMPLE
& .\extract-unity-build-log.ps1

.EXAMPLE
& .\extract-unity-build-log.ps1 -LogFilePath .\Editor.log -MaximumOutputLines 2000 -MaximumOutputCharacters 200000

.OUTPUTS
System.String

.NOTES
Exit Codes:
0 - A completed Player Build or Script Compilation block was emitted.
1 - The file was missing, empty, unreadable, over the input limit, changed while
    being read, had no usable boundaries, or its latest start was incomplete.
#>
[CmdletBinding()]
param(
    [string] $LogFilePath = 'C:\Users\syasui\AppData\Local\Unity\Editor\Editor.log',
    [ValidateRange(1, 1000000)] [int] $MaximumOutputLines = 10000,
    [ValidateRange(1, 100000000)] [int] $MaximumOutputCharacters = 500000,
    [ValidateRange(1, 1073741824)] [long] $MaximumInputBytes = 100000000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RedactedLogLine {
    <#
    .SYNOPSIS
    Masks credential-like values in one Editor.log line.
    .DESCRIPTION
    Replaces the value portion of sensitive key-value pairs through the end of
    the line. Bearer tokens are masked in quoted and unquoted forms. If a key
    has no value on this line, the next physical line is masked conservatively.
    .PARAMETER LogLine
    The log line to sanitize.
    .PARAMETER PendingSensitiveValue
    Reference to the state used for a value split onto the next line.
    .OUTPUTS
    System.String
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $LogLine,
        [Parameter(Mandatory = $true)]
        [ref] $PendingSensitiveValue
    )

    if ($PendingSensitiveValue.Value) {
        # Keep the state across blank lines so pretty-printed JSON values do not
        # leak, but stop at the first non-empty physical line.
        if ([string]::IsNullOrWhiteSpace($LogLine)) {
            return $LogLine
        }
        $PendingSensitiveValue.Value = $false
        return '<redacted>'
    }

    # The delimiter and everything after a secret key are replaced as one unit.
    # This deliberately avoids trying to parse malformed or escaped JSON values.
    $secretKeyPattern = '(?i)(?<prefix>\b(?:access[\s_-]*token|auth[\s_-]*token|refresh[\s_-]*token|id[\s_-]*token|client[\s_-]*secret|password|passwd|passphrase|secret(?:[\s_-]*key)?|api[\s_-]*key|authorization|bearer|serial(?:[\s_-]*(?:number|key))?|license(?:[\s_-]*(?:key|serial))?|private[\s_-]*key|signing[\s_-]*key|token)\b(?:\s|\\?[\x22\x27])*[:=])(?<value>.*)$'
    $secretMatches = [regex]::Matches($LogLine, $secretKeyPattern)
    $hasEmptySecretValue = $false
    foreach ($secretMatch in $secretMatches) {
        if ([string]::IsNullOrWhiteSpace($secretMatch.Groups['value'].Value)) {
            $hasEmptySecretValue = $true
            break
        }
    }
    $sanitizedLine = [regex]::Replace($LogLine, $secretKeyPattern, '${prefix}<redacted>')

    # Handle both `Bearer "value"` and `"Bearer value"`, including escaped
    # quotes. The key-value rule above already covers Authorization headers.
    $quotedBearerPattern = '(?i)(?<quote>\\?[\x22\x27])(?<prefix>Bearer\s+)(?<value>(?:\\.|(?!\k<quote>)[^\\\r\n])*?)(?:\k<quote>)'
    $sanitizedLine = [regex]::Replace($sanitizedLine, $quotedBearerPattern, '${quote}${prefix}<redacted>${quote}')
    $bearerWithQuotedValuePattern = '(?i)(?<prefix>\bBearer\s+)(?<quote>\\?[\x22\x27])(?<value>(?:\\.|(?!\k<quote>)[^\\\r\n])*?)(?:\k<quote>)'
    $sanitizedLine = [regex]::Replace($sanitizedLine, $bearerWithQuotedValuePattern, '${prefix}${quote}<redacted>${quote}')
    # Treat everything after a bare Bearer prefix as credential material. This
    # avoids leaving a token fragment behind when malformed log text contains
    # spaces or trailing punctuation inside the value.
    $unquotedBearerPattern = '(?i)(?<prefix>\bBearer\s+)(?<value>(?!<redacted>).*)$'
    $sanitizedLine = [regex]::Replace($sanitizedLine, $unquotedBearerPattern, '${prefix}<redacted>')

    $PendingSensitiveValue.Value = $hasEmptySecretValue
    return $sanitizedLine
}

function Get-RedactedLogBlock {
    <#
    .SYNOPSIS
    Redacts sensitive values from every line in an extracted block.
    .DESCRIPTION
    Applies line-level key-value and Bearer masking while carrying only one
    immediate next-line pending-value state.
    .PARAMETER LogLines
    Lines belonging to the selected build interval.
    .OUTPUTS
    System.String[]
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $LogLines
    )

    $pendingSensitiveValue = $false
    $pendingReference = [ref] $pendingSensitiveValue
    $redactedLines = [System.Collections.Generic.List[string]]::new()
    foreach ($logLine in $LogLines) {
        $redactedLines.Add((Get-RedactedLogLine -LogLine $logLine -PendingSensitiveValue $pendingReference))
    }
    return @($redactedLines.ToArray())
}

function Get-BuildResultState {
    <#
    .SYNOPSIS
    Converts a Unity completion line to a normalized result state.
    .DESCRIPTION
    Maps success, failure, and cancellation wording to stable labels for output.
    .PARAMETER CompletionLine
    The line containing the detected completion marker.
    .OUTPUTS
    System.String
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $CompletionLine
    )
    if ($CompletionLine -match '(?i)\bresult\s+of\s*[\x27\x22]?(?<resultState>succeeded|successful|success|failed|failure|cancelled|canceled|error)\b') {
        switch ($Matches['resultState'].ToLowerInvariant()) {
            'succeeded' { return 'Succeeded' }
            'successful' { return 'Succeeded' }
            'success' { return 'Succeeded' }
            'cancelled' { return 'Cancelled' }
            'canceled' { return 'Cancelled' }
            'failed' { return 'Failed' }
            'failure' { return 'Failed' }
            'error' { return 'Failed' }
        }
    }
    if ($CompletionLine -match '(?i)\b(?:cancelled|canceled)\b') { return 'Cancelled' }
    if ($CompletionLine -match '(?i)\b(?:failed|failure|error)\b') { return 'Failed' }
    if ($CompletionLine -match '(?i)\b(?:succeeded|successful|success)\b') { return 'Succeeded' }
    return 'Completed'
}

function Get-UnityLogEvent {
    <#
    .SYNOPSIS
    Identifies one typed Unity build-log event from a line.
    .DESCRIPTION
    Uses anchored, explicit markers for starts so stack-trace method names such
    as BuildPlayerWindow are never treated as Player Build starts. Tundra's
    additional-run notice and ordinary output separators are intentionally not
    terminal events.
    .PARAMETER LogLine
    The line under inspection.
    .PARAMETER LineNumber
    One-based line number in the snapshot.
    .OUTPUTS
    PSCustomObject
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $LogLine,
        [Parameter(Mandatory = $true)]
        [int] $LineNumber
    )

    if ($null -eq $LogLine) { $LogLine = '' }
    $trimmedLine = $LogLine.TrimStart()
    if ([string]::IsNullOrWhiteSpace($trimmedLine)) { return $null }

    # This notice says another Tundra pass is needed; it is not a completion.
    if ($trimmedLine -match '(?i)^\*{3}\s*Tundra\s+(?:build\s+)?requires\s+additional\s+run\b') {
        return $null
    }

    # Script Compilation terminal markers must be checked before generic Build
    # wording so they cannot be mistaken for a Player Build terminal marker.
    if ($trimmedLine -match '(?i)^\*{3}\s*Tundra\s+build\s+(?:succeeded|successful|success|failed|failure|cancelled|canceled|error)\b') {
        return [pscustomobject]@{
            Kind = 'Script Compilation'
            EventType = 'End'
            LineNumber = $LineNumber
            Result = Get-BuildResultState -CompletionLine $trimmedLine
        }
    }
    if ($trimmedLine -match '(?i)^##\s+Script\s+Compilation\s+Error\s+for:') {
        return [pscustomobject]@{
            Kind = 'Script Compilation'
            EventType = 'End'
            LineNumber = $LineNumber
            Result = 'Failed'
        }
    }

    if ($LogLine -match '(?i)(?:^|\s)\[ScriptCompilation\]\s+Requested\s+script\s+compilation\b' -or
        $LogLine -match '(?i)(?:^|\s)Starting:\s+.*\bScriptCompilationBuildProgram\.exe\b') {
        return [pscustomobject]@{
            Kind = 'Script Compilation'
            EventType = 'Start'
            LineNumber = $LineNumber
            Result = $null
        }
    }

    # These start forms are deliberately anchored. In particular, neither
    # BuildPlayerWindow+DefaultBuildMethods:BuildPlayer nor UnityEditor stack
    # frames can satisfy them.
    if ($trimmedLine -match '(?i)^Building\s+Player\b' -or
        $trimmedLine -match '(?i)^BuildPipeline\.BuildPlayer\b' -or
        $trimmedLine -match '(?i)^BuildPlayer(?:\s|:|\(|$)' -or
        $trimmedLine -match '(?i)^BuildPlayer\s+(?:started|starting|begin|began)\b' -or
        $trimmedLine -match '(?i)^(?:Player\s+)?Build\s+(?:started|starting|begin|began)\b') {
        if ($trimmedLine -notmatch '(?i)BuildPlayerWindow|(?:^|\s)(?:at|Stack\s+trace)\b') {
            return [pscustomobject]@{
                Kind = 'Player Build'
                EventType = 'Start'
                LineNumber = $LineNumber
                Result = $null
            }
        }
    }

    if ($trimmedLine -notmatch '(?i)\bTundra\b' -and
        ($trimmedLine -match '(?i)^(?:Player\s+)?Build\s+completed\s+with\s+a\s+result\s+of\b' -or
         $trimmedLine -match '(?i)^Build\s+(?:succeeded|successful|success|failed|failure|cancelled|canceled|error)\b' -or
         $trimmedLine -match '(?i)^(?:Player\s+)?Build\s+(?:finished|complete|completed)\b')) {
        return [pscustomobject]@{
            Kind = 'Player Build'
            EventType = 'End'
            LineNumber = $LineNumber
            Result = Get-BuildResultState -CompletionLine $trimmedLine
        }
    }

    return $null
}

function Get-LogBlockCandidates {
    <#
    .SYNOPSIS
    Pairs typed Unity start and end events in one forward scan.
    .DESCRIPTION
    Maintains one active start for each event kind while scanning lines exactly
    once. Start order and completion order are retained explicitly, avoiding
    Hashtable enumeration or cross-kind regular-expression pairing.
    .PARAMETER LogLines
    Editor.log lines, without requiring the complete file to be emitted.
    .OUTPUTS
    PSCustomObject
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $LogLines
    )
    # The event classifier below supplies typed events; this function only pairs them.
    $completedCandidates = [System.Collections.Generic.List[object]]::new()
    $startEvents = [System.Collections.Generic.List[object]]::new()
    $activePlayerStartLine = $null
    $activeScriptStartLine = $null
    $latestStart = $null
    $latestCompleted = $null
    for ($index = 0; $index -lt $LogLines.Count; $index++) {
        $lineNumber = $index + 1
        $logEvent = Get-UnityLogEvent -LogLine $LogLines[$index] -LineNumber $lineNumber
        if ($null -eq $logEvent) { continue }

        if ($logEvent.EventType -eq 'Start') {
            $startEvents.Add($logEvent)
            $latestStart = $logEvent
            if ($logEvent.Kind -eq 'Player Build') {
                $activePlayerStartLine = $lineNumber
            } elseif ($logEvent.Kind -eq 'Script Compilation') {
                $activeScriptStartLine = $lineNumber
            }
            continue
        }

        if ($logEvent.EventType -eq 'End' -and $logEvent.Kind -eq 'Player Build' -and $null -ne $activePlayerStartLine) {
            $completedCandidate = [pscustomobject]@{
                Kind = 'Player Build'
                StartLine = $activePlayerStartLine
                EndLine = $lineNumber
                Complete = $true
                Result = $logEvent.Result
            }
            $completedCandidates.Add($completedCandidate)
            $latestCompleted = $completedCandidate
            $activePlayerStartLine = $null
            continue
        }

        if ($logEvent.EventType -eq 'End' -and $logEvent.Kind -eq 'Script Compilation' -and $null -ne $activeScriptStartLine) {
            $completedCandidate = [pscustomobject]@{
                Kind = 'Script Compilation'
                StartLine = $activeScriptStartLine
                EndLine = $lineNumber
                Complete = $true
                Result = $logEvent.Result
            }
            $completedCandidates.Add($completedCandidate)
            $latestCompleted = $completedCandidate
            $activeScriptStartLine = $null
        }
    }

    return [pscustomobject]@{
        Starts = @($startEvents.ToArray())
        Completed = @($completedCandidates.ToArray())
        LatestStart = $latestStart
        LatestCompleted = $latestCompleted
    }
}

function Read-SharedLogSnapshot {
    <#
    .SYNOPSIS
    Reads a bounded, shared Editor.log snapshot line by line.
    .DESCRIPTION
    Opens the file with FileShare.ReadWrite, enforces a byte-size limit, and
    records metadata needed to identify the snapshot after extraction.
    .PARAMETER Path
    Editor.log path.
    .PARAMETER MaximumBytes
    Maximum accepted file size in bytes.
    .OUTPUTS
    PSCustomObject
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [long] $MaximumBytes
    )

    $fileStream = $null
    $streamReader = $null
    try {
        $fileInfoBefore = Get-Item -LiteralPath $Path -ErrorAction Stop
        $fileLengthBefore = [int64] $fileInfoBefore.Length
        if ($fileLengthBefore -gt $MaximumBytes) {
            throw [System.InvalidOperationException]::new('input-size-limit')
        }

        $fileStream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $streamReader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8, $true, 4096, $false)
        $logLines = [System.Collections.Generic.List[string]]::new()
        while ($null -ne ($logLine = $streamReader.ReadLine())) {
            $logLines.Add($logLine)
            # StreamReader buffers a small amount, but this check also protects
            # against Unity growing the file after the initial metadata read.
            if ([int64] $streamReader.BaseStream.Position -gt $MaximumBytes) {
                throw [System.InvalidOperationException]::new('input-size-limit')
            }
        }

        $fileInfoAfter = Get-Item -LiteralPath $Path -ErrorAction Stop
        $fileLengthAfter = [int64] $fileInfoAfter.Length
        $lastWriteTimeBefore = $fileInfoBefore.LastWriteTimeUtc
        $lastWriteTimeAfter = $fileInfoAfter.LastWriteTimeUtc
        return [pscustomobject]@{
            Lines = @($logLines.ToArray())
            TotalLines = $logLines.Count
            FileLength = $fileLengthBefore
            LastWriteTimeUtc = $lastWriteTimeBefore
            FileLengthAfterRead = $fileLengthAfter
            LastWriteTimeUtcAfterRead = $lastWriteTimeAfter
            IsStable = ($fileLengthBefore -eq $fileLengthAfter -and $lastWriteTimeBefore -eq $lastWriteTimeAfter)
        }
    } finally {
        if ($null -ne $streamReader) {
            $streamReader.Dispose()
        } elseif ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
    }
}

function Limit-OutputLines {
    <#
    .SYNOPSIS
    Limits block lines while retaining the beginning and end.
    .DESCRIPTION
    Uses a compact marker when at least three output slots are available and
    reports the exact omitted count to the caller.
    .PARAMETER LogLines
    Redacted block lines.
    .PARAMETER MaximumLines
    Maximum number of emitted block lines.
    .OUTPUTS
    PSCustomObject
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $LogLines,
        [Parameter(Mandatory = $true)]
        [int] $MaximumLines
    )

    $lines = @($LogLines)
    if ($lines.Count -le $MaximumLines) {
        return [pscustomobject]@{
            Lines = $lines
            Truncated = $false
            OmittedCount = 0
        }
    }

    if ($MaximumLines -eq 1) {
        return [pscustomobject]@{
            Lines = @($lines[0])
            Truncated = $true
            OmittedCount = $lines.Count - 1
        }
    }

    if ($MaximumLines -eq 2) {
        return [pscustomobject]@{
            Lines = @($lines[0], $lines[$lines.Count - 1])
            Truncated = $true
            OmittedCount = $lines.Count - 2
        }
    }

    $payloadSlots = $MaximumLines - 1
    $headCount = [int] [math]::Ceiling($payloadSlots / 2.0)
    $tailCount = $payloadSlots - $headCount
    $omittedCount = $lines.Count - $headCount - $tailCount
    $limitedLines = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $headCount; $index++) {
        $limitedLines.Add($lines[$index])
    }
    $limitedLines.Add('[... log lines omitted ...]')
    for ($index = $lines.Count - $tailCount; $index -lt $lines.Count; $index++) {
        $limitedLines.Add($lines[$index])
    }
    return [pscustomobject]@{
        Lines = @($limitedLines.ToArray())
        Truncated = $true
        OmittedCount = $omittedCount
    }
}

function Limit-OutputCharacters {
    <#
    .SYNOPSIS
    Limits block text while retaining its beginning and end.
    .DESCRIPTION
    Inserts a fixed omission marker when the character limit permits one and
    returns the exact omitted count separately.
    .PARAMETER Text
    Redacted block text.
    .PARAMETER MaximumCharacters
    Maximum number of emitted block characters.
    .OUTPUTS
    PSCustomObject
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Text,
        [Parameter(Mandatory = $true)]
        [int] $MaximumCharacters
    )

    if ($Text.Length -le $MaximumCharacters) {
        return [pscustomobject]@{
            Text = $Text
            Truncated = $false
            OmittedCount = 0
        }
    }

    $marker = '[... output characters omitted ...]'
    $availableCharacters = $MaximumCharacters - $marker.Length
    if ($availableCharacters -lt 2) {
        return [pscustomobject]@{
            Text = $Text.Substring(0, $MaximumCharacters)
            Truncated = $true
            OmittedCount = $Text.Length - $MaximumCharacters
        }
    }

    $headCharacters = [int] [math]::Ceiling($availableCharacters / 2.0)
    $tailCharacters = $availableCharacters - $headCharacters
    $omittedCount = $Text.Length - $headCharacters - $tailCharacters
    return [pscustomobject]@{
        Text = $Text.Substring(0, $headCharacters) + $marker + $Text.Substring($Text.Length - $tailCharacters, $tailCharacters)
        Truncated = $true
        OmittedCount = $omittedCount
    }
}

$failureCategory = '読み取り失敗'
try {
    if (-not (Test-Path -LiteralPath $LogFilePath -PathType Leaf)) {
        $failureCategory = 'ファイル不存在'
        throw [System.IO.FileNotFoundException]::new('missing-log')
    }

    $snapshot = Read-SharedLogSnapshot -Path $LogFilePath -MaximumBytes $MaximumInputBytes
    $hasNonEmptyLine = $false
    foreach ($snapshotLine in @($snapshot.Lines)) {
        if (-not [string]::IsNullOrWhiteSpace($snapshotLine)) {
            $hasNonEmptyLine = $true
            break
        }
    }
    if ($snapshot.FileLength -eq 0 -or $snapshot.TotalLines -eq 0 -or -not $hasNonEmptyLine) {
        $failureCategory = 'ログ空'
        throw [System.InvalidOperationException]::new('empty-log')
    }
    if (-not $snapshot.IsStable) {
        $failureCategory = 'スナップショット変更'
        throw [System.InvalidOperationException]::new('snapshot-changed')
    }
    if ($snapshot.FileLengthAfterRead -gt $MaximumInputBytes) {
        $failureCategory = '入力上限超過'
        throw [System.InvalidOperationException]::new('input-size-limit')
    }

    $boundaryData = Get-LogBlockCandidates -LogLines $snapshot.Lines
    if ($null -eq $boundaryData.LatestStart) {
        $failureCategory = '境界なし'
        throw [System.InvalidOperationException]::new('no-boundary')
    }
    $latestStart = $boundaryData.LatestStart
    $latestStartCompleted = $false
    foreach ($completedCandidate in @($boundaryData.Completed)) {
        if ($completedCandidate.Kind -eq $latestStart.Kind -and $completedCandidate.StartLine -eq $latestStart.LineNumber) {
            $latestStartCompleted = $true
            break
        }
    }
    if (-not $latestStartCompleted) {
        $failureCategory = '最新未完了'
        throw [System.InvalidOperationException]::new('latest-start-incomplete')
    }
    if ($null -eq $boundaryData.LatestCompleted) {
        $failureCategory = '境界なし'
        throw [System.InvalidOperationException]::new('no-completed-boundary')
    }

    $latest = $boundaryData.LatestCompleted
    $selectedSourceLines = @($snapshot.Lines[($latest.StartLine - 1)..($latest.EndLine - 1)])
    $redactedLines = @(Get-RedactedLogBlock -LogLines $selectedSourceLines)
    $lineLimit = Limit-OutputLines -LogLines $redactedLines -MaximumLines $MaximumOutputLines
    $joinedText = $lineLimit.Lines -join "`r`n"
    $characterLimit = Limit-OutputCharacters -Text $joinedText -MaximumCharacters $MaximumOutputCharacters
    $wasTruncated = [bool] ($lineLimit.Truncated -or $characterLimit.Truncated)

    "分類: $($latest.Kind)"
    "開始行: $($latest.StartLine)"
    "終了行: $($latest.EndLine)"
    "結果: $($latest.Result)"
    "切り詰め: $wasTruncated"
    "行省略数: $($lineLimit.OmittedCount)"
    "文字省略数: $($characterLimit.OmittedCount)"
    "総行数: $($snapshot.TotalLines)"
    "読み取り時ファイル長: $($snapshot.FileLength)"
    "最終更新UTC: $($snapshot.LastWriteTimeUtc.ToString('o'))"
    "スナップショット安定: $($snapshot.IsStable)"
    '--- 抽出ブロック開始 ---'
    $characterLimit.Text
    '--- 抽出ブロック終了 ---'
    exit 0
} catch {
    # Internal sentinel messages are fixed constants, so mapping them here
    # preserves a useful category without exposing filesystem exception text.
    switch ($_.Exception.Message) {
        'input-size-limit' { $failureCategory = '入力上限超過' }
        'snapshot-changed' { $failureCategory = 'スナップショット変更' }
        'empty-log' { $failureCategory = 'ログ空' }
        'latest-start-incomplete' { $failureCategory = '最新未完了' }
        'no-boundary' { $failureCategory = '境界なし' }
        'no-completed-boundary' { $failureCategory = '完了境界なし' }
    }
    [Console]::Error.WriteLine("Unityビルドログを取得できません: $failureCategory")
    exit 1
}

#requires -Version 7.0
<#
.SYNOPSIS
Measures reproducible token, command, and stdout metrics from one session JSONL.

.DESCRIPTION
Reads one bounded JSONL snapshot with a shared read, records its content identity,
and emits one JSON measurement record. Child mode uses the final
turn_token_usage; Parent mode sums usage in a half-open UTC window. Any malformed,
inconsistent, oversized, or changed input fails closed.

.PARAMETER SessionFilePath
One session JSONL path to measure.

.PARAMETER AggregationMode
Child selects the final turn_token_usage. Parent sums payload.usage in the window.

.PARAMETER WindowStartUtc
Inclusive UTC start for Parent mode.

.PARAMETER WindowEndUtc
Exclusive UTC end for Parent mode.

.PARAMETER MaximumInputBytes
Maximum accepted snapshot size.

.PARAMETER AsJson
Compatibility switch; output is always one compact JSON measurement record.

.EXAMPLE
& .\Measure-RigorousReviewUsage.ps1 -SessionFilePath .\session.jsonl

.EXAMPLE
& .\Measure-RigorousReviewUsage.ps1 -SessionFilePath .\parent.jsonl -AggregationMode Parent -WindowStartUtc '2026-09-04T07:57:00Z' -WindowEndUtc '2026-09-04T08:33:00Z'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $SessionFilePath,
    [ValidateSet('Child', 'Parent')]
    [string] $AggregationMode = 'Child',
    [Nullable[datetimeoffset]] $WindowStartUtc,
    [Nullable[datetimeoffset]] $WindowEndUtc,
    [ValidateRange(1, 1073741824)]
    [long] $MaximumInputBytes = 536870912,
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$measurementSchemaVersion = 1
$measurementScriptVersion = '0.2.0'

function Get-Field {
    <# Reads one optional property from a JSON object. #>
    param(
        [AllowNull()][object] $Object,
        [Parameter(Mandatory = $true)][string] $Name
    )
    if ($null -eq $Object) { return $null }
    $property = $Object.psobject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-Utc {
    <# Converts a JSON timestamp to a UTC DateTimeOffset. #>
    param([AllowNull()][object] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetime]) { return [datetimeoffset]::new($Value).ToUniversalTime() }
    return [datetimeoffset]::Parse(
        [string] $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    )
}

function Get-Usage {
    <# Validates required non-negative usage counters and their relationships. #>
    param([Parameter(Mandatory = $true)][object] $Usage)
    $values = [ordered]@{}
    foreach ($name in @('input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens', 'total_tokens')) {
        $raw = Get-Field -Object $Usage -Name $name
        if ($null -eq $raw -or $raw -is [bool]) { throw "required usage counter '$name' is missing or not numeric" }
        try { $number = [decimal] $raw } catch { throw "usage counter '$name' is not numeric" }
        if ($number -lt 0 -or $number -ne [math]::Truncate($number) -or $number -gt [decimal][int64]::MaxValue) {
            throw "usage counter '$name' is not a non-negative integer"
        }
        $values[$name] = [int64] $number
    }
    if ($values['cached_input_tokens'] -gt $values['input_tokens']) { throw 'cached_input_tokens exceeds input_tokens' }
    if ($values['reasoning_output_tokens'] -gt $values['output_tokens']) { throw 'reasoning_output_tokens exceeds output_tokens' }
    if ([decimal]$values['total_tokens'] -ne ([decimal]$values['input_tokens'] + [decimal]$values['output_tokens'])) {
        throw 'total_tokens must equal input_tokens plus output_tokens'
    }
    return $values
}

function Add-Usage {
    <# Adds validated usage counters into cumulative totals. #>
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Totals,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Usage
    )
    foreach ($name in $Usage.Keys) { $Totals[$name] = [int64]$Totals[$name] + [int64]$Usage[$name] }
}

function Get-UnicodeCodePointCount {
    <# Counts Unicode scalar values instead of UTF-16 code units. #>
    param([AllowEmptyString()][string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return [int64] 0 }
    $count = [int64]$Text.Length
    for ($i = 0; $i -lt $Text.Length - 1; $i++) {
        if ([char]::IsHighSurrogate($Text[$i]) -and [char]::IsLowSurrogate($Text[$i + 1])) { $count--; $i++ }
    }
    return $count
}

function Get-SharedSha256 {
    <# Computes SHA-256 while allowing a writer to keep the file open. #>
    param([Parameter(Mandatory = $true)][string] $Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return [Convert]::ToHexString($algorithm.ComputeHash($stream)).ToLowerInvariant() } finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
}

function Read-Measurement {
    <# Reads one stable session file and returns its measurement record. #>
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Mode,
        [Parameter(Mandatory = $true)][long] $MaximumBytes,
        [AllowNull()][Nullable[datetimeoffset]] $StartUtc,
        [AllowNull()][Nullable[datetimeoffset]] $EndUtc
    )
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "session path is not a regular trusted file: $Path" }
    if ([int64]$file.Length -gt $MaximumBytes) { throw "input-size-limit: $($file.Length) > $MaximumBytes bytes" }
    $fullPath = $file.FullName
    $bytes = [int64]$file.Length
    $sha256 = Get-SharedSha256 -Path $fullPath
    $totals = [ordered]@{ input_tokens = [int64]0; cached_input_tokens = [int64]0; output_tokens = [int64]0; reasoning_output_tokens = [int64]0; total_tokens = [int64]0 }
    $finalUsage = $null
    $lineNumber = 0
    $finalTokenOrdinal = $null
    $execCalls = 0
    $commands = 0
    $stdoutCodePoints = [int64]0
    $stdoutBytes = [int64]0
    $compactions = 0
    $stream = $null
    $reader = $null
    try {
        $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true, 65536, $false)
        while ($null -ne ($line = $reader.ReadLine())) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $record = $line | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { throw "invalid JSONL at ordinal $lineNumber" }
            $type = [string](Get-Field -Object $record -Name 'type')
            if ([string]::IsNullOrWhiteSpace($type)) { throw "record at ordinal $lineNumber has no type" }
            $timestampValue = Get-Field -Object $record -Name 'timestamp'
            if ($null -eq $timestampValue) { $timestampValue = Get-Field -Object $record -Name 'created_at' }
            if ($Mode -eq 'Parent' -and $type -in @('token_usage_record', 'response_item', 'event_msg') -and $null -eq $timestampValue) { throw "record at ordinal $lineNumber has no timestamp" }
            if ($Mode -eq 'Child' -and $type -eq 'token_usage_record' -and $null -eq $timestampValue) { throw "token_usage_record at ordinal $lineNumber has no timestamp" }
            $timestamp = if ($null -eq $timestampValue) { $null } else { ConvertTo-Utc -Value $timestampValue }
            $inScope = $true
            if ($Mode -eq 'Parent') { $inScope = $timestamp -ge $StartUtc -and $timestamp -lt $EndUtc }
            switch ($type) {
                'token_usage_record' {
                    $payload = Get-Field -Object $record -Name 'payload'
                    if ($null -eq $payload) { throw "token_usage_record at ordinal $lineNumber has no payload" }
                    if ($Mode -eq 'Child') {
                        $rawUsage = Get-Field -Object $payload -Name 'turn_token_usage'
                        if ($null -eq $rawUsage) { throw "token_usage_record at ordinal $lineNumber has no turn_token_usage" }
                        $finalUsage = Get-Usage -Usage $rawUsage
                        $finalTokenOrdinal = $lineNumber
                    } elseif ($inScope) {
                        $rawUsage = Get-Field -Object $payload -Name 'usage'
                        if ($null -eq $rawUsage) { throw "scoped token_usage_record at ordinal $lineNumber has no usage" }
                        Add-Usage -Totals $totals -Usage (Get-Usage -Usage $rawUsage)
                    }
                }
                'response_item' {
                    if ($inScope) {
                        $payload = Get-Field -Object $record -Name 'payload'
                        if ($null -eq $payload) { throw "response_item at ordinal $lineNumber has no payload" }
                        if ([string](Get-Field -Object $payload -Name 'type') -eq 'custom_tool_call' -and [string](Get-Field -Object $payload -Name 'name') -eq 'exec') { $execCalls++ }
                    }
                }
                'event_msg' {
                    if ($inScope) {
                        $payload = Get-Field -Object $record -Name 'payload'
                        if ($null -eq $payload) { throw "event_msg at ordinal $lineNumber has no payload" }
                        $payloadType = [string](Get-Field -Object $payload -Name 'type')
                        if ($payloadType -eq 'item_completed') {
                            $item = Get-Field -Object $payload -Name 'item'
                            if ($null -eq $item) { throw "item_completed at ordinal $lineNumber has no item" }
                            $itemType = [string](Get-Field -Object $item -Name 'type')
                            if ([string]::IsNullOrWhiteSpace($itemType)) { throw "item_completed at ordinal $lineNumber has no item type" }
                            if ($itemType -eq 'CommandExecution') {
                                $stdout = Get-Field -Object $item -Name 'stdout'
                                if ($null -eq $stdout) { throw "CommandExecution at ordinal $lineNumber has no stdout" }
                                $commands++
                                $stdout = [string]$stdout
                                $stdoutCodePoints += Get-UnicodeCodePointCount -Text $stdout
                                $stdoutBytes += [Text.Encoding]::UTF8.GetByteCount($stdout)
                            } elseif ($itemType -eq 'ContextCompaction') { $compactions++ }
                        } elseif ($payloadType -eq 'compacted') { $compactions++ }
                    }
                }
            }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() } elseif ($null -ne $stream) { $stream.Dispose() }
    }
    $after = Get-Item -LiteralPath $fullPath -ErrorAction Stop
    if ([int64]$after.Length -ne $bytes -or (Get-SharedSha256 -Path $fullPath) -ne $sha256) { throw "session snapshot changed while reading: $fullPath" }
    if ($Mode -eq 'Child') {
        if ($null -eq $finalUsage) { throw 'child session has no token_usage_record' }
        Add-Usage -Totals $totals -Usage $finalUsage
    }
    $window = if ($Mode -eq 'Parent') { [ordered]@{ start_utc = ([datetimeoffset]$StartUtc).ToString('o'); end_utc_exclusive = ([datetimeoffset]$EndUtc).ToString('o') } } else { $null }
    return [ordered]@{
        schema_version = $measurementSchemaVersion
        script_version = $measurementScriptVersion
        aggregation = if ($Mode -eq 'Child') { 'child_final_turn_token_usage' } else { 'parent_window_usage_sum' }
        source = [ordered]@{ path = $fullPath; sha256 = $sha256; bytes = $bytes; final_ordinal = $lineNumber; timestamp_window = $window }
        usage = [ordered]@{ total_tokens = $totals['total_tokens']; gross_input_tokens = $totals['input_tokens']; cached_input_tokens = $totals['cached_input_tokens']; uncached_input_tokens = $totals['input_tokens'] - $totals['cached_input_tokens']; output_tokens = $totals['output_tokens']; reasoning_output_tokens = $totals['reasoning_output_tokens']; reasoning_is_output_subset = $true }
        execution = [ordered]@{ exec_tool_calls = $execCalls; command_executions = $commands; stdout_unicode_codepoints = $stdoutCodePoints; stdout_utf8_bytes = $stdoutBytes; compactions = $compactions }
    }
}

try {
    $startUtc = $null
    $endUtc = $null
    if ($AggregationMode -eq 'Parent') {
        if ($null -eq $WindowStartUtc -or $null -eq $WindowEndUtc) { throw 'Parent mode requires WindowStartUtc and WindowEndUtc' }
        $startUtc = ConvertTo-Utc -Value $WindowStartUtc
        $endUtc = ConvertTo-Utc -Value $WindowEndUtc
        if ($endUtc -le $startUtc) { throw 'WindowEndUtc must be later than WindowStartUtc' }
    } elseif ($null -ne $WindowStartUtc -or $null -ne $WindowEndUtc) { throw 'WindowStartUtc and WindowEndUtc are valid only in Parent mode' }
    $result = Read-Measurement -Path $SessionFilePath -Mode $AggregationMode -MaximumBytes $MaximumInputBytes -StartUtc $startUtc -EndUtc $endUtc
    $result | ConvertTo-Json -Depth 12 -Compress
    exit 0
} catch {
    Write-Error $_
    exit 2
}

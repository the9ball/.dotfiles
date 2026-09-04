#requires -Version 7.0
<#
.SYNOPSIS
Runs dependency-free acceptance tests for Measure-RigorousReviewUsage.ps1.

.DESCRIPTION
Generates small, medium, and large allowlisted JSONL fixtures in a temporary
directory, then verifies aggregation, safe replacement, Unicode accounting,
fail-closed validation, input bounds, and read-time change detection.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Measure-RigorousReviewUsage.ps1'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('rigorous-review-measure-' + [guid]::NewGuid().ToString('N'))
$assertionCount = 0
$sentinel = 'SENTINEL-MUST-NOT-BE-COPIED'

function Assert-Condition {
    <# Fails the test when a condition is false. #>
    param([Parameter(Mandatory = $true)][bool] $Condition, [Parameter(Mandatory = $true)][string] $Message)
    $script:assertionCount++
    if (-not $Condition) { throw $Message }
}

function New-AllowlistedRecord {
    <# Converts a constrained synthetic source object to an allowlisted record. #>
    param(
        [Parameter(Mandatory = $true)][object] $Source,
        [Parameter(Mandatory = $true)][ValidateSet('Child', 'Parent')][string] $Mode
    )
    switch ($Source.kind) {
        'usage' {
            $usage = [ordered]@{ input_tokens = $Source.input; cached_input_tokens = $Source.cached; output_tokens = $Source.output; reasoning_output_tokens = $Source.reasoning; total_tokens = $Source.total }
            $payload = [ordered]@{ thread_id = $Source.thread; session_id = $Source.session; turn_id = $Source.turn }
            if ($Mode -eq 'Child') { $payload.turn_token_usage = $usage } else { $payload.usage = $usage }
            return [ordered]@{ timestamp = $Source.timestamp; ordinal = $Source.ordinal; type = 'token_usage_record'; payload = $payload }
        }
        'exec' { return [ordered]@{ timestamp = $Source.timestamp; ordinal = $Source.ordinal; type = 'response_item'; payload = [ordered]@{ type = 'custom_tool_call'; name = 'exec'; id = $Source.turn } } }
        'not_exec' { return [ordered]@{ timestamp = $Source.timestamp; ordinal = $Source.ordinal; type = 'response_item'; payload = [ordered]@{ type = 'custom_tool_call'; name = 'other'; id = $Source.turn } } }
        'command' { return [ordered]@{ timestamp = $Source.timestamp; ordinal = $Source.ordinal; type = 'event_msg'; payload = [ordered]@{ type = 'item_completed'; item = [ordered]@{ type = 'CommandExecution'; id = $Source.turn; stdout = $Source.stdout; stderr = $Source.stderr } } } }
        'compaction' { return [ordered]@{ timestamp = $Source.timestamp; ordinal = $Source.ordinal; type = 'event_msg'; payload = [ordered]@{ type = 'item_completed'; item = [ordered]@{ type = 'ContextCompaction'; id = $Source.turn } } } }
        default { throw "unsupported synthetic kind: $($Source.kind)" }
    }
}

function Write-AllowlistedSession {
    <# Writes a deterministic fixture after replacing source data through an allowlist. #>
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][ValidateSet('Child', 'Parent')][string] $Mode,
        [Parameter(Mandatory = $true)][ValidateSet('small', 'medium', 'large')][string] $Size,
        [ValidateSet('None', 'MissingCounter', 'CachedExceedsGross', 'ReasoningExceedsOutput', 'MissingTimestamp')][string] $Invalid = 'None'
    )
    $repeat = @{ small = 1; medium = 3; large = 500 }[$Size]
    $sources = [System.Collections.Generic.List[object]]::new()
    $baseTime = [datetimeoffset]::Parse('2026-09-04T07:57:01Z')
    for ($i = 0; $i -lt $repeat; $i++) {
        $stamp = $baseTime.AddSeconds(2 * $i).ToString('o')
        $turn = 'turn-{0:D4}' -f $i
        $sources.Add([pscustomobject]@{ kind = 'usage'; timestamp = $stamp; ordinal = $i * 4 + 1; input = 10 + $i; cached = 2; output = 3; reasoning = 1; total = 13 + $i; thread = 'thread-synthetic'; session = 'session-synthetic'; turn = $turn; command = 'C:\private\command'; secret = $sentinel }) | Out-Null
        $sources.Add([pscustomobject]@{ kind = if ($i -eq 0) { 'not_exec' } else { 'exec' }; timestamp = $baseTime.AddSeconds(2 * $i + 1).ToString('o'); ordinal = $i * 4 + 2; turn = $turn; command = 'C:\private\command'; secret = $sentinel }) | Out-Null
        $sources.Add([pscustomobject]@{ kind = 'command'; timestamp = $baseTime.AddSeconds(2 * $i + 1.5).ToString('o'); ordinal = $i * 4 + 3; turn = $turn; stdout = if ($i % 3 -eq 1) { '' } elseif ($i % 3 -eq 2) { '界😀' } else { "A😀é`n" }; stderr = if ($i % 3 -eq 1) { 'stderr-only synthetic warning' } else { '' }; command = 'C:\private\command'; secret = $sentinel }) | Out-Null
        $sources.Add([pscustomobject]@{ kind = 'compaction'; timestamp = $baseTime.AddSeconds(2 * $i + 1.75).ToString('o'); ordinal = $i * 4 + 4; turn = $turn; command = 'C:\private\command'; secret = $sentinel }) | Out-Null
    }
    if ($Mode -eq 'Parent') {
        $sources.Add([pscustomobject]@{ kind = 'usage'; timestamp = '2026-09-04T08:34:00Z'; ordinal = $repeat * 4 + 1; input = 99; cached = 9; output = 9; reasoning = 1; total = 108; thread = 'thread-synthetic'; session = 'session-synthetic'; turn = 'turn-outside'; command = 'C:\private\command'; secret = $sentinel }) | Out-Null
        $sources.Add([pscustomobject]@{ kind = 'command'; timestamp = '2026-09-04T08:34:01Z'; ordinal = $repeat * 4 + 2; turn = 'turn-outside'; stdout = 'outside-window'; stderr = ''; command = 'C:\private\command'; secret = $sentinel }) | Out-Null
    }
    $bad = @($sources | Where-Object kind -eq 'usage')[0]
    switch ($Invalid) {
        'MissingCounter' { $bad.output = $null }
        'CachedExceedsGross' { $bad.cached = 11 }
        'ReasoningExceedsOutput' { $bad.reasoning = 4 }
        'MissingTimestamp' { $bad.timestamp = $null }
    }
    $lines = foreach ($source in $sources) { New-AllowlistedRecord -Source $source -Mode $Mode | ConvertTo-Json -Depth 12 -Compress }
    $content = ($lines -join "`n") + "`n"
    [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
    return $content
}

function Invoke-Measurement {
    <# Invokes the measurement script and parses its single JSON result. #>
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][ValidateSet('Child', 'Parent')][string] $Mode,
        [datetime] $StartUtc,
        [datetime] $EndUtc,
        [long] $MaximumInputBytes
    )
    $arguments = @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $Path, '-AggregationMode', $Mode)
    if ($Mode -eq 'Parent') { $arguments += @('-WindowStartUtc', $StartUtc.ToString('o'), '-WindowEndUtc', $EndUtc.ToString('o')) }
    if ($PSBoundParameters.ContainsKey('MaximumInputBytes')) { $arguments += @('-MaximumInputBytes', [string]$MaximumInputBytes) }
    $output = & pwsh @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "measurement failed unexpectedly: $($output -join "`n")" }
    return (($output -join "`n") | ConvertFrom-Json -Depth 20)
}

function Assert-MeasurementFailure {
    <# Verifies a non-zero exit code and, when given, an expected error marker. #>
    param([Parameter(Mandatory = $true)][string[]] $Arguments, [Parameter(Mandatory = $true)][string] $Pattern)
    $output = & pwsh @Arguments 2>&1
    Assert-Condition -Condition ($LASTEXITCODE -ne 0) -Message "expected measurement failure: $Pattern"
    $joined = $output -join "`n"
    Assert-Condition -Condition ($joined -match $Pattern) -Message "failure did not contain '$Pattern': $joined"
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $paths = @{}
    foreach ($size in @('small', 'medium', 'large')) {
        $path = Join-Path $temporaryRoot "$size.jsonl"
        Write-AllowlistedSession -Path $path -Mode Child -Size $size | Out-Null
        $paths[$size] = $path
        $text = [IO.File]::ReadAllText($path)
        Assert-Condition -Condition (-not $text.Contains($sentinel) -and -not $text.Contains('C:\private\command')) -Message "$size fixture contains non-allowlisted data"
        $result = Invoke-Measurement -Path $path -Mode Child
        Assert-Condition -Condition ($result.source.sha256 -match '^[0-9a-f]{64}$') -Message "$size hash format"
        Assert-Condition -Condition ([int64]$result.source.bytes -eq [IO.FileInfo]::new($path).Length) -Message "$size byte identity"
    }

    $medium = Invoke-Measurement -Path $paths.medium -Mode Child
    Assert-Condition -Condition ($medium.aggregation -eq 'child_final_turn_token_usage' -and $medium.usage.total_tokens -eq 15 -and $medium.usage.gross_input_tokens -eq 12 -and $medium.usage.cached_input_tokens -eq 2 -and $medium.usage.uncached_input_tokens -eq 10) -Message 'child final usage'
    Assert-Condition -Condition ($medium.usage.output_tokens -eq 3 -and $medium.usage.reasoning_output_tokens -eq 1 -and $medium.usage.reasoning_is_output_subset) -Message 'child reasoning relationship'
    Assert-Condition -Condition ($medium.execution.exec_tool_calls -eq 2 -and $medium.execution.command_executions -eq 3 -and $medium.execution.stdout_unicode_codepoints -eq 6 -and $medium.execution.stdout_utf8_bytes -eq 15 -and $medium.execution.compactions -eq 3) -Message 'child execution separation'
    $expectedHash = (Get-FileHash -LiteralPath $paths.medium -Algorithm SHA256).Hash.ToLowerInvariant()
    $mediumLineCount = @([IO.File]::ReadLines($paths.medium)).Count
    Assert-Condition -Condition ($medium.source.sha256 -eq $expectedHash -and $medium.source.final_ordinal -eq $mediumLineCount) -Message 'fixed source identity'

    $parentPath = Join-Path $temporaryRoot 'parent.jsonl'
    Write-AllowlistedSession -Path $parentPath -Mode Parent -Size small | Out-Null
    $parent = Invoke-Measurement -Path $parentPath -Mode Parent -StartUtc ([datetime]'2026-09-04T07:57:00Z') -EndUtc ([datetime]'2026-09-04T08:33:00Z')
    Assert-Condition -Condition ($parent.usage.total_tokens -eq 13 -and $parent.usage.gross_input_tokens -eq 10 -and $parent.usage.cached_input_tokens -eq 2 -and $parent.usage.uncached_input_tokens -eq 8 -and $parent.execution.command_executions -eq 1) -Message 'parent half-open window'

    foreach ($invalid in @('MissingCounter', 'CachedExceedsGross', 'ReasoningExceedsOutput')) {
        $path = Join-Path $temporaryRoot "$invalid.jsonl"
        Write-AllowlistedSession -Path $path -Mode Child -Size small -Invalid $invalid | Out-Null
        $pattern = switch ($invalid) { 'MissingCounter' { 'required usage counter' } 'CachedExceedsGross' { 'cached_input_tokens exceeds' } 'ReasoningExceedsOutput' { 'reasoning_output_tokens exceeds' } }
        Assert-MeasurementFailure -Arguments @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $path) -Pattern $pattern
    }
    $missingTimestampPath = Join-Path $temporaryRoot 'missing-timestamp.jsonl'
    Write-AllowlistedSession -Path $missingTimestampPath -Mode Parent -Size small -Invalid MissingTimestamp | Out-Null
    Assert-MeasurementFailure -Arguments @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $missingTimestampPath, '-AggregationMode', 'Parent', '-WindowStartUtc', '2026-09-04T07:57:00Z', '-WindowEndUtc', '2026-09-04T08:33:00Z') -Pattern 'no timestamp'

    $invalidPath = Join-Path $temporaryRoot 'invalid.jsonl'
    [IO.File]::WriteAllText($invalidPath, "{not-json`n", [Text.UTF8Encoding]::new($false))
    Assert-MeasurementFailure -Arguments @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $invalidPath) -Pattern 'invalid JSONL'
    Assert-MeasurementFailure -Arguments @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $paths.small, '-AggregationMode', 'Parent') -Pattern 'requires WindowStartUtc'
    Assert-MeasurementFailure -Arguments @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $paths.small, '-MaximumInputBytes', '1') -Pattern 'input-size-limit'

    $changePath = $paths.large
    $appendCode = "for(`$i = 0; `$i -lt 3000; `$i++) { Add-Content -LiteralPath '$changePath' -Value ''; Start-Sleep -Milliseconds 2 }"
    $writer = Start-Process -FilePath pwsh -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', $appendCode) -PassThru
    try {
        Assert-MeasurementFailure -Arguments @('-NoProfile', '-File', $scriptPath, '-SessionFilePath', $changePath) -Pattern 'changed while reading'
    } finally {
        $writer.WaitForExit()
    }

    Write-Output ("PASS: {0} assertions" -f $assertionCount)
    exit 0
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

#requires -Version 7.4

[CmdletBinding()]
param()

# Reuse the shared sender. Dot-sourcing defines its functions without running its entry point.
. (Join-Path $PSScriptRoot 'codex-stop-hook.ps1')

function Read-HookInput {
    <#
    .SYNOPSIS
    Reads the Stop hook input as UTF-8 text within a size and time limit.
    .PARAMETER InputStream
    The caller-owned input stream. It is read to the end but not disposed.
    .PARAMETER MaximumBytes
    Inputs larger than this are still drained so the producer is not cut off,
    but their content is discarded and not parsed.
    .PARAMETER TimeoutMilliseconds
    Total time allowed to reach the end of the input.
    .OUTPUTS
    System.String, or $null when the input is absent, oversized, unreadable, or
    does not end within the time limit.
    #>
    param(
        [AllowNull()][IO.Stream]$InputStream,
        [int]$MaximumBytes = 16MB,
        [int]$TimeoutMilliseconds = 3000
    )
    if ($null -eq $InputStream) { return $null }
    $Buffer = [byte[]]::new(65536)
    $Collected = [IO.MemoryStream]::new()
    $Elapsed = [Diagnostics.Stopwatch]::StartNew()
    $Oversized = $false
    try {
        while ($true) {
            $RemainingMilliseconds = $TimeoutMilliseconds - $Elapsed.ElapsedMilliseconds
            if ($RemainingMilliseconds -le 0) { return $null }
            $ReadTask = $InputStream.ReadAsync($Buffer, 0, $Buffer.Length)
            if (-not $ReadTask.Wait([int]$RemainingMilliseconds)) { return $null }
            $ReadCount = $ReadTask.GetAwaiter().GetResult()
            if ($ReadCount -eq 0) { break }
            if ($Collected.Length + $ReadCount -gt $MaximumBytes) { $Oversized = $true }
            if (-not $Oversized) { $Collected.Write($Buffer, 0, $ReadCount) }
        }
        if ($Oversized) { return $null }
        return [Text.Encoding]::UTF8.GetString($Collected.ToArray())
    }
    catch {
        return $null
    }
    finally {
        $Collected.Dispose()
    }
}

function Test-ClaudeTurnIdle {
    <#
    .SYNOPSIS
    Decides whether a Claude Code Stop event means the session waits for the user.
    .PARAMETER InputText
    The raw Stop hook input JSON, or $null when it could not be read.
    .OUTPUTS
    System.Boolean. $false only when background_tasks or session_crons is a
    non-empty array, which means background work will resume the session.
    .NOTES
    Only those two fields are inspected, and no input value is retained or output.
    Missing, malformed, or unexpected input counts as idle, so a change in the
    input format causes extra notifications instead of silently stopping them.
    #>
    param([AllowNull()][string]$InputText)
    if ([string]::IsNullOrWhiteSpace($InputText)) { return $true }
    try {
        $HookInput = ConvertFrom-Json -InputObject $InputText -AsHashtable -Depth 64 -NoEnumerate
    }
    catch {
        return $true
    }
    if ($HookInput -isnot [Collections.IDictionary]) { return $true }
    foreach ($FieldName in @('background_tasks', 'session_crons')) {
        $FieldValue = $HookInput[$FieldName]
        if ($FieldValue -is [Collections.IList] -and $FieldValue.Count -gt 0) { return $false }
    }
    return $true
}

function Invoke-ClaudeStopHook {
    <#
    .SYNOPSIS
    Sends the fixed Claude Code notification only when no background work remains.
    .PARAMETER InputStream
    The Stop hook input. Pass $null to treat the input as unavailable.
    .OUTPUTS
    System.String. An empty JSON object with no continuation decision.
    #>
    param([AllowNull()][IO.Stream]$InputStream)
    try {
        $InputText = Read-HookInput -InputStream $InputStream
        if (Test-ClaudeTurnIdle -InputText $InputText) {
            $null = Invoke-TurnNotification -Source 'Claude'
        }
    }
    catch {
        # A notification must never request continuation or change the turn result.
    }
    return '{}'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $InputStream = if ([Console]::IsInputRedirected) { [Console]::OpenStandardInput() } else { $null }
        $Response = Invoke-ClaudeStopHook -InputStream $InputStream
    }
    catch {
        $Response = '{}'
    }
    try { [Console]::Out.WriteLine($Response) }
    catch {
        # A closed output pipe must not produce a secondary hook error.
    }
    exit 0
}

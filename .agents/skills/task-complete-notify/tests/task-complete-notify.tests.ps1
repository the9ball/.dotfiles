#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SkillDirectory = Split-Path -Parent $PSScriptRoot
$ScriptDirectory = Join-Path $SkillDirectory 'scripts'
$PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'
$TestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$SecondTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$ThirdTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$FourthTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$StopActiveTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$ResidentTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$TransientTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$GenerationTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$NotHandledTestId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
$FixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "task-complete-notify-tests-$([Guid]::NewGuid().ToString('N'))"
$StateDirectory = Join-Path $FixtureRoot '.task-complete-notify'
$CreatedStatePaths = [Collections.Generic.List[string]]::new()
$ResidentProcess = $null

function Assert-Condition {
    <#
    .SYNOPSIS
    Fails the test run when a required condition is false.

    .PARAMETER Condition
    The condition that must be true.

    .PARAMETER Name
    A fixed test identifier; it must not contain notification content.

    .OUTPUTS
    None. Throws a generic assertion error on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $Condition) {
        throw "assert_failed:$Name"
    }
}

function Invoke-NativeWithInput {
    <#
    .SYNOPSIS
    Runs a PowerShell script with UTF-8 JSON on standard input.

    .PARAMETER ScriptPath
    The script to execute.

    .PARAMETER InputText
    The JSON input sent only through standard input.

    .PARAMETER Arguments
    Additional non-secret script arguments.

    .OUTPUTS
    PSCustomObject. Returns exit code and captured output for assertions.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [string]$InputText,

        [string[]]$Arguments = @()
    )

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
    [void]$StartInfo.ArgumentList.Add($ScriptPath)
    foreach ($Argument in $Arguments) {
        [void]$StartInfo.ArgumentList.Add($Argument)
    }

    $Process = [Diagnostics.Process]::new()
    try {
        $Process.StartInfo = $StartInfo
        if (-not $Process.Start()) {
            throw 'process_start_failed'
        }

        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.StandardInput.Write($InputText)
        $Process.StandardInput.Close()
        if (-not $Process.WaitForExit(60000)) {
            try {
                $Process.Kill($true)
            }
            catch {
                # The test child is already terminating.
            }
            throw 'process_timeout'
        }

        return [pscustomobject]@{
            ExitCode = $Process.ExitCode
            Stdout = $OutputTask.GetAwaiter().GetResult()
            Stderr = $ErrorTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $Process.Dispose()
    }
}

function Start-DetachedPowerShell {
    <#
    .SYNOPSIS
    Starts a background PowerShell script for resident-watcher assertions.

    .PARAMETER ScriptPath
    The script to execute.

    .PARAMETER Arguments
    Non-secret script arguments.

    .OUTPUTS
    System.Diagnostics.Process. Returns the started process handle.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [string[]]$Arguments = @()
    )

    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $PowerShellExecutable
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    [void]$StartInfo.ArgumentList.Add('-NoProfile')
    [void]$StartInfo.ArgumentList.Add('-NonInteractive')
    [void]$StartInfo.ArgumentList.Add('-File')
    [void]$StartInfo.ArgumentList.Add($ScriptPath)
    foreach ($Argument in $Arguments) {
        [void]$StartInfo.ArgumentList.Add($Argument)
    }

    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    if (-not $Process.Start()) {
        $Process.Dispose()
        throw 'process_start_failed'
    }

    return $Process
}

function Read-JsonFile {
    <#
    .SYNOPSIS
    Reads a test JSON file for non-secret state assertions.

    .PARAMETER Path
    The explicit test-state path to read.

    .OUTPUTS
    System.Object. Returns the parsed JSON document.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function New-TestTranscript {
    <#
    .SYNOPSIS
    Creates a minimal Codex-style transcript fixture.

    .PARAMETER Path
    The explicit fixture path.

    .PARAMETER ThreadId
    The user session UUID to put in session_meta.

    .PARAMETER IncludeOldComplete
    Adds a task_complete record timestamped before arm.

    .OUTPUTS
    None. The fixture is written as UTF-8 JSONL.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ThreadId,

        [switch]$IncludeOldComplete
    )

    $Lines = [Collections.Generic.List[string]]::new()
    $Lines.Add((
        [ordered]@{
            timestamp = [DateTimeOffset]::UtcNow.ToString('o')
            type = 'session_meta'
            payload = [ordered]@{
                id = $ThreadId
                session_id = $ThreadId
                thread_source = 'user'
            }
        } | ConvertTo-Json -Compress
    ))

    if ($IncludeOldComplete) {
        $Lines.Add((
            [ordered]@{
                timestamp = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
                type = 'event_msg'
                payload = [ordered]@{
                    type = 'task_complete'
                    turn_id = $ThreadId
                }
            } | ConvertTo-Json -Compress
        ))
    }

    [IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function Add-TestSessionIndexEntry {
    <#
    .SYNOPSIS
    Appends a minimal local Codex session-index fixture entry.

    .PARAMETER ThreadId
    The UUID represented by the fixture rollout.

    .PARAMETER CodexHomePath
    Optional fixture Codex home; the main fixture home is used by default.

    .OUTPUTS
    None. The entry is appended to the explicit test Codex home index.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThreadId,

        [string]$CodexHomePath = $FixtureRoot
    )

    $IndexPath = Join-Path $CodexHomePath 'session_index.jsonl'
    $Entry = [ordered]@{
        id = $ThreadId
        thread_name = 'fixture'
        updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($IndexPath, "$Entry`n", [Text.UTF8Encoding]::new($false))
}

function Remove-TestState {
    <#
    .SYNOPSIS
    Removes only the explicit state files created by this test run.

    .OUTPUTS
    None. Cleanup is limited to known generated paths.
    #>
    foreach ($Path in $CreatedStatePaths) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

$OriginalNtfyTopic = [Environment]::GetEnvironmentVariable('NTFY_TOPIC', 'Process')
$OriginalCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
$OriginalWatcherMode = [Environment]::GetEnvironmentVariable('TASK_COMPLETE_NOTIFY_WATCHER', 'Process')

try {
    New-Item -ItemType Directory -Force -Path $FixtureRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $FixtureRoot 'sessions\2026\01') | Out-Null
    [Environment]::SetEnvironmentVariable('NTFY_TOPIC', $null, 'Process')
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $FixtureRoot, 'Process')
    [Environment]::SetEnvironmentVariable('TASK_COMPLETE_NOTIFY_WATCHER', $null, 'Process')

    foreach ($InitialThreadId in @($TestId, $SecondTestId, $ThirdTestId, $FourthTestId, $StopActiveTestId)) {
        $InitialTranscriptPath = Join-Path $FixtureRoot "sessions\2026\01\rollout-2026-01-01T00-00-00-$InitialThreadId.jsonl"
        New-TestTranscript -Path $InitialTranscriptPath -ThreadId $InitialThreadId
        Add-TestSessionIndexEntry -ThreadId $InitialThreadId
    }

    foreach ($ScriptFile in Get-ChildItem -LiteralPath $ScriptDirectory -Filter '*.ps1' -File -Recurse) {
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptFile.FullName, [ref]$Tokens, [ref]$Errors) | Out-Null
        Assert-Condition ($Errors.Count -eq 0) "parser_$($ScriptFile.BaseName)"
    }

    $StopHookText = Get-Content -Raw -LiteralPath (Join-Path $ScriptDirectory 'codex-stop-hook.ps1')
    $ArmText = Get-Content -Raw -LiteralPath (Join-Path $ScriptDirectory 'arm-notification.ps1')
    $NotifyText = Get-Content -Raw -LiteralPath (Join-Path $ScriptDirectory 'notify.ps1')
    $HelperText = Get-Content -Raw -LiteralPath (Join-Path $ScriptDirectory 'windows-helper.ps1')
    $WatcherText = Get-Content -Raw -LiteralPath (Join-Path $ScriptDirectory 'codex-watcher.ps1')
    Assert-Condition (-not ($StopHookText -match '\[Console\]::InputEncoding')) 'stop_no_console_encoding_mutation'
    Assert-Condition (-not ($ArmText -match '\[Console\]::InputEncoding')) 'arm_no_console_encoding_mutation'
    Assert-Condition (-not ($NotifyText -match '\[Console\]::InputEncoding')) 'notify_no_console_encoding_mutation'
    Assert-Condition (-not ($HelperText -match '\[Console\]::InputEncoding')) 'helper_no_console_encoding_mutation'
    Assert-Condition (-not ($WatcherText -match '\[Console\]::InputEncoding')) 'watcher_no_console_encoding_mutation'
    Assert-Condition ($StopHookText -match '\[Console\]::OpenStandardInput\(\)' -and
        $NotifyText -match '\[Console\]::OpenStandardInput\(\)' -and
        $HelperText -match '\[Console\]::OpenStandardInput\(\)') 'explicit_utf8_stdin_readers'
    Assert-Condition ($StopHookText -match '\$HelperTimeoutMilliseconds\s*=\s*55000' -and
        $StopHookText -match 'WaitForExit\(\$HelperTimeoutMilliseconds\)') 'stop_timeout_headroom'
    Assert-Condition ($HelperText -match '\$NotifierTimeoutMilliseconds\s*=\s*35000' -and
        $HelperText -match 'WaitForExit\(\$NotifierTimeoutMilliseconds\)' -and
        $NotifyText -match '-ConnectionTimeoutSeconds\s+10' -and
        $NotifyText -match '-OperationTimeoutSeconds\s+20' -and
        $StopHookText -match '\$HelperTimeoutMilliseconds\s*=\s*55000' -and
        (10000 + 35000 + 5000) -lt 55000 -and
        55000 -lt 90000) 'notification_timeout_hierarchy'
    Assert-Condition (-not ($WatcherText -match '\.task-complete-notify\.invalid') -and
        -not ($HelperText -match '\.task-complete-notify\.invalid')) 'no_invalid_home_fallback_path'

    $NotifyPath = Join-Path $ScriptDirectory 'notify.ps1'
    $NotifyResult = Invoke-NativeWithInput -ScriptPath $NotifyPath -InputText '{"message":"Task completed"}'
    $NotifyJson = $NotifyResult.Stdout.Trim() | ConvertFrom-Json
    Assert-Condition ($NotifyJson.Ok -eq $false -and $NotifyJson.Reason -eq 'topic_missing') 'notify_missing_topic'
    Assert-Condition ([string]::IsNullOrWhiteSpace($NotifyResult.Stderr)) 'notify_no_stderr'

    $ArmPath = Join-Path $ScriptDirectory 'arm-notification.ps1'
    $StopPath = Join-Path $ScriptDirectory 'codex-stop-hook.ps1'
    $WatcherPath = Join-Path $ScriptDirectory 'codex-watcher.ps1'
    $InvalidHomePath = Join-Path $SkillDirectory '.task-complete-notify.invalid'
    $InvalidHomeValue = Join-Path $FixtureRoot 'missing-codex-home'
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $InvalidHomeValue, 'Process')
    $InvalidHomeOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $TestId
    $InvalidHomeJson = ($InvalidHomeOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $InvalidHomeJson.Ok -eq $false) 'invalid_home_rejected'
    Assert-Condition (-not (Test-Path -LiteralPath $InvalidHomePath -PathType Container)) 'invalid_home_no_skill_state'
    $InvalidWatcherOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once 2>$null
    Assert-Condition ($LASTEXITCODE -ne 0) 'invalid_watcher_home_rejected'
    Assert-Condition (-not (Test-Path -LiteralPath $InvalidHomePath -PathType Container)) 'invalid_watcher_no_skill_state'
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $FixtureRoot, 'Process')
    $StatePath = Join-Path $StateDirectory "requests\$TestId.json"
    $CheckpointPath = Join-Path $StateDirectory "checkpoints\$TestId.json"
    $TerminalPath = Join-Path $StateDirectory "terminal\$TestId.json"
    foreach ($Path in @($StatePath, $CheckpointPath, $TerminalPath, (Join-Path $StateDirectory "locks\$TestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }

    $ForeignId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
    $ForeignOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $ForeignId
    $ForeignJson = ($ForeignOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $ForeignJson.Status -eq 'thread_not_managed') 'foreign_thread_rejected'
    Assert-Condition (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) 'foreign_does_not_create_state'

    $ArmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread "対象: [thread](codex://threads/$TestId) / $TestId" -Message '初回本文'
    $ArmExitCode = $LASTEXITCODE
    $ArmJson = ($ArmOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($ArmExitCode -eq 0 -and $ArmJson.Ok -eq $true -and $ArmJson.Status -eq 'armed') 'arm_explicit_message'
    Assert-Condition ((Read-JsonFile -Path $StatePath).notification.message -eq '初回本文') 'arm_message_literal'
    Assert-Condition (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) 'arm_checkpoint'

    $RearmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $TestId -Message '上書き不可'
    $RearmJson = ($RearmOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($RearmJson.Ok -eq $true -and $RearmJson.Status -eq 'already_armed') 'rearm_idempotent'
    Assert-Condition ((Read-JsonFile -Path $StatePath).notification.message -eq '初回本文') 'rearm_preserves_message'

    $StopActiveStatePath = Join-Path $StateDirectory "requests\\$StopActiveTestId.json"
    $StopActiveCheckpointPath = Join-Path $StateDirectory "checkpoints\\$StopActiveTestId.json"
    $StopActiveTerminalPath = Join-Path $StateDirectory "terminal\\$StopActiveTestId.json"
    foreach ($Path in @($StopActiveStatePath, $StopActiveCheckpointPath, $StopActiveTerminalPath, (Join-Path $StateDirectory "locks\\$StopActiveTestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }
    & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $StopActiveTestId -Message '停止hook再入' | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'stop_hook_active_arm'
    $StopActiveTranscriptPath = Join-Path $FixtureRoot "sessions\2026\01\stop-active-$StopActiveTestId.jsonl"
    New-TestTranscript -Path $StopActiveTranscriptPath -ThreadId $StopActiveTestId
    $StopActiveInput = [ordered]@{
        hook_event_name = 'Stop'
        session_id = $StopActiveTestId
        transcript_path = $StopActiveTranscriptPath
        turn_id = $SecondTestId
        stop_hook_active = $true
    } | ConvertTo-Json -Compress
    $StopActiveResult = Invoke-NativeWithInput -ScriptPath $StopPath -InputText $StopActiveInput
    Assert-Condition ($StopActiveResult.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($StopActiveResult.Stdout)) 'stop_hook_active_silent'
    Assert-Condition ((Read-JsonFile -Path $StopActiveStatePath).status -eq 'armed') 'stop_hook_active_keeps_state'
    Assert-Condition (-not (Test-Path -LiteralPath $StopActiveTerminalPath -PathType Leaf)) 'stop_hook_active_no_terminal'
    # This request was intentionally preserved by the re-entry test; remove
    # its fixture before starting the resident watcher scenario below.
    Remove-Item -LiteralPath $StopActiveStatePath, $StopActiveCheckpointPath -Force -ErrorAction Stop

    $PersonalCodexHome = Join-Path $FixtureRoot 'personal-home'
    $PersonalSessionsDirectory = Join-Path $PersonalCodexHome 'sessions\2026\01'
    New-Item -ItemType Directory -Force -Path $PersonalSessionsDirectory | Out-Null
    $PersonalTranscriptPath = Join-Path $PersonalSessionsDirectory "rollout-2026-01-01T00-00-00-$TestId.jsonl"
    New-TestTranscript -Path $PersonalTranscriptPath -ThreadId $TestId
    Add-TestSessionIndexEntry -ThreadId $TestId -CodexHomePath $PersonalCodexHome
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $PersonalCodexHome, 'Process')
    $PersonalStateDirectory = Join-Path $PersonalCodexHome '.task-complete-notify'
    $PersonalStatePath = Join-Path $PersonalStateDirectory "requests\$TestId.json"
    [void]$CreatedStatePaths.Add($PersonalStatePath)
    $PersonalArmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $TestId -Message 'personal home'
    Assert-Condition ($LASTEXITCODE -eq 0) 'personal_home_arm'
    Assert-Condition ((Read-JsonFile -Path $PersonalStatePath).notification.message -eq 'personal home') 'personal_home_state_isolated'
    Assert-Condition ((Read-JsonFile -Path $StatePath).notification.message -eq '初回本文') 'default_home_state_preserved'
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $FixtureRoot, 'Process')

    $AttemptingStatePath = Join-Path $StateDirectory "requests\$SecondTestId.json"
    $AttemptingCheckpointPath = Join-Path $StateDirectory "checkpoints\$SecondTestId.json"
    $AttemptingTerminalPath = Join-Path $StateDirectory "terminal\$SecondTestId.json"
    foreach ($Path in @($AttemptingStatePath, $AttemptingCheckpointPath, $AttemptingTerminalPath, (Join-Path $StateDirectory "locks\$SecondTestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }
    $AttemptingArmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $SecondTestId -Message '孤立予約'
    Assert-Condition ($LASTEXITCODE -eq 0) 'attempting_arm'
    $AttemptingState = Read-JsonFile -Path $AttemptingStatePath
    $AttemptingStateDocument = [ordered]@{
        schemaVersion = $AttemptingState.schemaVersion
        provider = $AttemptingState.provider
        generation = $AttemptingState.generation
        status = 'attempting'
        target = [ordered]@{ threadId = $SecondTestId }
        event = [ordered]@{ turnId = $ThirdTestId }
        claimedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($AttemptingStatePath, ($AttemptingStateDocument | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
    $OrphanRearmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $SecondTestId -Message '新世代'
    $OrphanRearmJson = ($OrphanRearmOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -eq 0 -and $OrphanRearmJson.Ok -eq $true -and $OrphanRearmJson.Status -eq 'armed') 'attempting_rearm'
    Assert-Condition ((Read-JsonFile -Path $AttemptingTerminalPath).status -eq 'abandoned') 'attempting_abandoned'
    Assert-Condition ((Read-JsonFile -Path $AttemptingStatePath).notification.message -eq '新世代') 'attempting_new_generation'
    # The orphan-rearm case is complete; remove its deliberately retained
    # active generation so later watcher tests have a single live request.
    Remove-Item -LiteralPath $AttemptingStatePath, $AttemptingCheckpointPath -Force -ErrorAction Stop

    $TranscriptPath = Join-Path $FixtureRoot "sessions\2026\01\stop-$TestId.jsonl"
    New-TestTranscript -Path $TranscriptPath -ThreadId $TestId
    $ExternalTranscriptPath = Join-Path $FixtureRoot "external-$TestId.jsonl"
    New-TestTranscript -Path $ExternalTranscriptPath -ThreadId $TestId
    $ExternalStopInput = [ordered]@{
        hook_event_name = 'Stop'
        session_id = $TestId
        transcript_path = $ExternalTranscriptPath
        turn_id = $SecondTestId
        stop_hook_active = $false
    } | ConvertTo-Json -Compress
    $ExternalStopResult = Invoke-NativeWithInput -ScriptPath $StopPath -InputText $ExternalStopInput
    Assert-Condition ($ExternalStopResult.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($ExternalStopResult.Stdout)) 'stop_external_transcript_silent'
    Assert-Condition (Test-Path -LiteralPath $StatePath -PathType Leaf) 'stop_external_transcript_keeps_active'
    $StopInput = [ordered]@{
        hook_event_name = 'Stop'
        session_id = $TestId
        transcript_path = $TranscriptPath
        turn_id = $SecondTestId
        stop_hook_active = $false
    } | ConvertTo-Json -Compress
    $StopResult = Invoke-NativeWithInput -ScriptPath $StopPath -InputText $StopInput
    Assert-Condition ($StopResult.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($StopResult.Stdout)) 'stop_silent_output'
    Assert-Condition (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) 'stop_consumes_active'
    Assert-Condition ((Read-JsonFile -Path $TerminalPath).status -eq 'failure') 'stop_terminal_failure'
    $SecondStopResult = Invoke-NativeWithInput -ScriptPath $StopPath -InputText $StopInput
    Assert-Condition ($SecondStopResult.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($SecondStopResult.Stdout)) 'stop_no_resend'

    $InvalidUriOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread "codex://$ThirdTestId"
    $InvalidUriJson = ($InvalidUriOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $InvalidUriJson.Ok -eq $false) 'legacy_uri_rejected'

    $AmbiguousOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread "対象 $ThirdTestId と $FourthTestId"
    $AmbiguousJson = ($AmbiguousOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $AmbiguousJson.Status -eq 'thread_ambiguous') 'ambiguous_thread_rejected'

    $AttachedUuidOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread "prefix$ThirdTestId"
    $AttachedUuidJson = ($AttachedUuidOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $AttachedUuidJson.Status -eq 'thread_invalid') 'attached_uuid_rejected'

    $DecoratedUriOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread "codex://threads/${FourthTestId}?view=full"
    $DecoratedUriJson = ($DecoratedUriOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $DecoratedUriJson.Status -eq 'thread_invalid') 'decorated_uri_rejected'

    $OversizedThreadOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread ('x' * 4097)
    $OversizedThreadJson = ($OversizedThreadOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $OversizedThreadJson.Status -eq 'thread_invalid') 'oversized_thread_rejected'

    $InvalidMessageOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $ThirdTestId -Message "A`nB"
    $InvalidMessageJson = ($InvalidMessageOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $InvalidMessageJson.Ok -eq $false) 'newline_message_rejected'

    $LongMessage = 'あ' * 100
    $LongMessageOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $FourthTestId -Message $LongMessage
    $LongMessageJson = ($LongMessageOutput -join "`n") | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -ne 0 -and $LongMessageJson.Ok -eq $false) 'long_message_rejected'

    $WatcherId = [Guid]::NewGuid().ToString('D').ToLowerInvariant()
    $WatcherRollout = Join-Path $FixtureRoot "sessions\2026\01\rollout-2026-01-01T00-00-00-$WatcherId.jsonl"
    New-TestTranscript -Path $WatcherRollout -ThreadId $WatcherId -IncludeOldComplete
    Add-TestSessionIndexEntry -ThreadId $WatcherId
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $FixtureRoot, 'Process')
    $WatcherStatePath = Join-Path $StateDirectory "requests\$WatcherId.json"
    $WatcherCheckpointPath = Join-Path $StateDirectory "checkpoints\$WatcherId.json"
    $WatcherTerminalPath = Join-Path $StateDirectory "terminal\$WatcherId.json"
    foreach ($Path in @($WatcherStatePath, $WatcherCheckpointPath, $WatcherTerminalPath, (Join-Path $StateDirectory "locks\$WatcherId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }

    $WatcherArmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $WatcherId -Message 'watcher本文'
    Assert-Condition ($LASTEXITCODE -eq 0) 'watcher_arm'
    $WatcherOnce = & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once
    Assert-Condition ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $WatcherStatePath -PathType Leaf)) 'watcher_ignores_old_complete'

    $PartialEvent = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        type = 'event_msg'
        payload = [ordered]@{
            type = 'task_complete'
            turn_id = $WatcherId
        }
    } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($WatcherRollout, $PartialEvent.Substring(0, [Math]::Max(1, $PartialEvent.Length - 3)), [Text.UTF8Encoding]::new($false))
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once | Out-Null
    Assert-Condition (Test-Path -LiteralPath $WatcherStatePath -PathType Leaf) 'watcher_ignores_partial_line'
    [IO.File]::AppendAllText($WatcherRollout, $PartialEvent.Substring([Math]::Max(1, $PartialEvent.Length - 3)) + "`n", [Text.UTF8Encoding]::new($false))
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once | Out-Null
    Assert-Condition (-not (Test-Path -LiteralPath $WatcherStatePath -PathType Leaf)) 'watcher_consumes_complete_line'
    Assert-Condition ((Read-JsonFile -Path $WatcherTerminalPath).status -eq 'failure') 'watcher_terminal_failure'

    $ResidentRollout = Join-Path $FixtureRoot "sessions\2026\01\rollout-2026-01-01T00-00-00-$ResidentTestId.jsonl"
    New-TestTranscript -Path $ResidentRollout -ThreadId $ResidentTestId
    Add-TestSessionIndexEntry -ThreadId $ResidentTestId
    $ResidentStatePath = Join-Path $StateDirectory "requests\$ResidentTestId.json"
    $ResidentCheckpointPath = Join-Path $StateDirectory "checkpoints\$ResidentTestId.json"
    $ResidentTerminalPath = Join-Path $StateDirectory "terminal\$ResidentTestId.json"
    foreach ($Path in @($ResidentStatePath, $ResidentCheckpointPath, $ResidentTerminalPath, (Join-Path $StateDirectory "locks\$ResidentTestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }
    $ResidentArmOutput = & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $ResidentTestId -Message '常駐待機'
    Assert-Condition ($LASTEXITCODE -eq 0) 'resident_arm'
    $ResidentProcess = Start-DetachedPowerShell `
        -ScriptPath $WatcherPath `
        -Arguments @('-PollIntervalMilliseconds', '100')
    Start-Sleep -Milliseconds 500
    $ResidentProcess.Refresh()
    Assert-Condition (-not $ResidentProcess.HasExited) 'resident_watcher_waits'
    $ResidentEvent = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        type = 'event_msg'
        payload = [ordered]@{
            type = 'task_complete'
            turn_id = $ResidentTestId
        }
    } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($ResidentRollout, "$ResidentEvent`n", [Text.UTF8Encoding]::new($false))
    $ResidentDeadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
    while ($true) {
        $ResidentProcess.Refresh()
        if ($ResidentProcess.HasExited -or [DateTimeOffset]::UtcNow -ge $ResidentDeadline) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    $ResidentProcess.Refresh()
    Assert-Condition $ResidentProcess.HasExited 'resident_watcher_consumes'
    [void]$ResidentProcess.WaitForExit()
    Assert-Condition (-not (Test-Path -LiteralPath $ResidentStatePath -PathType Leaf)) 'resident_consumes_active'
    Assert-Condition ((Read-JsonFile -Path $ResidentTerminalPath).status -eq 'failure') 'resident_terminal_failure'
    $ResidentProcess.Dispose()
    $ResidentProcess = $null

    $TransientRollout = Join-Path $FixtureRoot "sessions\2026\01\rollout-2026-01-01T00-00-00-$TransientTestId.jsonl"
    New-TestTranscript -Path $TransientRollout -ThreadId $TransientTestId
    Add-TestSessionIndexEntry -ThreadId $TransientTestId
    $TransientStatePath = Join-Path $StateDirectory "requests\$TransientTestId.json"
    $TransientCheckpointPath = Join-Path $StateDirectory "checkpoints\$TransientTestId.json"
    $TransientTerminalPath = Join-Path $StateDirectory "terminal\$TransientTestId.json"
    foreach ($Path in @($TransientStatePath, $TransientCheckpointPath, $TransientTerminalPath, (Join-Path $StateDirectory "locks\$TransientTestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }
    & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $TransientTestId -Message '一時失敗' | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'transient_arm'
    $TransientState = Read-JsonFile -Path $TransientStatePath
    $TransientCheckpoint = Read-JsonFile -Path $TransientCheckpointPath
    $TransientBaselineEntry = @($TransientCheckpoint.files | Where-Object { $_.path -eq $TransientRollout })[0]
    Assert-Condition ($null -ne $TransientBaselineEntry) 'transient_baseline_entry'
    $TransientBaselineOffset = [long]$TransientBaselineEntry.offset
    $TransientEvent = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        type = 'event_msg'
        payload = [ordered]@{
            type = 'task_complete'
            turn_id = $TransientTestId
        }
    } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($TransientRollout, "$TransientEvent`n", [Text.UTF8Encoding]::new($false))
    $MissingHelperPath = Join-Path $FixtureRoot 'missing-helper.ps1'
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once -HelperScriptPath $MissingHelperPath | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $TransientStatePath -PathType Leaf)) 'transient_keeps_active'
    $TransientAfterCheckpoint = Read-JsonFile -Path $TransientCheckpointPath
    $TransientAfterEntry = @($TransientAfterCheckpoint.files | Where-Object { $_.path -eq $TransientRollout })[0]
    Assert-Condition ($TransientAfterCheckpoint.generation -eq $TransientState.generation) 'transient_generation_preserved'
    Assert-Condition ([long]$TransientAfterEntry.offset -eq $TransientBaselineOffset) 'transient_offset_preserved'
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once | Out-Null
    Assert-Condition (-not (Test-Path -LiteralPath $TransientStatePath -PathType Leaf)) 'transient_recovered'
    Assert-Condition ((Read-JsonFile -Path $TransientTerminalPath).status -eq 'failure') 'transient_terminal_failure'

    $NotHandledRollout = Join-Path $FixtureRoot "sessions\2026\01\rollout-2026-01-01T00-00-00-$NotHandledTestId.jsonl"
    New-TestTranscript -Path $NotHandledRollout -ThreadId $NotHandledTestId
    Add-TestSessionIndexEntry -ThreadId $NotHandledTestId
    $NotHandledStatePath = Join-Path $StateDirectory "requests\$NotHandledTestId.json"
    $NotHandledCheckpointPath = Join-Path $StateDirectory "checkpoints\$NotHandledTestId.json"
    $NotHandledTerminalPath = Join-Path $StateDirectory "terminal\$NotHandledTestId.json"
    foreach ($Path in @($NotHandledStatePath, $NotHandledCheckpointPath, $NotHandledTerminalPath, (Join-Path $StateDirectory "locks\$NotHandledTestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }
    & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $NotHandledTestId -Message '未処理保持' | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'not_handled_arm'
    $NotHandledState = Read-JsonFile -Path $NotHandledStatePath
    $NotHandledCheckpoint = Read-JsonFile -Path $NotHandledCheckpointPath
    $NotHandledBaselineEntry = @($NotHandledCheckpoint.files | Where-Object { $_.path -eq $NotHandledRollout })[0]
    Assert-Condition ($null -ne $NotHandledBaselineEntry) 'not_handled_baseline_entry'
    $NotHandledBaselineOffset = [long]$NotHandledBaselineEntry.offset
    $NotHandledEvent = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        type = 'event_msg'
        payload = [ordered]@{
            type = 'task_complete'
            turn_id = $NotHandledTestId
        }
    } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($NotHandledRollout, "$NotHandledEvent`n", [Text.UTF8Encoding]::new($false))
    $NotHandledHelperPath = Join-Path $FixtureRoot 'not-handled-helper.ps1'
    $NotHandledHelperText = @'
#requires -Version 7.4
[Console]::In.ReadToEnd() | Out-Null
[Console]::Out.WriteLine('{"Ok":true,"Handled":false}')
'@
    [IO.File]::WriteAllText($NotHandledHelperPath, $NotHandledHelperText, [Text.UTF8Encoding]::new($false))
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once -HelperScriptPath $NotHandledHelperPath | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $NotHandledStatePath -PathType Leaf)) 'not_handled_keeps_active'
    $NotHandledAfterCheckpoint = Read-JsonFile -Path $NotHandledCheckpointPath
    $NotHandledAfterEntry = @($NotHandledAfterCheckpoint.files | Where-Object { $_.path -eq $NotHandledRollout })[0]
    Assert-Condition ([long]$NotHandledAfterEntry.offset -eq $NotHandledBaselineOffset) 'not_handled_offset_preserved'
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once | Out-Null
    Assert-Condition (-not (Test-Path -LiteralPath $NotHandledStatePath -PathType Leaf)) 'not_handled_recovered'
    Assert-Condition ((Read-JsonFile -Path $NotHandledTerminalPath).status -eq 'failure') 'not_handled_terminal_failure'

    $GenerationRollout = Join-Path $FixtureRoot "sessions\2026\01\rollout-2026-01-01T00-00-00-$GenerationTestId.jsonl"
    New-TestTranscript -Path $GenerationRollout -ThreadId $GenerationTestId
    Add-TestSessionIndexEntry -ThreadId $GenerationTestId
    $GenerationStatePath = Join-Path $StateDirectory "requests\$GenerationTestId.json"
    $GenerationCheckpointPath = Join-Path $StateDirectory "checkpoints\$GenerationTestId.json"
    $GenerationTerminalPath = Join-Path $StateDirectory "terminal\$GenerationTestId.json"
    foreach ($Path in @($GenerationStatePath, $GenerationCheckpointPath, $GenerationTerminalPath, (Join-Path $StateDirectory "locks\$GenerationTestId.lock"))) {
        [void]$CreatedStatePaths.Add($Path)
    }
    & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $GenerationTestId -Message '世代A' | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'generation_arm_a'
    $GenerationStateA = Read-JsonFile -Path $GenerationStatePath
    $GenerationAttempting = [ordered]@{
        schemaVersion = $GenerationStateA.schemaVersion
        provider = $GenerationStateA.provider
        generation = $GenerationStateA.generation
        status = 'attempting'
        target = [ordered]@{ threadId = $GenerationTestId }
        event = [ordered]@{ turnId = $GenerationTestId }
        claimedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($GenerationStatePath, ($GenerationAttempting | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
    & $PowerShellExecutable -NoProfile -NonInteractive -File $ArmPath -Thread $GenerationTestId -Message '世代B' | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) 'generation_arm_b'
    $GenerationStateB = Read-JsonFile -Path $GenerationStatePath
    Assert-Condition ($GenerationStateA.generation -ne $GenerationStateB.generation) 'generation_rotated'
    $StaleCheckpoint = [ordered]@{
        schemaVersion = 1
        provider = 'codex'
        generation = $GenerationStateA.generation
        target = [ordered]@{ threadId = $GenerationTestId }
        armedAtUtc = $GenerationStateA.armedAtUtc
        files = @(
            [ordered]@{
                path = $GenerationRollout
                offset = 0
            }
        )
    }
    [IO.File]::WriteAllText($GenerationCheckpointPath, ($StaleCheckpoint | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
    & $PowerShellExecutable -NoProfile -NonInteractive -File $WatcherPath -Once | Out-Null
    $GenerationAfterCheckpoint = Read-JsonFile -Path $GenerationCheckpointPath
    Assert-Condition ($GenerationAfterCheckpoint.generation -eq $GenerationStateB.generation) 'stale_generation_replaced'

    [Console]::Out.WriteLine('task-complete-notify tests: PASS')
}
catch {
    if ($_.Exception.Message -match '^assert_failed:[A-Za-z0-9_]+$') {
        [Console]::Error.WriteLine("task-complete-notify tests: FAIL ($($_.Exception.Message))")
    }
    else {
        [Console]::Error.WriteLine("task-complete-notify tests: FAIL (unexpected:$($_.Exception.GetType().Name):line$($_.InvocationInfo.ScriptLineNumber))")
    }
    exit 1
}
finally {
    if ($null -ne $ResidentProcess) {
        try {
            $ResidentProcess.Refresh()
            if (-not $ResidentProcess.HasExited) {
                $ResidentProcess.Kill($true)
                [void]$ResidentProcess.WaitForExit()
            }
        }
        catch {
            # The resident test child may already have exited or been cleaned up.
        }
        finally {
            $ResidentProcess.Dispose()
            $ResidentProcess = $null
        }
    }
    Remove-TestState
    if ($null -eq $OriginalNtfyTopic) {
        [Environment]::SetEnvironmentVariable('NTFY_TOPIC', $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('NTFY_TOPIC', $OriginalNtfyTopic, 'Process')
    }
    if ($null -eq $OriginalCodexHome) {
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $OriginalCodexHome, 'Process')
    }
    if ($null -eq $OriginalWatcherMode) {
        [Environment]::SetEnvironmentVariable('TASK_COMPLETE_NOTIFY_WATCHER', $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('TASK_COMPLETE_NOTIFY_WATCHER', $OriginalWatcherMode, 'Process')
    }
    Remove-Item -LiteralPath $FixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

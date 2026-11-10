#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SkillDirectory = Split-Path -Parent $PSScriptRoot
$HookPath = Join-Path $SkillDirectory 'scripts/codex-stop-hook.ps1'
$ClaudeHookPath = Join-Path $SkillDirectory 'scripts/claude-stop-hook.ps1'
$OriginalTopic = [Environment]::GetEnvironmentVariable('NTFY_TOPIC', 'Process')
$OriginalCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
$FixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("task-complete-notify-tests-" + [Guid]::NewGuid().ToString('N'))
$SandboxEnvironment = @{}
Get-ChildItem Env: | Where-Object Name -Match 'SANDBOX|PROXY|PERMISSION' | ForEach-Object {
    $SandboxEnvironment[$_.Name] = $_.Value
}

function Assert-Condition {
    <#
    .SYNOPSIS
    Fails a test with a fixed assertion name, never the actual sensitive value.
    #>
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw $Name }
}

function Invoke-HookProcess {
    <#
    .SYNOPSIS
    Checks the real entry point with independent normal, open, and large inputs.
    .PARAMETER Topic
    An unset or invalid topic that cannot initiate HTTP.
    .PARAMETER InputCase
    Normal closes small input, open withholds EOF, and large sends one MiB.
    .PARAMETER ScriptPath
    The entry point to run: the Codex hook by default, or the Claude Code hook.
    .OUTPUTS
    None. Asserts bounded writes and exit, empty errors, and inert JSON.
    #>
    param(
        [AllowNull()][string]$Topic,
        [ValidateSet('normal', 'open', 'large')]
        [string]$InputCase = 'normal',
        [string]$ScriptPath = $HookPath
    )
    $ProcessTimeoutMilliseconds = 30000
    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = (Get-Process -Id $PID).Path
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardInput = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    foreach ($Argument in @('-NoProfile', '-NonInteractive', '-File', $ScriptPath)) {
        $StartInfo.ArgumentList.Add($Argument)
    }
    [void]$StartInfo.Environment.Remove('NTFY_TOPIC')
    if ($null -ne $Topic) { $StartInfo.Environment['NTFY_TOPIC'] = $Topic }
    $StartInfo.Environment['CODEX_HOME'] = Join-Path $FixtureRoot 'process-home'
    $Process = [Diagnostics.Process]::new()
    $Started = $false
    try {
        $Process.StartInfo = $StartInfo
        $Started = $Process.Start()
        Assert-Condition $Started 'process_start'
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $InputText = if ($InputCase -eq 'large') {
            '{"last_assistant_message":"' + ('x' * 1048576) + '","transcript_path":"private-path"}'
        } else {
            '{"last_assistant_message":"private-answer","stop_hook_active":true}'
        }
        $WriteTask = $Process.StandardInput.WriteAsync($InputText)
        Assert-Condition ($WriteTask.Wait($ProcessTimeoutMilliseconds)) 'process_write_bounded'
        $FlushTask = $Process.StandardInput.FlushAsync()
        Assert-Condition ($FlushTask.Wait($ProcessTimeoutMilliseconds)) 'process_flush_bounded'
        if ($InputCase -ne 'open') { $Process.StandardInput.Close() }
        Assert-Condition ($Process.WaitForExit($ProcessTimeoutMilliseconds)) 'process_exit_bounded'
        Assert-Condition ($Process.ExitCode -eq 0) 'process_exit_zero'
        Assert-Condition ($OutputTask.GetAwaiter().GetResult().Trim() -ceq '{}') 'process_inert_json'
        Assert-Condition ($ErrorTask.GetAwaiter().GetResult() -ceq '') 'process_no_errors'
    }
    finally {
        if ($Started -and -not $Process.HasExited) { $Process.Kill($true) }
        $Process.Dispose()
    }
}

try {
    $env:NTFY_TOPIC = 'offline-fixture-topic'
    $env:CODEX_HOME = Join-Path $FixtureRoot 'initial-home'
    # The Claude entry point dot-sources the shared sender too, so load it before
    # the fixture client below replaces the production one.
    . $ClaudeHookPath
    $ProductionClientFactory = ${function:New-NotificationHttpClient}
    $Client = New-NotificationHttpClient
    Assert-Condition ($Client.Timeout.TotalSeconds -eq 10) 'production_total_deadline'
    $Client.Dispose()

    # The in-memory transport prevents every test case from reaching the network.
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

/// <summary>In-memory HTTP transport that captures requests without networking.</summary>
public sealed class NotificationFixtureHandler : HttpMessageHandler
{
    public int StatusCode = 200;
    public string Mode = "response";
    public int Calls;
    public string Body = "";
    public string Uri = "";
    public string Method = "";
    public int HeaderCount;
    public string MediaType = "";
    public bool Disposed;

    /// <summary>Captures the fixed request and simulates response, error, or deadline.</summary>
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Calls++;
        Body = await request.Content.ReadAsStringAsync();
        Uri = request.RequestUri.AbsoluteUri;
        Method = request.Method.Method;
        MediaType = request.Content.Headers.ContentType.MediaType;
        foreach (var header in request.Headers) HeaderCount++;
        if (Mode == "error") throw new HttpRequestException("private-topic private-credential");
        if (Mode == "timeout") await Task.Delay(Timeout.Infinite, cancellationToken);
        return new HttpResponseMessage((HttpStatusCode)StatusCode)
        {
            Content = new StringContent("private-response-body")
        };
    }

    /// <summary>Tracks transport disposal to verify per-invocation resource cleanup.</summary>
    protected override void Dispose(bool disposing)
    {
        Disposed = true;
        base.Dispose(disposing);
    }
}
'@

    function New-NotificationHttpClient {
        <#
        .SYNOPSIS
        Supplies only the in-memory fixture transport with a short real deadline.
        #>
        $Client = [Net.Http.HttpClient]::new($script:FixtureHandler)
        $Client.Timeout = [TimeSpan]::FromMilliseconds(100)
        return $Client
    }

    $script:FixtureHandler = [NotificationFixtureHandler]::new()
    $InputProducer = [IO.Pipes.AnonymousPipeServerStream]::new([IO.Pipes.PipeDirection]::Out)
    $InputConsumer = [IO.Pipes.AnonymousPipeClientStream]::new(
        [IO.Pipes.PipeDirection]::In, $InputProducer.ClientSafePipeHandle
    )
    try {
        $InputBytes = [Text.Encoding]::UTF8.GetBytes('{}')
        $InputProducer.Write($InputBytes)
        $InputProducer.Flush()
        $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
        Assert-Condition ((Invoke-CodexStopHook -InputStream $InputConsumer) -ceq '{}') 'open_input_inert_hook'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'http_attempt_before_input_eof'
        Assert-Condition ($Stopwatch.ElapsedMilliseconds -lt 3000) 'input_wait_bounded'
    }
    finally {
        $InputProducer.Dispose()
        $InputConsumer.Dispose()
    }

    $script:FixtureHandler = [NotificationFixtureHandler]::new()
    $DisposedInput = [IO.MemoryStream]::new()
    $DisposedInput.Dispose()
    Assert-Condition ((Invoke-CodexStopHook -InputStream $DisposedInput) -ceq '{}') 'input_start_failure_inert'
    Assert-Condition ($FixtureHandler.Calls -eq 1) 'input_failure_does_not_skip_http'

    foreach ($StatusCode in 200..299) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $script:FixtureHandler.StatusCode = $StatusCode
        Assert-Condition ((Invoke-TurnNotification) -ceq 'success') 'every_2xx_succeeds'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'one_attempt'
        Assert-Condition ($FixtureHandler.Disposed) 'client_disposed'
        Assert-Condition ($FixtureHandler.Body -cmatch '\ACodex turn finished \d{2}:\d{2}:\d{2}\z') 'fixed_body'
        Assert-Condition ($FixtureHandler.Uri -ceq 'https://ntfy.sh/offline-fixture-topic') 'fixed_destination'
        Assert-Condition ($FixtureHandler.Method -ceq 'POST') 'post_method'
        Assert-Condition ($FixtureHandler.MediaType -ceq 'text/plain') 'plain_text'
        Assert-Condition ($FixtureHandler.HeaderCount -eq 0) 'no_title_or_credentials'
    }

    foreach ($SourceCase in @(
            @{ Source = 'Codex'; Pattern = '\ACodex turn finished \d{2}:\d{2}:\d{2}\z' },
            @{ Source = 'Claude'; Pattern = '\AClaude turn finished \d{2}:\d{2}:\d{2}\z' })) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        Assert-Condition ((Invoke-TurnNotification -Source $SourceCase.Source) -ceq 'success') 'source_success'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'source_one_attempt'
        Assert-Condition ($FixtureHandler.Body -cmatch $SourceCase.Pattern) 'source_fixed_body'
    }

    $FirstBody = $null
    $Attempts = 0
    do {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $null = Invoke-TurnNotification
        if ($null -eq $FirstBody) { $FirstBody = $FixtureHandler.Body }
        $Attempts++
        if ($FixtureHandler.Body -ceq $FirstBody) { Start-Sleep -Milliseconds 250 }
    } while ($FixtureHandler.Body -ceq $FirstBody -and $Attempts -lt 12)
    Assert-Condition ($FixtureHandler.Body -cne $FirstBody) 'body_changes_with_send_time'

    $IdleInputs = @(
        $null,
        '',
        'not json',
        '[]',
        '{"stop_hook_active":false}',
        '{"background_tasks":[],"session_crons":[]}',
        '{"background_tasks":[]}',
        '{"background_tasks":null,"session_crons":"unexpected"}'
    )
    foreach ($IdleInput in $IdleInputs) {
        Assert-Condition (Test-ClaudeTurnIdle -InputText $IdleInput) 'claude_idle_or_unknown_notifies'
    }
    $BusyInputs = @(
        '{"background_tasks":[{"id":"fixture","type":"subagent","status":"running"}],"session_crons":[]}',
        '{"background_tasks":[],"session_crons":[{"id":"fixture","recurring":false}]}',
        '{"background_tasks":[{"id":"fixture","type":"shell"}]}'
    )
    foreach ($BusyInput in $BusyInputs) {
        Assert-Condition (-not (Test-ClaudeTurnIdle -InputText $BusyInput)) 'claude_background_work_suppresses'
    }

    foreach ($ClaudeCase in @(
            @{ Input = '{"last_assistant_message":"private-answer","background_tasks":[],"session_crons":[]}'; Calls = 1 },
            @{ Input = '{"last_assistant_message":"private-answer","background_tasks":[{"id":"fixture"}],"session_crons":[]}'; Calls = 0 })) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $ClaudeInput = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($ClaudeCase.Input))
        Assert-Condition ((Invoke-ClaudeStopHook -InputStream $ClaudeInput) -ceq '{}') 'claude_inert_hook'
        Assert-Condition ($FixtureHandler.Calls -eq $ClaudeCase.Calls) 'claude_sends_only_when_idle'
        if ($ClaudeCase.Calls -eq 1) {
            Assert-Condition ($FixtureHandler.Body -cmatch '\AClaude turn finished \d{2}:\d{2}:\d{2}\z') 'claude_fixed_body'
        }
    }

    $OversizedInput = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('{"background_tasks":[{"id":"fixture"}]}'))
    Assert-Condition ($null -eq (Read-HookInput -InputStream $OversizedInput -MaximumBytes 8)) 'claude_oversized_input_unparsed'
    Assert-Condition ($OversizedInput.Position -eq $OversizedInput.Length) 'claude_oversized_input_drained'
    $OpenProducer = [IO.Pipes.AnonymousPipeServerStream]::new([IO.Pipes.PipeDirection]::Out)
    $OpenConsumer = [IO.Pipes.AnonymousPipeClientStream]::new(
        [IO.Pipes.PipeDirection]::In, $OpenProducer.ClientSafePipeHandle
    )
    try {
        $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
        Assert-Condition ($null -eq (Read-HookInput -InputStream $OpenConsumer -TimeoutMilliseconds 200)) 'claude_open_input_unknown'
        Assert-Condition ($Stopwatch.ElapsedMilliseconds -lt 3000) 'claude_input_wait_bounded'
    }
    finally {
        $OpenProducer.Dispose()
        $OpenConsumer.Dispose()
    }

    foreach ($RejectedSource in @('claude', 'CODEX', 'Other', '')) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $Rejected = $false
        try { $null = Invoke-TurnNotification -Source $RejectedSource }
        catch { $Rejected = $true }
        Assert-Condition $Rejected 'source_limited_to_fixed_values'
        Assert-Condition ($FixtureHandler.Calls -eq 0) 'rejected_source_no_http'
    }

    foreach ($StatusCode in @(199, 300, 301, 302, 307, 308, 400, 401, 403, 429, 500, 599)) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $script:FixtureHandler.StatusCode = $StatusCode
        Assert-Condition ((Invoke-TurnNotification) -ceq 'http_failure') 'non_2xx_fails'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'non_2xx_no_retry'
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $script:FixtureHandler.StatusCode = $StatusCode
        Assert-Condition ((Invoke-CodexStopHook) -ceq '{}') 'http_failure_inert_hook'
    }

    foreach ($Mode in @('error', 'timeout')) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $script:FixtureHandler.Mode = $Mode
        $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
        Assert-Condition ((Invoke-TurnNotification) -ceq 'transport_failure') 'transport_error_sanitized'
        Assert-Condition ($Stopwatch.ElapsedMilliseconds -lt 5000) 'deadline_bounded'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'transport_no_retry'
        Assert-Condition ($FixtureHandler.Disposed) 'failure_disposed'
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $script:FixtureHandler.Mode = $Mode
        Assert-Condition ((Invoke-CodexStopHook) -ceq '{}') 'transport_failure_inert_hook'
    }

    foreach ($Topic in @($null, '', ' ', 'bad/topic', 'bad?topic', "bad`ntopic", ('a' * 65))) {
        [Environment]::SetEnvironmentVariable('NTFY_TOPIC', $Topic, 'Process')
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $Expected = if ([string]::IsNullOrWhiteSpace($Topic)) { 'topic_missing' } else { 'topic_invalid' }
        Assert-Condition ((Invoke-TurnNotification) -ceq $Expected) 'topic_rejected'
        Assert-Condition ((Invoke-CodexStopHook) -ceq '{}') 'topic_failure_inert_hook'
        Assert-Condition ($FixtureHandler.Calls -eq 0) 'invalid_topic_no_http'
    }

    $env:NTFY_TOPIC = 'offline-fixture-topic'
    foreach ($UnusedHome in @((Join-Path $FixtureRoot 'home-one'), (Join-Path $FixtureRoot 'home-two'))) {
        $env:CODEX_HOME = $UnusedHome
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        Assert-Condition ((Invoke-CodexStopHook) -ceq '{}') 'no_home_or_reservation_dependency'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'every_invocation_sends'
        Assert-Condition (-not (Test-Path -LiteralPath $UnusedHome)) 'no_state_created'
    }

    function New-NotificationHttpClient {
        <#
        .SYNOPSIS
        Simulates a client initialization failure containing sensitive text.
        #>
        throw 'private-topic private-path private-credential'
    }
    Assert-Condition ((Invoke-CodexStopHook) -ceq '{}') 'initialization_failure_silent'
    ${function:New-NotificationHttpClient} = $ProductionClientFactory

    Invoke-HookProcess -Topic $null -InputCase normal
    Invoke-HookProcess -Topic $null -InputCase open
    Invoke-HookProcess -Topic $null -InputCase large
    Invoke-HookProcess -Topic 'invalid/topic'
    Invoke-HookProcess -Topic $null -ScriptPath $ClaudeHookPath
    Invoke-HookProcess -Topic $null -InputCase large -ScriptPath $ClaudeHookPath

    $Example = Get-Content (Join-Path $SkillDirectory 'references/codex-hooks.json') -Raw | ConvertFrom-Json
    Assert-Condition (@($Example.hooks.PSObject.Properties).Count -eq 1) 'stop_only_registration'
    Assert-Condition ($Example.hooks.Stop[0].hooks[0].timeout -eq 20) 'outer_deadline'
    $ClaudeExample = Get-Content (Join-Path $SkillDirectory 'references/claude-settings.json') -Raw | ConvertFrom-Json
    Assert-Condition (@($ClaudeExample.hooks.PSObject.Properties).Count -eq 1) 'claude_stop_only_registration'
    Assert-Condition (@($ClaudeExample.hooks.Stop).Count -eq 1 -and @($ClaudeExample.hooks.Stop[0].hooks).Count -eq 1) 'claude_single_handler'
    Assert-Condition ($ClaudeExample.hooks.Stop[0].hooks[0].timeout -eq 20) 'claude_outer_deadline'
    Assert-Condition ($ClaudeExample.hooks.Stop[0].hooks[0].command.EndsWith('scripts/claude-stop-hook.ps1"')) 'claude_entry_point'
    $HookSourceText = Get-Content $HookPath -Raw
    Assert-Condition ($HookSourceText.Contains('$Handler.AllowAutoRedirect = $false')) 'redirects_disabled'
    Assert-Condition ($HookSourceText.Contains('$Handler.UseCookies = $false')) 'cookies_disabled'
    Assert-Condition ($HookSourceText.Contains('ResponseHeadersRead')) 'no_response_body_read'
    foreach ($Name in $SandboxEnvironment.Keys) {
        Assert-Condition ([Environment]::GetEnvironmentVariable($Name, 'Process') -ceq $SandboxEnvironment[$Name]) 'sandbox_environment_preserved'
    }
    [Console]::Out.WriteLine('task-complete-notify tests: PASS (offline HTTP; no publish)')
}
finally {
    [Environment]::SetEnvironmentVariable('NTFY_TOPIC', $OriginalTopic, 'Process')
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $OriginalCodexHome, 'Process')
}

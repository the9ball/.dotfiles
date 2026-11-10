#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SkillDirectory = Split-Path -Parent $PSScriptRoot
$HookPath = Join-Path $SkillDirectory 'scripts/codex-stop-hook.ps1'
$OriginalTopic = [Environment]::GetEnvironmentVariable('NTFY_TOPIC', 'Process')
$OriginalCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
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
    Runs the real entry point with a non-deliverable topic and hostile stdin.
    .PARAMETER Topic
    An unset or deliberately invalid topic that cannot initiate HTTP.
    .OUTPUTS
    None. Asserts bounded execution, exit 0, empty errors, and inert JSON.
    #>
    param([AllowNull()][string]$Topic)
    $StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = (Get-Process -Id $PID).Path
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardInput = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    foreach ($Argument in @('-NoProfile', '-NonInteractive', '-File', $HookPath)) {
        $StartInfo.ArgumentList.Add($Argument)
    }
    $StartInfo.Environment.Remove('NTFY_TOPIC') | Out-Null
    if ($null -ne $Topic) { $StartInfo.Environment['NTFY_TOPIC'] = $Topic }
    $StartInfo.Environment['CODEX_HOME'] = Join-Path ([IO.Path]::GetTempPath()) 'ntfy-no-state-required'
    $Process = [Diagnostics.Process]::new()
    try {
        $Process.StartInfo = $StartInfo
        Assert-Condition ($Process.Start()) 'process_start'
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.StandardInput.Write('{"last_assistant_message":"private-answer","transcript_path":"private-path","stop_hook_active":true}')
        $Process.StandardInput.Close()
        if (-not $Process.WaitForExit(5000)) {
            $Process.Kill($true)
            throw 'process_timeout'
        }
        Assert-Condition ($Process.ExitCode -eq 0) 'process_exit_zero'
        Assert-Condition ($OutputTask.GetAwaiter().GetResult().Trim() -ceq '{}') 'process_inert_json'
        Assert-Condition ($ErrorTask.GetAwaiter().GetResult() -ceq '') 'process_no_errors'
    }
    finally { $Process.Dispose() }
}

try {
    $env:NTFY_TOPIC = 'offline-fixture-topic'
    $env:CODEX_HOME = 'unused-codex-home'
    . $HookPath
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

    foreach ($StatusCode in 200..299) {
        $script:FixtureHandler = [NotificationFixtureHandler]::new()
        $script:FixtureHandler.StatusCode = $StatusCode
        Assert-Condition ((Invoke-TurnNotification) -ceq 'success') 'every_2xx_succeeds'
        Assert-Condition ($FixtureHandler.Calls -eq 1) 'one_attempt'
        Assert-Condition ($FixtureHandler.Disposed) 'client_disposed'
        Assert-Condition ($FixtureHandler.Body -ceq 'Codex turn finished') 'fixed_body'
        Assert-Condition ($FixtureHandler.Uri -ceq 'https://ntfy.sh/offline-fixture-topic') 'fixed_destination'
        Assert-Condition ($FixtureHandler.Method -ceq 'POST') 'post_method'
        Assert-Condition ($FixtureHandler.MediaType -ceq 'text/plain') 'plain_text'
        Assert-Condition ($FixtureHandler.HeaderCount -eq 0) 'no_title_or_credentials'
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
    foreach ($UnusedHome in @('unused-codex-home', 'another-unused-home')) {
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

    Invoke-HookProcess -Topic $null
    Invoke-HookProcess -Topic 'invalid/topic'

    $Example = Get-Content (Join-Path $SkillDirectory 'references/codex-hooks.json') -Raw | ConvertFrom-Json
    Assert-Condition (@($Example.hooks.PSObject.Properties).Count -eq 1) 'stop_only_registration'
    Assert-Condition ($Example.hooks.Stop[0].hooks[0].timeout -eq 20) 'outer_deadline'
    $Source = Get-Content $HookPath -Raw
    Assert-Condition ($Source.Contains('$Handler.AllowAutoRedirect = $false')) 'redirects_disabled'
    Assert-Condition ($Source.Contains('$Handler.UseCookies = $false')) 'cookies_disabled'
    Assert-Condition ($Source.Contains('ResponseHeadersRead')) 'no_response_body_read'
    foreach ($Name in $SandboxEnvironment.Keys) {
        Assert-Condition ([Environment]::GetEnvironmentVariable($Name, 'Process') -ceq $SandboxEnvironment[$Name]) 'sandbox_environment_preserved'
    }
    [Console]::Out.WriteLine('task-complete-notify tests: PASS (offline HTTP; no publish)')
}
finally {
    [Environment]::SetEnvironmentVariable('NTFY_TOPIC', $OriginalTopic, 'Process')
    [Environment]::SetEnvironmentVariable('CODEX_HOME', $OriginalCodexHome, 'Process')
}

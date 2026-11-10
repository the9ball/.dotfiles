#requires -Version 7.4

[CmdletBinding()]
param()

function New-NotificationHttpClient {
    <#
    .SYNOPSIS
    Creates a client with a total request deadline and no redirects or cookies.
    .OUTPUTS
    System.Net.Http.HttpClient. The caller must dispose the client.
    #>
    $Handler = [Net.Http.HttpClientHandler]::new()
    $Handler.AllowAutoRedirect = $false
    $Handler.UseCookies = $false
    $Client = [Net.Http.HttpClient]::new($Handler)
    $Client.Timeout = [TimeSpan]::FromSeconds(10)
    return $Client
}

function Invoke-TurnNotification {
    <#
    .SYNOPSIS
    Publishes a fixed message once using only the process NTFY_TOPIC.
    .PARAMETER Source
    The agent whose turn finished. Only the two fixed messages can be produced;
    the Claude Code entry point passes Claude, and everything else uses Codex.
    .OUTPUTS
    System.String. A generic result without input, topic, URL, or response data.
    .NOTES
    No hook input is parsed; no Codex home, transcript, or reservation is read.
    All HTTP failures are contained; no retry is performed.
    #>
    param(
        [ValidateSet('Codex', 'Claude', IgnoreCase = $false)]
        [string]$Source = 'Codex'
    )
    $Client = $null
    $Request = $null
    $Response = $null
    try {
        $Topic = [Environment]::GetEnvironmentVariable('NTFY_TOPIC', 'Process')
        if ([string]::IsNullOrWhiteSpace($Topic)) {
            return 'topic_missing'
        }
        if ($Topic -cnotmatch '\A[-_A-Za-z0-9]{1,64}\z') {
            return 'topic_invalid'
        }

        $Client = New-NotificationHttpClient
        $Request = [Net.Http.HttpRequestMessage]::new(
            [Net.Http.HttpMethod]::Post, "https://ntfy.sh/$Topic"
        )
        $Request.Content = [Net.Http.StringContent]::new(
            "$Source turn finished", [Text.Encoding]::UTF8, 'text/plain'
        )
        # Stop after headers: response bodies are unnecessary and may contain secrets.
        $Response = $Client.SendAsync(
            $Request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        if ($Response.IsSuccessStatusCode) {
            return 'success'
        }
        return 'http_failure'
    }
    catch {
        return 'transport_failure'
    }
    finally {
        if ($null -ne $Response) { $Response.Dispose() }
        if ($null -ne $Request) { $Request.Dispose() }
        if ($null -ne $Client) { $Client.Dispose() }
    }
}

function Invoke-CodexStopHook {
    <#
    .SYNOPSIS
    Publishes independently of stdin completion and emits an inert Stop response.
    .PARAMETER InputStream
    Optional caller-owned input to discard concurrently. Omit for in-process calls.
    .OUTPUTS
    System.String. An empty JSON object with no continuation decision.
    .NOTES
    After delivery, input draining gets at most one additional second. The entry
    process closes its standard input on exit, including a still-pending read.
    #>
    param([AllowNull()][IO.Stream]$InputStream)

    $InputDrainTask = $null
    try {
        if ($null -ne $InputStream) {
            # Keep the producer's pipe flowing without making delivery wait for EOF.
            $InputDrainTask = $InputStream.CopyToAsync([IO.Stream]::Null)
        }
    }
    catch {
        # Input failures must not prevent the independent delivery attempt.
    }

    try {
        $null = Invoke-TurnNotification
    }
    catch {
        # A notification must never request continuation or change the turn result.
    }

    if ($null -ne $InputDrainTask) {
        try { [void]$InputDrainTask.Wait(1000) }
        catch {
            # Drain faults are deliberately contained just like HTTP failures.
        }
    }
    return '{}'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $InputStream = if ([Console]::IsInputRedirected) { [Console]::OpenStandardInput() } else { $null }
        $Response = Invoke-CodexStopHook -InputStream $InputStream
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

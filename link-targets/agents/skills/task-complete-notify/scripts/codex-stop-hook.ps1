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
    .OUTPUTS
    System.String. A generic result without input, topic, URL, or response data.
    .NOTES
    No hook input is parsed; no Codex home, transcript, or reservation is read.
    All HTTP failures are contained; no retry is performed.
    #>
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
            'Codex turn finished', [Text.Encoding]::UTF8, 'text/plain'
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
    Emits an inert Stop response even when notification delivery fails.
    .OUTPUTS
    System.String. An empty JSON object with no continuation decision.
    #>
    try {
        if ([Console]::IsInputRedirected) {
            # Drain without parsing or retaining data so the host's pipe writer can finish.
            $InputStream = [Console]::OpenStandardInput()
            try { $InputStream.CopyTo([IO.Stream]::Null) }
            finally { $InputStream.Dispose() }
        }
        $null = Invoke-TurnNotification
    }
    catch {
        # A notification must never request continuation or change the turn result.
    }
    return '{}'
}

if ($MyInvocation.InvocationName -ne '.') {
    [Console]::Out.WriteLine((Invoke-CodexStopHook))
    exit 0
}

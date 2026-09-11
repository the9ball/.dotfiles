#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Assert-NotificationMessage {
    <#
    .SYNOPSIS
    Validates the literal message that will be sent to ntfy.

    .DESCRIPTION
    Enforces the one-line, control-character, Unicode, and UTF-8 byte-length
    contract without including the message value in any exception text.

    .PARAMETER Message
    The literal message to validate.

    .OUTPUTS
    System.String. Returns the unchanged message after validation.

    .NOTES
    The caller is responsible for keeping the returned value out of logs and
    user-visible diagnostics.
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

function Get-NtfyTopic {
    <#
    .SYNOPSIS
    Reads and validates the ntfy topic from the process environment.

    .OUTPUTS
    System.String. Returns a validated topic or throws a generic topic error.

    .NOTES
    The topic value is never included in output, state, or exception text.
    #>
    $Topic = [Environment]::GetEnvironmentVariable('NTFY_TOPIC', 'Process')
    if ([string]::IsNullOrWhiteSpace($Topic)) {
        throw 'topic_missing'
    }

    $Topic = $Topic.Trim()
    if ($Topic -notmatch '^[-_A-Za-z0-9]{1,64}$') {
        throw 'topic_invalid'
    }

    return $Topic
}

function Invoke-NtfyPublish {
    <#
    .SYNOPSIS
    Sends one message-body-only request to the fixed ntfy server.

    .PARAMETER Message
    The already validated message body.

    .OUTPUTS
    PSCustomObject. Returns an outcome with only a success flag and a generic
    reason; no topic, URL, response body, or message is returned.

    .NOTES
    A final HTTP 200-299 is the only successful result. Redirects and all
    transport failures are terminal for the caller's one-shot generation.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    try {
        $ValidatedMessage = Assert-NotificationMessage -Message $Message
        $Topic = Get-NtfyTopic
        $EncodedTopic = [Uri]::EscapeDataString($Topic)
        $Uri = "https://ntfy.sh/$EncodedTopic"

        $Response = Invoke-WebRequest `
            -Method Post `
            -Uri $Uri `
            -ContentType 'text/plain; charset=utf-8' `
            -Body $ValidatedMessage `
            -ConnectionTimeoutSeconds 10 `
            -OperationTimeoutSeconds 20 `
            -MaximumRedirection 0 `
            -SkipHttpErrorCheck

        $StatusCode = [int]$Response.StatusCode
        if ($StatusCode -ge 200 -and $StatusCode -le 299) {
            return [pscustomobject]@{
                Ok = $true
                Reason = 'success'
            }
        }

        return [pscustomobject]@{
            Ok = $false
            Reason = 'http_failure'
        }
    }
    catch {
        $Reason = switch -Regex ($_.Exception.Message) {
            '^topic_missing$' { 'topic_missing'; break }
            '^topic_invalid$' { 'topic_invalid'; break }
            '^message_invalid$' { 'message_invalid'; break }
            default { 'transport_failure' }
        }

        return [pscustomobject]@{
            Ok = $false
            Reason = $Reason
        }
    }
}

function Read-NotificationRequest {
    <#
    .SYNOPSIS
    Reads the helper-to-notifier JSON envelope from standard input.

    .OUTPUTS
    PSCustomObject. Returns a request containing only the validated message.

    .NOTES
    Invalid input is reported with a generic error and never echoed.
    #>
    $InputStream = $null
    $InputReader = $null
    try {
        $InputStream = [Console]::OpenStandardInput()
        $InputReader = [IO.StreamReader]::new(
            $InputStream,
            [Text.UTF8Encoding]::new($false),
            $true
        )
        $RequestText = $InputReader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($RequestText)) {
            throw 'request_invalid'
        }

        try {
            $Request = $RequestText | ConvertFrom-Json
        }
        catch {
            throw 'request_invalid'
        }

        if (-not $Request.PSObject.Properties.Name.Contains('message')) {
            throw 'request_invalid'
        }

        $Message = [string]$Request.message
        [void](Assert-NotificationMessage -Message $Message)

        return [pscustomobject]@{
            Message = $Message
        }
    }
    finally {
        if ($null -ne $InputReader) {
            $InputReader.Dispose()
        }
        if ($null -ne $InputStream) {
            $InputStream.Dispose()
        }
    }
}

try {
    $NotificationRequest = Read-NotificationRequest
    $NotificationResult = Invoke-NtfyPublish -Message $NotificationRequest.Message
}
catch {
    $NotificationResult = [pscustomobject]@{
        Ok = $false
        Reason = 'request_invalid'
    }
}

[Console]::Out.WriteLine(($NotificationResult | ConvertTo-Json -Compress))

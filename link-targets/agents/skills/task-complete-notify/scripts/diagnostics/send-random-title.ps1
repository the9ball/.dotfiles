#requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateRange(1, 256)]
    [int]$Length = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RandomText {
<#
.SYNOPSIS
Generates a random ASCII string with the requested length.

.DESCRIPTION
Uses a cryptographically strong random byte source and a header-safe alphabet
so the generated value can be sent as an ntfy title without newline or control
characters.

.PARAMETER Length
Number of characters to generate.

.OUTPUTS
System.String
#>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 256)]
        [int]$Length
    )

    $Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $RandomBytes = [byte[]]::new($Length)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($RandomBytes)

    $Characters = [char[]]::new($Length)
    for ($Index = 0; $Index -lt $Length; $Index++) {
        $Characters[$Index] = $Alphabet[$RandomBytes[$Index] % $Alphabet.Length]
    }

    return -join $Characters
}

function Get-NtfyTopicUri {
<#
.SYNOPSIS
Builds the fixed ntfy.sh topic URI from the NTFY_TOPIC value.

.DESCRIPTION
Trims surrounding whitespace, rejects line breaks, and URI-encodes the topic
as one path segment so environment input cannot alter the request target.

.PARAMETER Topic
Topic name read from the NTFY_TOPIC environment variable.

.OUTPUTS
System.Uri
#>
    [OutputType([Uri])]
    param(
        [Parameter(Mandatory)]
        [string]$Topic
    )

    if ($Topic -match '[\x00-\x1F\x7F]') {
        throw 'NTFY_TOPIC must not contain control characters.'
    }

    $TrimmedTopic = $Topic.Trim()
    if ([string]::IsNullOrWhiteSpace($TrimmedTopic)) {
        throw 'NTFY_TOPIC is empty.'
    }
    if ($TrimmedTopic -notmatch '^[-_A-Za-z0-9]{1,64}$') {
        throw 'NTFY_TOPIC must contain only ASCII letters, digits, hyphens, or underscores and be at most 64 characters.'
    }

    $EncodedTopic = [Uri]::EscapeDataString($TrimmedTopic)
    return [Uri]::new("https://ntfy.sh/$EncodedTopic")
}

function Send-NtfyNotification {
<#
.SYNOPSIS
Posts one notification and requires an HTTP 2xx response.

.DESCRIPTION
Sends the supplied message to the fixed ntfy.sh endpoint. The title is sent
through ntfy's X-Title header, and non-success HTTP responses are surfaced as
errors so a successful process start is not mistaken for delivery success.

.PARAMETER Uri
The ntfy topic URI.

.PARAMETER Title
Notification title.

.PARAMETER Message
Notification body.

.OUTPUTS
System.Object
#>
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [Uri]$Uri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    try {
        $Response = Invoke-WebRequest `
            -Uri $Uri `
            -Method Post `
            -Headers @{ 'X-Title' = $Title } `
            -Body $Message `
            -ContentType 'text/plain; charset=utf-8' `
            -ConnectionTimeoutSeconds 30 `
            -OperationTimeoutSeconds 30 `
            -MaximumRedirection 0 `
            -SkipHttpErrorCheck
    }
    catch {
        throw 'ntfy request failed before receiving an HTTP response.'
    }

    $StatusCode = [int]$Response.StatusCode
    if ($StatusCode -lt 200 -or $StatusCode -gt 299) {
        throw "ntfy returned HTTP $StatusCode."
    }

    return $Response
}

$Topic = [Environment]::GetEnvironmentVariable(
    'NTFY_TOPIC',
    [EnvironmentVariableTarget]::Process
)
if ([string]::IsNullOrWhiteSpace($Topic)) {
    throw 'Set env:NTFY_TOPIC before running this script.'
}

$RandomText = Get-RandomText -Length $Length
$Response = Send-NtfyNotification `
    -Uri (Get-NtfyTopicUri -Topic $Topic) `
    -Title $RandomText `
    -Message 'task-complete-notify: fixed message / variable title'

[Console]::Out.WriteLine('Sent title-variable ntfy test.')
[Console]::Out.WriteLine("Random title ($Length chars): $RandomText")
[Console]::Out.WriteLine("HTTP status: $([int]$Response.StatusCode)")

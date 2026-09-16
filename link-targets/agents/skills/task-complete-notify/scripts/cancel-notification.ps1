#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Thread
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-WindowsHelper {
    <#
    .SYNOPSIS
    Sends one sanitized cancel request to the Windows helper through standard input.

    .PARAMETER RequestJson
    The JSON envelope containing the explicit target thread.

    .OUTPUTS
    System.String. Returns the helper's sanitized JSON result, or an empty
    string when the helper could not be started or returned unusable output.

    .NOTES
    The target is passed through standard input and is never placed in a
    diagnostic message or an interpolated command-line argument.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RequestJson
    )

    $HelperPath = Join-Path $ScriptDirectory 'windows-helper.ps1'
    $PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'

    if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        return ''
    }

    $Process = $null
    try {
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
        [void]$StartInfo.ArgumentList.Add($HelperPath)

        $Process = [Diagnostics.Process]::new()
        $Process.StartInfo = $StartInfo
        if (-not $Process.Start()) {
            return ''
        }

        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.StandardInput.Write($RequestJson)
        $Process.StandardInput.Close()
        if (-not $Process.WaitForExit(60000)) {
            try {
                $Process.Kill($true)
            }
            catch {
                # The process is already terminating; retain the failure result.
            }
            return ''
        }

        $HelperOutput = $OutputTask.GetAwaiter().GetResult()
        [void]$ErrorTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($HelperOutput)) {
            return ''
        }

        $SanitizedResult = $HelperOutput | ConvertFrom-Json
        return ($SanitizedResult | ConvertTo-Json -Compress)
    }
    catch {
        return ''
    }
    finally {
        if ($null -ne $Process) {
            $Process.Dispose()
        }
    }
}

function Write-CancelResult {
    <#
    .SYNOPSIS
    Emits a fixed-field cancel result without exposing state content.

    .PARAMETER ResultJson
    Sanitized JSON returned by the helper.

    .OUTPUTS
    None. A compact JSON result is written to standard output.
    #>
    param(
        [AllowEmptyString()]
        [string]$ResultJson
    )

    if ([string]::IsNullOrWhiteSpace($ResultJson)) {
        [Console]::Out.WriteLine('{"Ok":false,"Status":"helper_failure"}')
        return
    }

    try {
        $Result = $ResultJson | ConvertFrom-Json
        $Output = [ordered]@{
            Ok = [bool]$Result.Ok
            Status = [string]$Result.Status
        }
        [Console]::Out.WriteLine(($Output | ConvertTo-Json -Compress))
    }
    catch {
        [Console]::Out.WriteLine('{"Ok":false,"Status":"helper_failure"}')
    }
}

$Envelope = [ordered]@{
    operation = 'cancel'
    thread = $Thread
}

$ResultJson = Invoke-WindowsHelper -RequestJson ($Envelope | ConvertTo-Json -Compress)
Write-CancelResult -ResultJson $ResultJson

try {
    $ResultObject = $ResultJson | ConvertFrom-Json
    if ($ResultObject.Ok -ne $true) {
        exit 1
    }
}
catch {
    exit 1
}

exit 0

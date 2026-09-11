#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-JsonProperty {
    <#
    .SYNOPSIS
    Reads one optional property from a JSON-derived object.

    .PARAMETER InputObject
    The parsed hook object.

    .PARAMETER Name
    The exact property name to read.

    .OUTPUTS
    System.Object. Returns the property value or null when absent.
    #>
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }

    return $Property.Value
}

function Invoke-WindowsHelper {
    <#
    .SYNOPSIS
    Sends a minimal Stop envelope to the Windows state helper via stdin.

    .PARAMETER RequestJson
    The JSON envelope containing only safe hook identity fields.

    .OUTPUTS
    None. Helper output and errors are intentionally discarded so the hook
    cannot echo a message, topic, transcript content, or response body.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RequestJson
    )

    $HelperPath = Join-Path $ScriptDirectory 'windows-helper.ps1'
    $PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'

    if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        return
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
            return
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
                # The process is already terminating; keep the best-effort hook.
            }
            return
        }

        [void]$OutputTask.GetAwaiter().GetResult()
        [void]$ErrorTask.GetAwaiter().GetResult()
    }
    catch {
        # Stop hooks are best effort; a failed helper must not alter the turn.
    }
    finally {
        if ($null -ne $Process) {
            $Process.Dispose()
        }
    }
}

$HookInput = $null
try {
    $HookText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($HookText)) {
        exit 0
    }

    $HookInput = $HookText | ConvertFrom-Json
}
catch {
    exit 0
}

$StopHookActive = Get-JsonProperty -InputObject $HookInput -Name 'stop_hook_active'
$StopHookActiveIsBoolean = $StopHookActive -is [bool]
if (-not $StopHookActiveIsBoolean) {
    exit 0
}

$SafeHook = [ordered]@{
    hook_event_name = Get-JsonProperty -InputObject $HookInput -Name 'hook_event_name'
    session_id = Get-JsonProperty -InputObject $HookInput -Name 'session_id'
    transcript_path = Get-JsonProperty -InputObject $HookInput -Name 'transcript_path'
    turn_id = Get-JsonProperty -InputObject $HookInput -Name 'turn_id'
    stop_hook_active = $StopHookActive
}

$Envelope = [ordered]@{
    operation = 'stop'
    hook = $SafeHook
}

Invoke-WindowsHelper -RequestJson ($Envelope | ConvertTo-Json -Compress)
exit 0

#requires -Version 7.5
<# .SYNOPSIS Runs Docker using one explicitly selected TPM PoC deployment, without changing the parent environment. #>
[CmdletBinding(PositionalBinding=$false)]
param([Parameter(Mandatory)][string]$DeploymentRoot, [string]$DockerArgumentsBase64, [switch]$RequireReady, [switch]$MetadataOnly, [Parameter(ValueFromRemainingArguments)][string[]]$DockerArguments)
$ErrorActionPreference = 'Stop'
function Get-LauncherEnvironmentState {
    <# .SYNOPSIS Reads membership and the exact string of one permitted process routing variable without logging its value. #>
    param([string] $Name)
    if ($Name -notin @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')) { throw 'Unexpected routing variable.' }
    $itemPath = 'Env:' + $Name
    $exists = Microsoft.PowerShell.Management\Test-Path -LiteralPath $itemPath
    $value = if ($exists) { [string](Microsoft.PowerShell.Management\Get-Item -LiteralPath $itemPath -ErrorAction Stop).Value } else { $null }
    return [pscustomobject]@{ Name=$Name; Exists=[bool]$exists; Value=$value }
}

function Set-LauncherEnvironmentState {
    <# .SYNOPSIS Restores exact process-only presence and string state, explicitly deleting absent keys and verifying the result. #>
    param([pscustomobject] $State)
    if ($null -eq $State -or $State.Exists -isnot [bool] -or ($State.Exists -and $State.Value -isnot [string])) { throw 'Invalid routing state.' }
    $current = Get-LauncherEnvironmentState -Name $State.Name
    $itemPath = 'Env:' + $State.Name
    if ($State.Exists) {
        Microsoft.PowerShell.Management\Set-Item -LiteralPath $itemPath -Value $State.Value -ErrorAction Stop
    } elseif ($current.Exists) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $itemPath -ErrorAction Stop
    }
    $after = Get-LauncherEnvironmentState -Name $State.Name
    if ($after.Exists -ne $State.Exists -or ($State.Exists -and -not [string]::Equals($after.Value, $State.Value, [StringComparison]::Ordinal))) {
        throw 'Routing state restoration could not be verified.'
    }
}

function Read-LauncherDeployment {
    <# .SYNOPSIS Validates strict managed routing or legacy child-only normalization, restoring all process state before returning a configuration.
       .NOTES Exact Env-provider empty strings require PowerShell 7.5 or newer. #>
    param([string] $Reader, [string] $Deployment, [bool] $Strict)
    if ($PSVersionTable.PSVersion -lt [version]'7.5') { throw 'PowerShell 7.5 or newer is required for exact routing restoration.' }
    $normalizeLegacy = $false
    if (-not $Strict) {
        . $Reader -DefinitionsOnly
        Assert-TpmDeploymentPath -Path $Deployment
        $settingsPath = Join-Path $Deployment 'settings.json'
        Assert-TpmDeploymentPath -Path $settingsPath
        $legacySettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $normalizeLegacy = $legacySettings.HelperVersion -eq '0.4.0'
    }
    $saved = @()
    $exitVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $previousExit = [pscustomobject]@{ Exists=($null -ne $exitVariable); Value=if ($null -ne $exitVariable) { $exitVariable.Value } else { $null } }
    $validatedConfiguration = $null
    try {
        if ($normalizeLegacy) {
            # Capture every key before mutation so partial normalization can restore the complete original state.
            foreach ($variableName in @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')) {
                $saved += Get-LauncherEnvironmentState -Name $variableName
            }
            foreach ($original in $saved) {
                Set-LauncherEnvironmentState -State ([pscustomobject]@{ Name=$original.Name; Exists=$false; Value=$null })
            }
        }
        $readerErrors = @()
        $configuration = $null
        $global:LASTEXITCODE = 0
        . $Reader -DeploymentRoot $Deployment -NoOutput -RequireReady:$Strict -ErrorAction Stop -ErrorVariable +readerErrors
        $validationSucceeded = $?
        if (-not $validationSucceeded -or $readerErrors.Count -or $global:LASTEXITCODE -ne 0 -or $null -eq $configuration) {
            throw 'Deployment validation did not complete successfully.'
        }
        if ($normalizeLegacy -and $configuration.HelperVersion -ne '0.4.0') { throw 'Deployment version changed during validation.' }
        $validatedConfiguration = $configuration
    } finally {
        $restoreFailed = $false
        # Each rollback is attempted independently; any incomplete restoration blocks metadata and process launch.
        foreach ($original in $saved) {
            try { Set-LauncherEnvironmentState -State $original } catch { $restoreFailed = $true }
        }
        try {
            if ($previousExit.Exists) { $global:LASTEXITCODE = $previousExit.Value }
            elseif (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) {
                Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction Stop
            }
            $exitAfter = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            if (($null -ne $exitAfter) -ne $previousExit.Exists -or ($previousExit.Exists -and $exitAfter.Value -cne $previousExit.Value)) {
                throw 'Exit state restoration failed.'
            }
        } catch { $restoreFailed = $true }
        if ($restoreFailed) { throw 'Process routing restoration failed; no command was started.' }
    }
    return $validatedConfiguration
}

try {
    if ($PSBoundParameters.ContainsKey('DockerArgumentsBase64')) {
        if ($DockerArguments) { throw 'Ambiguous arguments.' }
        $DockerArguments = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($DockerArgumentsBase64)) | ConvertFrom-Json -NoEnumerate
    }
    if (-not $IsWindows -or ((-not $MetadataOnly) -and -not $DockerArguments) -or ($DockerArguments -and $DockerArguments[0].StartsWith('-'))) { throw 'Command required.' }
    if ($MetadataOnly -and ($DockerArguments -or $PSBoundParameters.ContainsKey('DockerArgumentsBase64'))) { throw 'Metadata request must not include a command.' }
    if ($env:DOCKER_TLS_VERIFY -or $env:DOCKER_CERT_PATH) { throw 'Unsupported inherited TLS settings.' }
    foreach ($argument in $DockerArguments) {
        if ($argument -match '^--(?:host|context|config)(?:=|$)' -or $argument -match '^-[Hc]' -or $argument -match '^-[^-].{1,}') {
            throw 'Endpoint/config overrides and joined short options are not accepted.'
        }
    }
    if (-not [IO.Path]::IsPathFullyQualified($DeploymentRoot)) { throw 'Absolute deployment required.' }
    $deployment = [IO.Path]::GetFullPath($DeploymentRoot)
    $settings = Read-LauncherDeployment -Reader (Join-Path $PSScriptRoot 'Get-TpmDockerEnvironment.ps1') -Deployment $deployment -Strict:($RequireReady -or $env:DOCKER_SSH_MANAGED -eq '1')
    if ($MetadataOnly) {
        # Emit data only after validation and restoration completed; never expose partial metadata on failure.
        $fields = @($settings.DockerExecutable, (Join-Path $deployment ('bin/' + $settings.HelperVersion)),
            (Join-Path $deployment 'docker-config'), (Join-Path $deployment 'store'), $settings.EngineEndpoint)
        if (@($fields | Where-Object { -not $_ -or $_ -match '[\r\n]' }).Count) { throw 'Invalid validated metadata.' }
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($fields -join "`n"))
        $stream = [Console]::OpenStandardOutput()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        exit 0
    }
    $binaryDirectory = Join-Path $deployment ('bin/' + $settings.HelperVersion)
    $start = [Diagnostics.ProcessStartInfo]::new($settings.DockerExecutable)
    $start.UseShellExecute = $false
    $start.Environment.Remove('DOCKER_CONTEXT') | Out-Null
    $start.Environment.Remove('DOCKER_HOST') | Out-Null
    $start.Environment.Remove('DOCKER_AUTH_CONFIG') | Out-Null
    $start.Environment['DOCKER_CONFIG'] = Join-Path $deployment 'docker-config'
    $start.Environment['DOCKER_SSH_HELPER_ROOT'] = Join-Path $deployment 'store'
    $start.Environment['PATH'] = $binaryDirectory + [IO.Path]::PathSeparator + $env:PATH
    $start.ArgumentList.Add('--host')
    $start.ArgumentList.Add($settings.EngineEndpoint)
    $start.ArgumentList.Add('--config')
    $start.ArgumentList.Add((Join-Path $deployment 'docker-config'))
    foreach ($argument in $DockerArguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try { $process.WaitForExit(); exit $process.ExitCode } finally { $process.Dispose() }
} catch {
    # Never echo arguments, settings content, protocol payloads, or exception text.
    [Console]::Error.WriteLine('Docker SSH launcher failed; check dedicated deployment and supported routing options.')
    exit 1
}

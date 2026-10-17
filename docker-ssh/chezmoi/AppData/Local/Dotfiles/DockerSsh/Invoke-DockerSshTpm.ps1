<# .SYNOPSIS Runs Docker using one explicitly selected TPM PoC deployment, without changing the parent environment. #>
param([Parameter(Mandatory)][string]$DeploymentRoot, [Parameter(ValueFromRemainingArguments)][string[]]$DockerArguments)
$ErrorActionPreference = 'Stop'
try {
    if (-not $IsWindows -or -not $DockerArguments -or $DockerArguments[0].StartsWith('-')) { throw 'Command required.' }
    if ($env:DOCKER_TLS_VERIFY -or $env:DOCKER_CERT_PATH) { throw 'Unsupported inherited TLS settings.' }
    foreach ($argument in $DockerArguments) {
        if ($argument -match '^--(?:host|context|config)(?:=|$)' -or $argument -match '^-[Hc]' -or $argument -match '^-[^-].{1,}') {
            throw 'Endpoint/config overrides and joined short options are not accepted.'
        }
    }
    if (-not [IO.Path]::IsPathFullyQualified($DeploymentRoot)) { throw 'Absolute deployment required.' }
    $deployment = [IO.Path]::GetFullPath($DeploymentRoot)
    . (Join-Path $PSScriptRoot 'Get-TpmDockerEnvironment.ps1') -DeploymentRoot $deployment -NoOutput
    $settings = $configuration
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

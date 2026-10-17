<# .SYNOPSIS
Inspect local build, runtime, or test prerequisites without installing or initializing anything.
#>
param(
    [ValidateSet('Build', 'Run', 'Test')][string]$Purpose = 'Run',
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Get-BoundedToolOutput {
    <# .SYNOPSIS
    Read non-secret version metadata with a ten-second deadline and reject excessive output.
    #>
    param([string]$Executable, [string[]]$Arguments)
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.Environment['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
    $start.Environment['DOTNET_SKIP_FIRST_TIME_EXPERIENCE'] = '1'
    $start.Environment['DOTNET_NOLOGO'] = '1'
    $start.WorkingDirectory = Split-Path -Parent $PSScriptRoot
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill($true)
            $process.WaitForExit()
            return $null
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorOutput = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or $output.Length + $errorOutput.Length -gt 65536) { return $null }
        return $output.Trim()
    } finally { $process.Dispose() }
}

function Get-ToolMetadata {
    <# .SYNOPSIS
    Resolve an installed application and return only version metadata, never install it.
    #>
    param([string]$Name, [string[]]$Arguments)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return $null }
    try { return Get-BoundedToolOutput -Executable $command.Source -Arguments $Arguments }
    catch { return $null }
}

$checks = [Collections.Generic.List[object]]::new()
$checks.Add([ordered]@{ Name = 'Windows'; Passed = [bool]$IsWindows })
$checks.Add([ordered]@{ Name = 'PowerShell>=7.4'; Passed = $PSVersionTable.PSVersion -ge [version]'7.4'; Version = $PSVersionTable.PSVersion.ToString() })
$runtimes = Get-ToolMetadata -Name dotnet.exe -Arguments @('--list-runtimes')
$runtimeVersions = @([regex]::Matches([string]$runtimes, '(?m)^Microsoft\.NETCore\.App (10\.0\.\d+) ') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
$checks.Add([ordered]@{ Name = '.NET runtime 10.0'; Passed = $runtimeVersions.Count -gt 0; Version = if ($runtimeVersions.Count) { $runtimeVersions[0].ToString() } else { $null } })
if ($Purpose -in @('Run', 'Test')) {
    $dockerVersion = Get-ToolMetadata -Name docker.exe -Arguments @('--version')
    $checks.Add([ordered]@{ Name = 'Docker CLI'; Passed = [bool]($dockerVersion -match '^Docker version '); Version = if ($dockerVersion -match '^Docker version ([0-9.]+)') { $Matches[1] } else { $null } })
}
if ($Purpose -in @('Build', 'Test')) {
    $sdk = Get-ToolMetadata -Name dotnet.exe -Arguments @('--version')
    $checks.Add([ordered]@{ Name = '.NET SDK global.json contract'; Passed = [bool]($sdk -match '^10\.0\.\d+$'); Version = if ($sdk -match '^10\.0\.\d+$') { $sdk } else { $null } })
}
if ($Purpose -eq 'Test') {
    $node = Get-ToolMetadata -Name node.exe -Arguments @('--version')
    $checks.Add([ordered]@{ Name = 'Node.js>=22'; Passed = [bool]($node -match '^v(\d+)\.' -and [int]$Matches[1] -ge 22); Version = if ($node -match '^v[0-9.]+$') { $node } else { $null } })
    $chezmoi = Get-ToolMetadata -Name chezmoi.exe -Arguments @('--version')
    $checks.Add([ordered]@{ Name = 'chezmoi'; Passed = [bool]($chezmoi -match '^chezmoi version '); Version = if ($chezmoi -match '^chezmoi version ([^,\s]+)') { $Matches[1] } else { $null } })
}
$result = [ordered]@{
    Purpose = $Purpose
    Ready = @($checks | Where-Object { -not $_.Passed }).Count -eq 0
    Checks = $checks.ToArray()
    DpapiAvailability = 'UNTESTED'
    ColdBootSsh = 'UNTESTED'
}
if ($AsJson) { $result | ConvertTo-Json -Depth 5 }
else { [pscustomobject]$result }

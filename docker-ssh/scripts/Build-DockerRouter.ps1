#requires -Version 7.5
<# .SYNOPSIS Builds a public router package in a new directory without installing it or touching Docker. #>
param([Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($OutputRoot) -or (Test-Path -LiteralPath $OutputRoot)) { throw 'Select a new absolute output directory.' }
$sourceRoot = Split-Path $PSScriptRoot -Parent
$output = [IO.Path]::GetFullPath($OutputRoot)
$null = [IO.Directory]::CreateDirectory($output)
$start = [Diagnostics.ProcessStartInfo]::new('dotnet')
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.WorkingDirectory = $sourceRoot
foreach ($argument in @('publish', (Join-Path $sourceRoot 'src/DockerSshRouter/DockerSshRouter.csproj'), '-c', 'Release', '--nologo', '--output', (Join-Path $output 'bin'), '--artifacts-path', (Join-Path $output 'build'))) { $start.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($start)
try {
    if (-not $process.WaitForExit(300000)) { throw 'Router build indeterminate; inspect the owned build before retrying.' }
    if ($process.ExitCode -ne 0) { throw 'Router build failed.' }
} finally { $process.Dispose() }
$payload = Join-Path $output 'payload'
$null = [IO.Directory]::CreateDirectory($payload)
foreach ($name in @('Enter-DockerSshEnvironment.ps1', 'Get-TpmDockerEnvironment.ps1')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot ('chezmoi/AppData/Local/Dotfiles/DockerSsh/' + $name)) -Destination (Join-Path $payload $name)
}
$files = [ordered]@{}
foreach ($name in @('bin/docker.exe', 'payload/Enter-DockerSshEnvironment.ps1', 'payload/Get-TpmDockerEnvironment.ps1')) {
    $files[$name] = (Get-FileHash -LiteralPath (Join-Path $output $name)).Hash
}
@{ Version = 1; Files = $files } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'package.json') -Encoding utf8NoBOM
Write-Output 'Router package built; installation, ACL, Engine and credentials unchanged.'

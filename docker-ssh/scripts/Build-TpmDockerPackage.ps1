<# .SYNOPSIS Builds a versioned public-only TPM package; never initializes a key, store or user profile. #>
param([Parameter(Mandatory)][string] $OutputRoot)
$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($OutputRoot) -or (Test-Path -LiteralPath $OutputRoot)) { throw 'Select a new absolute package directory.' }
$packageDirectory=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($OutputRoot))
if ([IO.Path]::GetDirectoryName($packageDirectory) -ine [IO.Path]::GetFullPath($env:LOCALAPPDATA) -or [IO.Path]::GetFileName($packageDirectory) -notlike 'docker-ssh-issue142-lab-package-*') { throw 'Use an explicit disposable package directory immediately under LocalAppData.' }
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach ($project in @('src/DockerCredentialTpm/DockerCredentialTpm.csproj','src/TpmKeySetup/TpmKeySetup.csproj')) {
    $start = [Diagnostics.ProcessStartInfo]::new('dotnet')
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $source
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('build',(Join-Path $source $project),'-c','Release','--nologo')) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $buildOutputTask = $process.StandardOutput.ReadToEndAsync()
        $buildErrorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(300000)) { throw 'Build indeterminate; do not retry until process quiescence is established.' }
        [void]$buildOutputTask.GetAwaiter().GetResult()
        [void]$buildErrorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Package build failed.' }
    } finally { $process.Dispose() }
}
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
$security=[Security.AccessControl.DirectorySecurity]::new()
$security.SetOwner($owner)
$security.SetAccessRuleProtection($true,$false)
$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
[void][IO.FileSystemAclExtensions]::CreateDirectory($security,$packageDirectory)
$files = [ordered]@{}
foreach ($component in @(@{Name='helper';Project='DockerCredentialTpm';Base='docker-credential-ssh-tpm'},@{Name='key-tool';Project='TpmKeySetup';Base='docker-ssh-tpm-key'})) {
    foreach ($extension in @('.exe','.dll','.deps.json','.runtimeconfig.json')) {
        $relative = $component.Name + '/' + $component.Base + $extension
        $destination = Join-Path $OutputRoot $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath (Join-Path $source ('src/' + $component.Project + '/bin/Release/net10.0-windows/' + $component.Base + $extension)) -Destination $destination
        $files[$relative] = (Get-FileHash -LiteralPath $destination).Hash
    }
}
foreach ($name in @('docker-ssh.bash','Get-TpmDockerEnvironment.ps1')) {
    $destination = Join-Path $OutputRoot ('shell/' + $name)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
    Copy-Item -LiteralPath (Join-Path $source ('chezmoi/AppData/Local/Dotfiles/DockerSsh/' + $name)) -Destination $destination
    $files['shell/' + $name] = (Get-FileHash -LiteralPath $destination).Hash
}
@{Version='0.4.0';Runtime='Microsoft.NETCore.App 10';Files=$files} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputRoot 'package.json') -Encoding utf8NoBOM
Write-Output 'TPM package 0.4.0 built; ten public files; no key or credential initialization.'

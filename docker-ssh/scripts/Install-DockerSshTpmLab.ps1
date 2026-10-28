<# .SYNOPSIS Stages or verifies one explicitly selected private PoC deployment; never creates a TPM key. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $DestinationRoot,
    [Parameter(Mandatory)][string] $PackageDirectory,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $BindingPath,
    [Parameter(Mandatory)][string] $EngineEndpoint,
    [switch] $CheckOnly
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or $PSVersionTable.PSVersion -lt [version]'7.4') { throw 'Windows and PowerShell 7.4 or newer are required.' }
if ($EngineEndpoint -notmatch '^npipe:/{4}\./pipe/[A-Za-z0-9_.-]+$' -or $env:DOCKER_TLS_VERIFY -or $env:DOCKER_CERT_PATH) { throw 'Explicit named-pipe endpoint and separately reviewed TLS settings required.' }
if (-not [IO.Path]::IsPathFullyQualified($DestinationRoot)) { throw 'Absolute destination required.' }
$destination = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DestinationRoot))
$localData = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($env:LOCALAPPDATA))
if (-not $destination.StartsWith($localData + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($destination) -notlike 'docker-ssh-issue142-lab-*') { throw 'Only an explicitly named disposable PoC directory beneath LocalAppData is supported.' }
$required = @('docker-credential-ssh-tpm.exe', 'docker-credential-ssh-tpm.dll', 'docker-credential-ssh-tpm.deps.json', 'docker-credential-ssh-tpm.runtimeconfig.json')
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.Count -ne $required.Count) { throw 'Unexpected package manifest.' }
foreach ($name in $required) {
    if ($manifest[$name] -notmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $PackageDirectory $name)).Hash -cne $manifest[$name]) { throw 'Package identity mismatch.' }
}
$binding = Get-Content -LiteralPath $BindingPath -Raw | ConvertFrom-Json
if ($binding.ProviderName -ne 'Microsoft Platform Crypto Provider' -or $binding.KeyName -notlike 'docker-ssh-issue142-poc-*' -or
    $binding.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { throw 'Only this user and an explicitly created PoC key are accepted.' }
$docker = (Get-Command docker.exe -CommandType Application -ErrorAction Stop).Source
$helper = Join-Path $PackageDirectory 'docker-credential-ssh-tpm.exe'
$publicShell = Join-Path $PSScriptRoot '../chezmoi/AppData/Local/Dotfiles/DockerSsh'
$dispatcherDirectory = Join-Path $PSScriptRoot '../src/DockerSshDispatcher/bin/Release/net10.0-windows'
$additionalFiles = @{}
foreach ($name in @('docker.exe','docker.dll','docker.deps.json','docker.runtimeconfig.json')) { $additionalFiles['bin/0.5.0/' + $name] = Join-Path $dispatcherDirectory $name }
foreach ($name in @('Get-TpmDockerEnvironment.ps1','Invoke-DockerSshTpm.ps1')) { $additionalFiles['shell/' + $name] = Join-Path $publicShell $name }
foreach ($relative in $additionalFiles.Keys) {
    $manifestName = if ($relative.StartsWith('shell/')) { $relative } else { [IO.Path]::GetFileName($relative) }
    $manifest[$manifestName] = (Get-FileHash -LiteralPath $additionalFiles[$relative]).Hash
}

function Invoke-LabHelper {
    <# .SYNOPSIS Runs only a nonsecret preflight or initialization, with conservative timeout handling. #>
    param([string] $Operation, [string] $Root, [string] $Executable)
    $start = [Diagnostics.ProcessStartInfo]::new($Executable)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['DOCKER_SSH_HELPER_ROOT'] = $Root
    $start.Environment['DOCKER_SSH_TPM_BINDING'] = $BindingPath
    $start.ArgumentList.Add($Operation)
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(100)) {
            $process.Refresh()
            if ($process.MainWindowHandle -ne [IntPtr]::Zero -or $timer.Elapsed.TotalSeconds -ge 30) { throw 'Child outcome indeterminate; do not remove files or key. Establish child quiescence first.' }
        }
        [void]$output.GetAwaiter().GetResult()
        [void]$errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Helper preflight or initialization failed; preserve the partial deployment.' }
    } finally { $process.Dispose() }
}

Invoke-LabHelper -Operation validate-path -Root $destination -Executable $helper
if (Test-Path -LiteralPath $destination) {
    $installed = Get-Content -LiteralPath (Join-Path $destination 'settings.json') -Raw | ConvertFrom-Json
    if ($installed.Version -ne 1 -or $installed.HelperKind -ne 'tpm' -or $installed.HelperVersion -ne '0.5.0' -or
        $installed.EngineEndpoint -ne $EngineEndpoint -or $installed.DockerExecutable -ne $docker) { throw 'Existing deployment differs; no update or repair performed.' }
    foreach ($name in $required) {
        if ((Get-FileHash -LiteralPath (Join-Path $destination ('bin/0.5.0/' + $name))).Hash -cne $manifest[$name]) { throw 'Installed binary differs; no repair performed.' }
    }
    foreach ($relative in $additionalFiles.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $destination $relative)).Hash -cne (Get-FileHash -LiteralPath $additionalFiles[$relative]).Hash) { throw 'Installed dispatcher or shell differs.' }
    }
    $installedBinding = Get-Content -LiteralPath (Join-Path $destination 'key-binding.json') -Raw | ConvertFrom-Json
    if ($installedBinding.KeyName -ne $binding.KeyName -or $installedBinding.UniqueNameSHA256 -ne $binding.UniqueNameSHA256 -or $installedBinding.PublicSpkiSHA256 -ne $binding.PublicSpkiSHA256) { throw 'Public key identity differs.' }
    if ((Get-Content -LiteralPath (Join-Path $destination 'docker-config/config.json') -Raw | ConvertFrom-Json).credsStore -ne 'ssh-tpm') { throw 'Docker configuration differs.' }
    Write-Output 'Existing staged PoC package matches; no changes. Initialization, decryption and cold boot are not inferred.'
    return
}
if ($CheckOnly) { Write-Output 'PoC preflight passed; no directory or key created; initialization and cold boot untested.'; return }
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$security = [Security.AccessControl.DirectorySecurity]::new()
$security.SetOwner($owner)
$security.SetAccessRuleProtection($true, $false)
$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
[void][IO.FileSystemAclExtensions]::CreateDirectory($security, $destination)
$claim = [IO.FileStream]::new((Join-Path $destination 'installation.claim'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$claim.Dispose()
$binaryDirectory = Join-Path $destination 'bin/0.5.0'
[void][IO.Directory]::CreateDirectory($binaryDirectory)
foreach ($name in $required) { Copy-Item -LiteralPath (Join-Path $PackageDirectory $name) -Destination (Join-Path $binaryDirectory $name) }
foreach ($relative in $additionalFiles.Keys) {
    $target = Join-Path $destination $relative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    Copy-Item -LiteralPath $additionalFiles[$relative] -Destination $target
}
# Staging and credential initialization are separate: this script never opens a TPM key.
Copy-Item -LiteralPath $BindingPath -Destination (Join-Path $destination 'key-binding.json')
[void][IO.Directory]::CreateDirectory((Join-Path $destination 'docker-config'))
'{"credsStore":"ssh-tpm"}' | Set-Content -LiteralPath (Join-Path $destination 'docker-config/config.json') -Encoding utf8NoBOM
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'installed-manifest.json') -Encoding utf8NoBOM
@{ Version=1; State='STAGED'; HelperKind='tpm'; HelperVersion='0.5.0'; InstallationId=[guid]::NewGuid().ToString('N'); EngineEndpoint=$EngineEndpoint; DockerExecutable=$docker; PowerShellExecutable=(Get-Process -Id $PID).Path } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'settings.json') -Encoding utf8NoBOM
Write-Output 'Disposable TPM PoC deployment staged; no key, original Docker configuration, or context changed.'

<# .SYNOPSIS Validates a dedicated TPM deployment and emits exactly five nonsecret LF-delimited fields, never shell code. #>
param([Parameter(Mandatory)][string] $DeploymentRoot, [switch] $AllowDisabled, [switch] $NoOutput, [string] $ExpectedDockerConfig)
$ErrorActionPreference = 'Stop'

function Assert-TpmDeploymentPath {
    <# .SYNOPSIS Checks private leaves and every ancestor before executing or trusting any deployment file. #>
    param([string] $Path)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $trusted = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544', ([Security.Principal.NTAccount]::new('NT SERVICE','TrustedInstaller')).Translate([Security.Principal.SecurityIdentifier]).Value)
    $absolute = [IO.Path]::GetFullPath($Path)
    for ($current = $absolute; $current; $current = Split-Path -Parent $current) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse path rejected.' }
        $acl = Get-Acl -LiteralPath $current
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new($acl.Sddl)
        if ($null -eq $raw.DiscretionaryAcl -or $raw.Owner.Value -notin $trusted) { throw 'Unsafe ownership or DACL.' }
        if ($current -eq $absolute -and $raw.Owner -ne $owner) { throw 'Private leaf owner required.' }
        foreach ($rule in $acl.Access) {
            $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($rule.AccessControlType -ne 'Allow') { continue }
            if ($current -eq $absolute -and $sid -ne $owner.Value) { throw 'Private leaf grant required.' }
            $forbidden = [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
            if (-not ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and $sid -notin $trusted -and ($rule.FileSystemRights -band $forbidden)) { throw 'Replaceable ancestor rejected.' }
        }
    }
}

try {
    if (-not $IsWindows -or -not [IO.Path]::IsPathFullyQualified($DeploymentRoot)) { throw 'Windows absolute path required.' }
    if ($env:DOCKER_TLS_VERIFY -or $env:DOCKER_CERT_PATH) { throw 'Inherited TLS configuration requires separate review.' }
    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($DeploymentRoot))
    $settings = Join-Path $root 'settings.json'
    foreach ($path in @($root, $settings, (Join-Path $root 'installed-manifest.json'), (Join-Path $root 'docker-config/config.json'))) {
        Assert-TpmDeploymentPath -Path $path
    }
    $configuration = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    if ($configuration.State -notin @('READY','STAGED') -and -not ($AllowDisabled -and $configuration.State -eq 'DISABLED')) { throw 'Deployment is disabled or incomplete.' }
    if ($configuration.Version -ne 1 -or $configuration.HelperKind -ne 'tpm' -or $configuration.HelperVersion -ne '0.4.0' -or
        $configuration.EngineEndpoint -notmatch '^npipe:/{4}\./pipe/[A-Za-z0-9_.-]+$' -or
        -not [IO.Path]::IsPathFullyQualified($configuration.DockerExecutable) -or -not (Test-Path -LiteralPath $configuration.DockerExecutable -PathType Leaf)) { throw 'Unsupported settings.' }
    $binary = Join-Path $root ('bin/' + $configuration.HelperVersion)
    foreach ($directory in @((Join-Path $root 'bin'), $binary, (Join-Path $root 'docker-config'))) { Assert-TpmDeploymentPath -Path $directory }
    $manifest = Get-Content -LiteralPath (Join-Path $root 'installed-manifest.json') -Raw | ConvertFrom-Json -AsHashtable
    $names = @('docker-credential-ssh-tpm.exe','docker-credential-ssh-tpm.dll','docker-credential-ssh-tpm.deps.json','docker-credential-ssh-tpm.runtimeconfig.json')
    if ($manifest.Count -ne 4) { throw 'Incomplete manifest.' }
    foreach ($name in $names) {
        Assert-TpmDeploymentPath -Path (Join-Path $binary $name)
        if ($manifest[$name] -notmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $binary $name)).Hash -cne $manifest[$name]) { throw 'Helper binary mismatch.' }
    }
    $dockerConfig = Get-Content -LiteralPath (Join-Path $root 'docker-config/config.json') -Raw | ConvertFrom-Json
    if ($dockerConfig.credsStore -ne 'ssh-tpm' -or $dockerConfig.credHelpers) { throw 'Dedicated helper routing mismatch.' }
    foreach ($entry in $dockerConfig.auths.PSObject.Properties) {
        if ($entry.Value.auth -or $entry.Value.identitytoken -or $entry.Value.password) { throw 'Inline credentials rejected.' }
    }
    $dockerConfigDirectory = Join-Path $root 'docker-config'
    if ($PSBoundParameters.ContainsKey('ExpectedDockerConfig') -and
        (-not [IO.Path]::IsPathFullyQualified($ExpectedDockerConfig) -or
        [IO.Path]::GetFullPath($ExpectedDockerConfig) -cne [IO.Path]::GetFullPath($dockerConfigDirectory))) { throw 'Resolved Docker configuration path mismatch.' }
    $fields = @($configuration.DockerExecutable, $binary, $dockerConfigDirectory, (Join-Path $root 'store'), $configuration.EngineEndpoint)
    if (@($fields | Where-Object { -not $_ -or $_ -match '[\r\n]' }).Count) { throw 'Invalid metadata field.' }
    if (-not $NoOutput) {
        # Write UTF-8 bytes without changing a console code page shared with the parent shell.
        $metadataBytes = [Text.UTF8Encoding]::new($false).GetBytes(($fields -join "`n"))
        $metadataStream = [Console]::OpenStandardOutput()
        $metadataStream.Write($metadataBytes, 0, $metadataBytes.Length)
        $metadataStream.Flush()
    }
} catch {
    [Console]::Error.WriteLine('TPM Docker deployment validation failed; no shell state changed.')
    # A dot-sourced validation must terminate its caller's operation rather than merely set LASTEXITCODE.
    if ($NoOutput) { throw 'TPM Docker deployment validation failed.' }
    exit 1
}

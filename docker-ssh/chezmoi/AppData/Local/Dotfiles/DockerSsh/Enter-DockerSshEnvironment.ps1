<# .SYNOPSIS Validates an explicit host selector and emits nonsecret deployment metadata for the parent shell. #>
param([string] $SelectorPath = (Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerSsh/ssh-environment.json'), [string] $PublicBootstrapRoot = (Join-Path $env:LOCALAPPDATA 'Dotfiles/DockerSsh'))
$ErrorActionPreference = 'Stop'
try {
    if (-not $IsWindows) { throw 'Windows required.' }
    . (Join-Path $PSScriptRoot 'Get-TpmDockerEnvironment.ps1') -DefinitionsOnly
    Assert-TpmDeploymentPath -Path $SelectorPath
    $selector = Get-Content -LiteralPath $SelectorPath -Raw | ConvertFrom-Json
    if ($selector.Version -ne 1 -or -not [IO.Path]::IsPathFullyQualified($selector.DeploymentRoot)) { throw 'Explicit deployment selector required.' }
    . (Join-Path $PSScriptRoot 'Get-TpmDockerEnvironment.ps1') -DeploymentRoot $selector.DeploymentRoot -NoOutput -RequireReady
    # Execute only checkout code; deployed public hooks are verified as data before accepting their installation.
    Assert-TpmDeploymentPath -Path $PublicBootstrapRoot -PublicLeaf
    foreach ($name in @('Enter-DockerSshEnvironment.ps1','Get-TpmDockerEnvironment.ps1')) {
        $publicPath = Join-Path $PublicBootstrapRoot $name
        Assert-TpmDeploymentPath -Path $publicPath -PublicLeaf
        $canonicalText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $name)).Replace("`r`n","`n").TrimEnd([char]10)
        $publicText = [IO.File]::ReadAllText($publicPath).Replace("`r`n","`n").TrimEnd([char]10)
        if ($publicText -cne $canonicalText) { throw 'Public bootstrap source mismatch.' }
    }
    if ($configuration.HelperVersion -ne '0.5.0' -or $configuration.State -ne 'READY') { throw 'Managed SSH requires a ready 0.5.0 deployment.' }
    $fields = @($root, $configuration.DockerExecutable, $binary, $dockerConfigDirectory, (Join-Path $root 'store'), $configuration.EngineEndpoint)
    if (@($fields | Where-Object { -not $_ -or $_ -match '[\r\n]' }).Count) { throw 'Invalid metadata.' }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($fields -join "`n"))
    $stream = [Console]::OpenStandardOutput()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
} catch {
    [Console]::Error.WriteLine('Managed SSH Docker initialization failed; a valid explicit selector is required.')
    exit 1
}

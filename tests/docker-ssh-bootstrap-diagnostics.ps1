#requires -Version 7.5
<# .SYNOPSIS Exercises the actual bootstrap with synthetic deployment validation, without ACL, SSH, Docker or psmux operations. #>
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows and PowerShell 7.5 or newer are required.' }
$repository = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repository 'docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh/Enter-DockerSshEnvironment.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('docker-ssh-diagnostics-' + [guid]::NewGuid().ToString('N'))
$canonicalRoot = Join-Path $fixtureRoot 'canonical'
$publicRoot = Join-Path $fixtureRoot 'public'
$selectorPath = Join-Path $fixtureRoot 'selector.json'
$runtime = (Get-Process -Id $PID).Path
$cases = 0

function Invoke-DiagnosticCase {
    <# .SYNOPSIS Runs an isolated bootstrap child and requires exact output, exit status and bounded completion. #>
    param([string]$Name, [string]$ExpectedCode = '')
    $start = [Diagnostics.ProcessStartInfo]::new($runtime)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile','-File',(Join-Path $canonicalRoot 'Enter-DockerSshEnvironment.ps1'),'-SelectorPath',$selectorPath,'-PublicBootstrapRoot',$publicRoot)) {
        [void]$start.ArgumentList.Add($argument)
    }
    $child = [Diagnostics.Process]::Start($start)
    try {
        $outputTask = $child.StandardOutput.ReadToEndAsync()
        $errorTask = $child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(10000)) {
            $child.Kill($true)
            $child.WaitForExit()
            throw ('Diagnostic child timed out: ' + $Name)
        }
        $output = $outputTask.GetAwaiter().GetResult()
        $errorOutput = $errorTask.GetAwaiter().GetResult()
        if ($ExpectedCode) {
            $expected = 'Managed SSH Docker initialization failed [' + $ExpectedCode + '].'
            if ($child.ExitCode -ne 1 -or $output -cne '' -or $errorOutput.TrimEnd("`r","`n") -cne $expected) {
                throw ('Diagnostic rejection contract failed: ' + $Name)
            }
        } elseif ($child.ExitCode -ne 0 -or $errorOutput -cne '' -or @($output.Split("`n")).Count -ne 6) {
            throw ('Diagnostic success contract failed: ' + $Name)
        }
        $script:cases++
        Write-Output ('PASS ' + $Name)
    } finally { $child.Dispose() }
}

function Set-FixtureSelector {
    <# .SYNOPSIS Selects a synthetic deployment mode using a temporary selector only. #>
    param([string]$Mode = 'ready', [int]$Version = 1)
    $selector = @{ Version=$Version; DeploymentRoot=(Join-Path $fixtureRoot $Mode) } | ConvertTo-Json
    [IO.File]::WriteAllText($selectorPath, $selector, [Text.UTF8Encoding]::new($false))
}

try {
    [void][IO.Directory]::CreateDirectory($canonicalRoot)
    [void][IO.Directory]::CreateDirectory($publicRoot)
    [IO.File]::Copy($source, (Join-Path $canonicalRoot 'Enter-DockerSshEnvironment.ps1'))
    $reader = @'
#requires -Version 7.5
param([string]$DeploymentRoot, [switch]$DefinitionsOnly, [switch]$NoOutput, [switch]$RequireReady)
function Assert-TpmDeploymentPath {
    <# .SYNOPSIS Accepts fixture paths without inspecting or modifying filesystem permissions. #>
    param([string]$Path, [switch]$PublicLeaf)
    if (-not (Test-Path -LiteralPath $Path)) { throw 'synthetic-private-detail' }
}
if ($DefinitionsOnly) { return }
if (-not $NoOutput -or -not $RequireReady) { throw 'synthetic-private-detail' }
$mode = Split-Path -Leaf $DeploymentRoot
if ($mode -eq 'deployment-failure') { throw 'synthetic-private-detail' }
$root = $DeploymentRoot
$binary = 'synthetic-binary'
$dockerConfigDirectory = 'synthetic-config'
$configuration = [pscustomobject]@{ HelperVersion='0.5.0'; State='READY'; DockerExecutable='synthetic-docker'; EngineEndpoint='synthetic-endpoint' }
if ($mode -eq 'not-ready') { $configuration.State = 'DISABLED' }
if ($mode -eq 'invalid-metadata') { $binary = "synthetic`nprivate-detail" }
'@
    [IO.File]::WriteAllText((Join-Path $canonicalRoot 'Get-TpmDockerEnvironment.ps1'), $reader, [Text.UTF8Encoding]::new($false))
    foreach ($name in @('Enter-DockerSshEnvironment.ps1','Get-TpmDockerEnvironment.ps1')) {
        [IO.File]::Copy((Join-Path $canonicalRoot $name), (Join-Path $publicRoot $name))
    }
    Set-FixtureSelector
    Invoke-DiagnosticCase 'matching-public-copies'
    [IO.File]::Delete($selectorPath)
    Invoke-DiagnosticCase 'missing-selector' 'DSSH_SELECTOR_INVALID'
    [IO.File]::WriteAllText($selectorPath, '{synthetic-private-detail')
    Invoke-DiagnosticCase 'malformed-selector' 'DSSH_SELECTOR_INVALID'
    Set-FixtureSelector -Version 0
    Invoke-DiagnosticCase 'invalid-selector-version' 'DSSH_SELECTOR_INVALID'
    [IO.File]::WriteAllText($selectorPath, '{"Version":1,"DeploymentRoot":"relative-private-detail"}')
    Invoke-DiagnosticCase 'relative-deployment-selector' 'DSSH_SELECTOR_INVALID'
    Set-FixtureSelector -Mode 'deployment-failure'
    Invoke-DiagnosticCase 'deployment-validation-failure' 'DSSH_DEPLOYMENT_INVALID'
    Set-FixtureSelector
    foreach ($name in @('Enter-DockerSshEnvironment.ps1','Get-TpmDockerEnvironment.ps1')) {
        $target = Join-Path $publicRoot $name
        [IO.File]::AppendAllText($target, "`n# synthetic-private-detail`n")
        Invoke-DiagnosticCase ('mismatched-' + $name) 'DSSH_PUBLIC_COPY_MISMATCH'
        [IO.File]::Copy((Join-Path $canonicalRoot $name), $target, $true)
        $content = [IO.File]::ReadAllText($target).Replace("`r`n","`n")
        [IO.File]::WriteAllText($target, $content.Replace("#requires -Version 7.5`n",''))
        Invoke-DiagnosticCase ('stale-version-requirement-' + $name) 'DSSH_PUBLIC_COPY_MISMATCH'
        [IO.File]::WriteAllText($target, $content.Replace("`n","`r`n") + "`r`n")
    }
    Invoke-DiagnosticCase 'normalized-line-endings-and-trailing-newlines'
    [IO.File]::Delete((Join-Path $publicRoot 'Get-TpmDockerEnvironment.ps1'))
    Invoke-DiagnosticCase 'missing-public-copy' 'DSSH_PUBLIC_BOOTSTRAP_INVALID'
    [IO.File]::Copy((Join-Path $canonicalRoot 'Get-TpmDockerEnvironment.ps1'), (Join-Path $publicRoot 'Get-TpmDockerEnvironment.ps1'))
    Set-FixtureSelector -Mode 'not-ready'
    Invoke-DiagnosticCase 'non-ready-deployment' 'DSSH_DEPLOYMENT_INVALID'
    Set-FixtureSelector -Mode 'invalid-metadata'
    Invoke-DiagnosticCase 'invalid-metadata' 'DSSH_METADATA_INVALID'
    Write-Output ('PASS: {0} ACL-free diagnostic cases; PowerShell {1}' -f $cases,$PSVersionTable.PSVersion)
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}

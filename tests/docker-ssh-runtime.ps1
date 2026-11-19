#requires -Version 7.5
<# .SYNOPSIS Tests the PowerShell minimum and exact launcher restoration with synthetic readers, without ACL or backend operations. #>
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows and PowerShell 7.5 or newer are required.' }
$repository = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $repository 'docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh/Invoke-DockerSshTpm.ps1'
$assertions = 0
$deadline = [DateTime]::UtcNow.AddSeconds(90)

function Assert-FixtureCondition {
    <# .SYNOPSIS Requires a fixture property without displaying environment values. #>
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw ('Failed fixture assertion: ' + $Name) }
    $script:assertions++
}

function Get-RoutingSnapshot {
    <# .SYNOPSIS Captures exact routing presence and values for comparison inside this test process. #>
    $snapshot = [ordered]@{}
    foreach ($name in @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')) {
        $snapshot[$name] = Get-LauncherEnvironmentState -Name $name
    }
    return ($snapshot | ConvertTo-Json -Depth 4 -Compress)
}

$tokens = $null
$parseErrors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$parseErrors)
Assert-FixtureCondition ($parseErrors.Count -eq 0) 'launcher syntax'
# Import the actual validation functions only; the launcher main must never run in this fixture.
foreach ($functionName in @('Get-LauncherEnvironmentState','Set-LauncherEnvironmentState','Read-LauncherDeployment')) {
    $definition = $tree.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $false)
    Assert-FixtureCondition ($null -ne $definition) ('function ' + $functionName)
    . ([ScriptBlock]::Create($definition.Extent.Text))
}

$sourcePaths = @(Get-ChildItem (Join-Path $repository 'docker-ssh/scripts') -Filter '*.ps1') +
    @(Get-ChildItem (Join-Path $repository 'docker-ssh/chezmoi/AppData/Local/Dotfiles/DockerSsh') -Filter '*.ps1') +
    @(Get-ChildItem (Join-Path $repository 'docker-ssh/tests') -Filter '*.ps1')
foreach ($sourcePath in $sourcePaths) {
    $sourceTree = [Management.Automation.Language.Parser]::ParseFile($sourcePath.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-FixtureCondition ($parseErrors.Count -eq 0) ('syntax ' + $sourcePath.Name)
    Assert-FixtureCondition ($sourceTree.ScriptRequirements.RequiredPSVersion -eq [version]'7.5') ('minimum 7.5 ' + $sourcePath.Name)
}

# Exercise the production guard with substituted version operands, not an emulated old interpreter.
$readDefinition = $tree.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-LauncherDeployment' }, $false)
$guardText = $readDefinition.Body.EndBlock.Statements[0].Extent.Text
Assert-FixtureCondition ($guardText.Contains('$PSVersionTable.PSVersion')) 'version guard precedes validation'
foreach ($unsupportedVersion in @('5.1','6.2','7.0','7.3','7.4')) {
    $guard = [ScriptBlock]::Create($guardText.Replace('$PSVersionTable.PSVersion', "[version]'$unsupportedVersion'"))
    $message = ''
    try { & $guard } catch { $message = $_.Exception.Message }
    Assert-FixtureCondition ($message -eq 'PowerShell 7.5 or newer is required for exact routing restoration.') ('unsupported ' + $unsupportedVersion)
}
foreach ($supportedVersion in @('7.5','7.6',$PSVersionTable.PSVersion.ToString())) {
    $guard = [ScriptBlock]::Create($guardText.Replace('$PSVersionTable.PSVersion', "[version]'$supportedVersion'"))
    & $guard
    Assert-FixtureCondition $true ('supported guard ' + $supportedVersion)
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('docker-ssh-runtime-' + [guid]::NewGuid().ToString('N'))
$reader = Join-Path $fixtureRoot 'reader.ps1'
$settings = Join-Path $fixtureRoot 'settings.json'
$previousRouting = @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG') | ForEach-Object { Get-LauncherEnvironmentState -Name $_ }
$previousExit = Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$exitExisted = $null -ne $previousExit
$exitValue = if ($exitExisted) { $previousExit.Value } else { $null }
try {
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    [IO.File]::WriteAllText($settings, '{"HelperVersion":"0.4.0"}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($reader, @'
#requires -Version 7.5
[CmdletBinding()]
param([string]$DeploymentRoot, [switch]$DefinitionsOnly, [switch]$NoOutput, [switch]$RequireReady)
function Assert-TpmDeploymentPath {
    <# .SYNOPSIS Accepts only this synthetic reader's directory and settings file, without inspecting ACLs. #>
    param([string]$Path)
    if ($Path -ne $PSScriptRoot -and $Path -ne (Join-Path $PSScriptRoot 'settings.json')) { throw 'Unexpected fixture path.' }
}
if ($DefinitionsOnly) { return }
if (-not $NoOutput) { throw 'Synthetic reader must suppress output.' }
foreach ($name in @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')) {
    if (Test-Path -LiteralPath ('Env:' + $name)) { throw 'Legacy routing was not normalized.' }
}
$configuration = [pscustomobject]@{ HelperVersion='0.4.0' }
switch ($global:syntheticReaderMode) {
    'exception' { throw 'Synthetic validation failure.' }
    'nonterminating' { Write-Error 'Synthetic reader error.' -ErrorAction Continue }
    'native-status' { $global:LASTEXITCODE = 37 }
    'missing-result' { $configuration = $null }
}
'@, [Text.UTF8Encoding]::new($false))
    $names = @('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_AUTH_CONFIG')
    for ($combination = 0; $combination -lt 27; $combination++) {
        foreach ($exitState in @('absent','zero','nonzero')) {
            foreach ($mode in @('success','exception','nonterminating','native-status','missing-result')) {
                if ([DateTime]::UtcNow -gt $deadline) { throw 'Runtime regression exceeded its 90-second deadline.' }
                $remaining = $combination
                foreach ($name in $names) {
                    $state = $remaining % 3
                    $remaining = [int][Math]::Floor($remaining / 3)
                    $value = if ($state -eq 2) { 'synthetic-value' } else { '' }
                    Set-LauncherEnvironmentState ([pscustomobject]@{ Name=$name; Exists=($state -ne 0); Value=$value })
                }
                if ($exitState -eq 'absent') { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
                elseif ($exitState -eq 'zero') { $global:LASTEXITCODE = 0 }
                else { $global:LASTEXITCODE = 29 }
                $before = Get-RoutingSnapshot
                $global:syntheticReaderMode = $mode
                $failed = $false
                $configuration = $null
                try { $configuration = Read-LauncherDeployment -Reader $reader -Deployment $fixtureRoot -Strict:$false 2>$null }
                catch { $failed = $true }
                Assert-FixtureCondition ($failed -eq ($mode -ne 'success')) ('reader outcome ' + $mode)
                Assert-FixtureCondition ((Get-RoutingSnapshot) -ceq $before) 'routing presence and exact values restored'
                $afterExit = Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
                if ($exitState -eq 'absent') { Assert-FixtureCondition ($null -eq $afterExit) 'absent exit restored' }
                else { Assert-FixtureCondition ($null -ne $afterExit -and $afterExit.Value -eq $(if ($exitState -eq 'zero') { 0 } else { 29 })) 'exit value restored' }
                if ($mode -eq 'success') { Assert-FixtureCondition ($configuration.HelperVersion -eq '0.4.0') 'legacy result preserved' }
                else { Assert-FixtureCondition ($null -eq $configuration) 'failed validation emits no configuration' }
            }
        }
    }
    Write-Output ('PASS PowerShell {0}: {1} assertions; 405 synthetic restoration cases; no ACL/backend execution' -f $PSVersionTable.PSVersion, $assertions)
}
finally {
    foreach ($state in $previousRouting) { Set-LauncherEnvironmentState -State $state }
    if ($exitExisted) { $global:LASTEXITCODE = $exitValue }
    else { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    foreach ($fixtureFile in @($reader,$settings)) {
        if ([IO.File]::Exists($fixtureFile)) { Remove-Item -LiteralPath $fixtureFile }
    }
    if ([IO.Directory]::Exists($fixtureRoot)) { [IO.Directory]::Delete($fixtureRoot) }
}

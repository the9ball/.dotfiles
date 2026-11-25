# Run with pwsh or Windows PowerShell -NoProfile -File .\tests\personal-cli-profile.ps1.
if ($args.Count -gt 0 -and $args[0] -eq '-NativeStub') {
    ConvertTo-Json -Compress -InputObject @($args[1..($args.Count - 1)])
    exit 37
}

$ErrorActionPreference = 'Stop'

function Assert-Equal {
    <# .SYNOPSIS
    Fail when two scalar values or arrays differ, including empty arguments.
    #>
    param($Actual, $Expected, $Label)
    $actualValues = @($Actual)
    $expectedValues = @($Expected)
    if ($actualValues.Count -ne $expectedValues.Count) { throw "$Label count differs" }
    for ($index = 0; $index -lt $actualValues.Count; $index++) {
        if ($actualValues[$index] -cne $expectedValues[$index]) { throw "$Label differs at $index" }
    }
}

function Invoke-CliStub {
    <# .SYNOPSIS
    Observe the wrapper without calling a real CLI, and simulate a native exit or exception.
    #>
    param($ObservedArguments, $ObservedInput)
    $script:observation = @{
        Codex = $env:CODEX_HOME
        Claude = $env:CLAUDE_CONFIG_DIR
        Arguments = @($ObservedArguments)
        InputValues = @($ObservedInput)
    }
    if ($script:throwFromStub) { throw 'fixture failure' }
    & $env:ComSpec /d /c 'exit 37'
    Write-Host "stub native exit=$LASTEXITCODE"
    $global:LASTEXITCODE = $LASTEXITCODE
    'fixture output'
}

function codex {
    <# .SYNOPSIS
    Replace Codex with an in-process observation stub.
    #>
    Invoke-CliStub -ObservedArguments $args -ObservedInput @($input)
}

function claude {
    <# .SYNOPSIS
    Replace Claude with an in-process observation stub.
    #>
    Invoke-CliStub -ObservedArguments $args -ObservedInput @($input)
}

$repository = Split-Path $PSScriptRoot -Parent
$previousCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
$previousClaudeConfig = [Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR', 'Process')
$previousEditor = $env:EDITOR
$previousVisual = $env:VISUAL
try {
    foreach ($profileDirectory in @('PowerShell', 'WindowsPowerShell')) {
        . (Join-Path $repository "chezmoi/Documents/$profileDirectory/Microsoft.PowerShell_profile.ps1")
        Invoke-PersonalCli -Command $env:ComSpec -CommandArguments @('/d', '/c', 'exit 23') -HasPipelineInput $false
        Write-Host "helper native exit=$LASTEXITCODE"
        Assert-Equal $LASTEXITCODE 23 'helper native exit propagation'
        $nativeArguments = @('--', 'tail', 'two words')
        $stubArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-NativeStub') + $nativeArguments
        $nativeOutput = Invoke-PersonalCli -Command "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -CommandArguments $stubArguments -HasPipelineInput $false
        Write-Host "native argument stub exit=$LASTEXITCODE"
        Assert-Equal $LASTEXITCODE 37 'native argument stub exit'
        Assert-Equal (ConvertFrom-Json $nativeOutput) $nativeArguments 'native arguments'
        foreach ($wrapper in @('pcodex', 'pclaude')) {
            foreach ($initialValue in @($null, 'inherited home')) {
                foreach ($withPipeline in @($false, $true)) {
                    foreach ($script:throwFromStub in @($false, $true)) {
                        if ($null -eq $initialValue) {
                            Remove-Item Env:CODEX_HOME, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
                        } else {
                            $env:CODEX_HOME = $initialValue
                            $env:CLAUDE_CONFIG_DIR = $initialValue
                        }
                        $script:observation = $null
                        $caught = $false
                        $commandArguments = @('first argument', '--', '', '-last', 'quoted"value')
                        try {
                            if ($withPipeline) {
                                $output = @('line one', 'line two') | & $wrapper @commandArguments
                            } else {
                                $output = & $wrapper @commandArguments
                            }
                            $observedExitCode = $LASTEXITCODE
                        } catch {
                            if ($_.Exception.Message -ne 'fixture failure') { throw }
                            $caught = $true
                        }
                        Assert-Equal $caught $script:throwFromStub 'exception propagation'
                        Assert-Equal $script:observation.Codex (Join-Path $HOME '.codex-personal') 'child Codex home'
                        Assert-Equal $script:observation.Claude (Join-Path $HOME '.claude-personal') 'child Claude home'
                        Assert-Equal $script:observation.Arguments $commandArguments 'arguments'
                        $expectedInput = @()
                        if ($withPipeline) { $expectedInput = @('line one', 'line two') }
                        Assert-Equal $script:observation.InputValues $expectedInput 'pipeline input'
                        if (-not $script:throwFromStub) {
                            Assert-Equal $observedExitCode 37 'native exit code'
                            Assert-Equal $output 'fixture output' 'output'
                        }
                        Assert-Equal ([Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')) $initialValue 'Codex restoration'
                        Assert-Equal ([Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR', 'Process')) $initialValue 'Claude restoration'
                    }
                }
            }
        }
        Write-Host "PASS $profileDirectory"
    }
} finally {
    if ($null -eq $previousCodexHome) {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $previousCodexHome, 'Process')
    }
    if ($null -eq $previousClaudeConfig) {
        Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $previousClaudeConfig, 'Process')
    }
    $env:EDITOR = $previousEditor
    $env:VISUAL = $previousVisual
}

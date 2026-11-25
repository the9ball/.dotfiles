# Use nano for interactive editors, including Codex Ctrl+G.
$env:EDITOR = 'nano'
$env:VISUAL = 'nano'

function Invoke-PersonalCli {
    <# .SYNOPSIS
    Run a CLI with the personal account pair, restoring the process environment even on failure.
    #>
    param($Command, $CommandArguments, $PipelineInput, $HasPipelineInput)

    $previousCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    $previousClaudeConfig = [Environment]::GetEnvironmentVariable('CLAUDE_CONFIG_DIR', 'Process')
    try {
        $env:CODEX_HOME = Join-Path $HOME '.codex-personal'
        $env:CLAUDE_CONFIG_DIR = Join-Path $HOME '.claude-personal'
        if ($HasPipelineInput) {
            $PipelineInput | & $Command @CommandArguments
        } else {
            & $Command @CommandArguments
        }
        $global:LASTEXITCODE = $LASTEXITCODE
    } finally {
        # .NET on PowerShell 7 can turn null into an empty variable instead of removing it.
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
    }
}

function pcodex {
    <# .SYNOPSIS
    Pass arguments and pipeline input to Codex with the personal account pair.
    #>
    Invoke-PersonalCli -Command codex -CommandArguments $args -PipelineInput $input -HasPipelineInput $MyInvocation.ExpectingInput
}

function pclaude {
    <# .SYNOPSIS
    Pass arguments and pipeline input to Claude with the personal account pair.
    #>
    Invoke-PersonalCli -Command claude -CommandArguments $args -PipelineInput $input -HasPipelineInput $MyInvocation.ExpectingInput
}

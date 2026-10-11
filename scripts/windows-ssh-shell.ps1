<#
.SYNOPSIS
Sets the Windows OpenSSH default shell to Git Bash or restores its saved values.
.DESCRIPTION
Run with an explicit PowerShell interpreter as an administrator. Only DefaultShell
and DefaultShellCommandOption are changed. A backup is retained outside Git.
Use -WhatIf to inspect the operation without administrator privileges or writes.
.PARAMETER Action
Enable selects Git Bash; Restore reinstates the backup, including absent values.
.PARAMETER BackupPath
Local CLIXML backup path. Enable refuses to overwrite an existing backup.
.PARAMETER GitBashPath
Optional bin/bash.exe path when Git for Windows cannot be located through PATH.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Enable', 'Restore')]
    [string]$Action,
    [string]$BackupPath = (Join-Path $HOME 'openssh-default-shell.backup.clixml'),
    [string]$GitBashPath
)

$ErrorActionPreference = 'Stop'
$openSshRegistryPath = 'HKLM:\SOFTWARE\OpenSSH'
$shellPropertyNames = @('DefaultShell', 'DefaultShellCommandOption')

function Restore-ShellProperties {
    <#
    .SYNOPSIS
    Restores validated shell properties, preserving registry types and absence.
    .PARAMETER Properties
    The two validated snapshots captured before changing the OpenSSH shell.
    #>
    param([object[]]$Properties)

    foreach ($savedProperty in $Properties) {
        if ($savedProperty.Exists) {
            New-ItemProperty -LiteralPath $openSshRegistryPath -Name $savedProperty.Name `
                -Value $savedProperty.Value -PropertyType $savedProperty.Kind -Force | Out-Null
        } elseif ((Get-Item -LiteralPath $openSshRegistryPath).GetValueNames() -contains $savedProperty.Name) {
            Remove-ItemProperty -LiteralPath $openSshRegistryPath -Name $savedProperty.Name
        }
    }
}

if (-not $WhatIfPreference) {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in an administrator PowerShell, or use -WhatIf.'
    }
}

if ($Action -eq 'Restore') {
    $shellProperties = @(Import-Clixml -LiteralPath $BackupPath)
    # Validate the complete backup before making the first registry change.
    if ($shellProperties.Count -ne 2 -or
        @($shellProperties.Name | Sort-Object -Unique).Count -ne 2) {
        throw 'The backup must contain exactly the two OpenSSH shell properties.'
    }
    foreach ($savedProperty in $shellProperties) {
        if ($savedProperty.Name -notin $shellPropertyNames -or $savedProperty.Exists -isnot [bool]) {
            throw 'Unexpected property or presence flag in the shell backup.'
        }
        # Older README backups did not record a type and used string properties.
        if ($savedProperty.Exists -and $null -eq $savedProperty.PSObject.Properties['Kind']) {
            $savedProperty | Add-Member -NotePropertyName Kind -NotePropertyValue 'String'
        }
        if ($savedProperty.Exists -and
            ($savedProperty.Value -isnot [string] -or $savedProperty.Kind -notin 'String', 'ExpandString')) {
            throw 'Unexpected registry value or type in the shell backup.'
        }
    }
    if ($PSCmdlet.ShouldProcess($openSshRegistryPath, "Restore SSH shell from $BackupPath")) {
        Restore-ShellProperties -Properties $shellProperties
        Write-Output 'OpenSSH default shell restored. Verify with a separate SSH connection.'
    }
    return
}

if (-not $GitBashPath) {
    $gitCommandPath = (Get-Command git.exe -ErrorAction Stop).Source
    $gitInstallationDirectory = Split-Path (Split-Path $gitCommandPath -Parent) -Parent
    $GitBashPath = Join-Path $gitInstallationDirectory 'bin\bash.exe'
}
if (-not (Test-Path -LiteralPath $GitBashPath -PathType Leaf) -or
    (Split-Path $GitBashPath -Leaf) -ne 'bash.exe') {
    throw 'Specify the existing Git for Windows bin\bash.exe, not git-bash.exe.'
}
$GitBashPath = (Resolve-Path -LiteralPath $GitBashPath).ProviderPath
if (Test-Path -LiteralPath $BackupPath) {
    throw 'A shell backup already exists. Preserve it before making another change.'
}
$registryKey = Get-Item -LiteralPath $openSshRegistryPath
$shellProperties = foreach ($propertyName in $shellPropertyNames) {
    $propertyExists = $registryKey.GetValueNames() -contains $propertyName
    $propertyKind = if ($propertyExists) { $registryKey.GetValueKind($propertyName).ToString() } else { $null }
    if ($propertyExists -and $propertyKind -notin 'String', 'ExpandString') {
        throw 'Unexpected existing SSH shell registry type; inspect it before continuing.'
    }
    [pscustomobject]@{
        Name = $propertyName
        Exists = $propertyExists
        Value = if ($propertyExists) {
            $registryKey.GetValue($propertyName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        } else { $null }
        Kind = $propertyKind
    }
}
if ($PSCmdlet.ShouldProcess($openSshRegistryPath, "Back up to $BackupPath and select Git Bash $GitBashPath")) {
    $shellProperties | Export-Clixml -LiteralPath $BackupPath -NoClobber
    try {
        New-ItemProperty -LiteralPath $openSshRegistryPath -Name DefaultShell `
            -Value $GitBashPath -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $openSshRegistryPath -Name DefaultShellCommandOption `
            -Value '-c' -PropertyType String -Force | Out-Null
    } catch {
        # A partial change must not leave the shell and command option mismatched.
        Restore-ShellProperties -Properties $shellProperties
        throw
    }
    Write-Output 'Git Bash selected. Keep recovery access and verify with a separate SSH connection.'
}

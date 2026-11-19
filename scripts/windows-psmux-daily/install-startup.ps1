# Install or remove only this user's daily monitor shortcut; never stop a session.
param([switch]$StartNow, [switch]$Remove)

$ErrorActionPreference = 'Stop'
if ($StartNow -and $Remove) { throw 'Choose installation/start or removal.' }
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -ne 1) {
    throw 'Run this installer in the normal Windows Session 1 terminal.'
}
$startupDirectory = [Environment]::GetFolderPath('Startup')
if (-not (Test-Path -LiteralPath $startupDirectory -PathType Container)) {
    throw 'The current-user Startup folder was not found.'
}
$shortcutPath = Join-Path $startupDirectory 'Dotfiles psmux Session 1.lnk'
$launcherPath = Join-Path $PSScriptRoot 'launch-hidden.vbs'
$wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$arguments = '//B //Nologo "' + $launcherPath + '"'
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcut = $shortcutShell.CreateShortcut($shortcutPath)
if ((Test-Path -LiteralPath $shortcutPath) -and
    ($shortcut.TargetPath -ine $wscriptPath -or $shortcut.Arguments -cne $arguments)) {
    throw 'The shortcut name is already used for another target; no changes made.'
}
if ($Remove) {
    if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath }
    Write-Output 'Daily startup shortcut removed; running sessions were left alone.'
    return
}
$null = & (Join-Path $PSScriptRoot 'resolve-psmux.ps1')
$runtimeDirectory = Join-Path $env:LOCALAPPDATA 'Dotfiles\PsmuxDaily'
if ($StartNow -and (Test-Path -LiteralPath (Join-Path $runtimeDirectory 'stop.request'))) {
    throw 'Daily stop.request remains. Inspect the daily monitor before removing it and restarting.'
}
$shortcut.TargetPath = $wscriptPath
$shortcut.Arguments = $arguments
$shortcut.WindowStyle = 7
$shortcut.Description = 'Dotfiles Session 1 psmux monitor'
$shortcut.Save()
Write-Output ('Installed current-user startup shortcut: ' + $shortcutPath)
if ($StartNow) {
    $launcher = Start-Process -FilePath $wscriptPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Write-Output ('Daily launcher started in Session 1, PID ' + $launcher.Id + '. Check main.monitor.log and main.attach.log for readiness.')
}

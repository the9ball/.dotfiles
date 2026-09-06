@echo off
setlocal

set "SCRIPT_PATH_WIN=%~dp0start-codex-remote.sh"
set "SCRIPT_PATH_WIN=%SCRIPT_PATH_WIN:\=/%"

wsl.exe bash -lc "exec bash \"$(wslpath -u '%SCRIPT_PATH_WIN%')\""
exit /b %ERRORLEVEL%

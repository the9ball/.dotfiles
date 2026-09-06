@echo off
setlocal

set "SCRIPT_PATH_WIN=%~dp0start-codex-remote.sh"

wsl.exe bash -lc "script_path=$(wslpath -u \"$1\"); exec bash \"$script_path\"" _ "%SCRIPT_PATH_WIN%"
exit /b %ERRORLEVEL%

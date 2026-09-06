@echo off
setlocal

for %%I in ("%~dp0start-codex-remote.sh") do set "SCRIPT_PATH_WIN=%%~fI"

wsl.exe bash -lc "script_path=$(wslpath -u \"$1\"); exec /usr/bin/env bash \"$script_path\"" _ "%SCRIPT_PATH_WIN%"
exit /b %ERRORLEVEL%

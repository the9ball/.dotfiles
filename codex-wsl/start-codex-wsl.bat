@echo off
setlocal

set "SCRIPT_PATH_WIN=%~dp0start-codex-wsl.sh"
set "SCRIPT_PATH_WIN=%SCRIPT_PATH_WIN:\=/%"
for /f "delims=" %%I in ('wsl.exe wslpath -u "%SCRIPT_PATH_WIN%"') do set "SCRIPT_PATH_WSL=%%I"

if not defined SCRIPT_PATH_WSL (
  >&2 echo Failed to convert the WSL launcher path.
  exit /b 1
)

wsl.exe --exec /usr/bin/env bash "%SCRIPT_PATH_WSL%"
exit /b %ERRORLEVEL%

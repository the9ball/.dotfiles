@echo off
setlocal

set "SCRIPT_PATH_WIN=%~dp0start-codex-wsl.sh"
set "SCRIPT_PATH_WIN=%SCRIPT_PATH_WIN:\=/%"
set "SCRIPT_PATH_WSL="
set "SCRIPT_PATH_WSL_EXIT_CODE="
rem FOR /F masks the child command's errorlevel, so emit an internal status marker.
for /f "delims=" %%I in ('wsl.exe wslpath -u "%SCRIPT_PATH_WIN%" ^&^& echo(__STATUS_SUCCESS__ ^|^| echo(__STATUS_FAILURE__') do (
  for /f "tokens=1" %%J in ("%%I") do (
    if "%%J"=="__STATUS_SUCCESS__" set "SCRIPT_PATH_WSL_EXIT_CODE=0"
    if "%%J"=="__STATUS_FAILURE__" set "SCRIPT_PATH_WSL_EXIT_CODE=1"
    if not "%%J"=="__STATUS_SUCCESS__" if not "%%J"=="__STATUS_FAILURE__" if not defined SCRIPT_PATH_WSL set "SCRIPT_PATH_WSL=%%I"
  )
)

if not "%SCRIPT_PATH_WSL_EXIT_CODE%"=="0" (
  >&2 echo Failed to convert the WSL launcher path.
  exit /b 1
)

if not defined SCRIPT_PATH_WSL (
  >&2 echo Failed to convert the WSL launcher path.
  exit /b 1
)

wsl.exe --exec /usr/bin/env bash "%SCRIPT_PATH_WSL%"
exit /b %ERRORLEVEL%

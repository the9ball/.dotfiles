@echo off
rem Verify a generation cookie before attaching to a detached daily session.
setlocal EnableExtensions DisableDelayedExpansion
if not defined DAILY_RUNTIME_DIRECTORY exit /b 64
if not defined DAILY_RUN_NAME exit /b 64
set "DAILY_PSMUX_EXECUTABLE="
set "PSMUX_DATA_DIR=%DAILY_RUNTIME_DIRECTORY%\registry"
set "PSMUX_NO_WARM=1"
set "PSMUX_SESSION="
set "PSMUX_SESSION_NAME="
set "PSMUX_SESSION_DISPLAY_NAME="
set "PSMUX_REMOTE_ATTACH="
set "PSMUX_TARGET_SESSION="
set "PSMUX_ACTIVE="
set "TMUX="
set "TMUX_PANE="
set "DAILY_NAMESPACE=dotfiles-session1"
set "DAILY_SESSION=main"
set "DAILY_LOG=%DAILY_RUNTIME_DIRECTORY%\%DAILY_RUN_NAME%.monitor.log"
set "DAILY_STOP_FILE=%DAILY_RUNTIME_DIRECTORY%\stop.request"
title psmux-daily-%DAILY_RUN_NAME%
>>"%DAILY_LOG%" echo [%date% %time%] monitor-start
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -Command "$p=[System.Diagnostics.Process]::GetCurrentProcess(); 'session-check-pid='+$p.Id+' windows-session-id='+$p.SessionId+' stdin-redirected='+[Console]::IsInputRedirected+' stdout-redirected='+[Console]::IsOutputRedirected; if($p.SessionId -ne 1){exit 76}" >>"%DAILY_LOG%" 2>&1
if errorlevel 1 exit /b 76

rem Resolve the installed executable using this checkout's pinned aqua configuration.
for /f "delims=" %%P in ('%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -File "%~dp0resolve-psmux.ps1" 2^>^>"%DAILY_LOG%"') do set "DAILY_PSMUX_EXECUTABLE=%%P"
if not defined DAILY_PSMUX_EXECUTABLE exit /b 66

rem A failed create never gives this monitor ownership of an existing session.
:loop
if exist "%DAILY_STOP_FILE%" exit /b 0
if exist "%DAILY_RUNTIME_DIRECTORY%\recreate.request" goto refuse_recreation
set "DOTFILES_PSMUX_OWNER="
for /f "delims=" %%G in ('%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -NonInteractive -Command "[guid]::NewGuid().ToString('N')"') do set "DOTFILES_PSMUX_OWNER=%%G"
if not defined DOTFILES_PSMUX_OWNER exit /b 80
if exist "%DAILY_STOP_FILE%" exit /b 0
>>"%DAILY_LOG%" echo [%date% %time%] new-session-start
"%DAILY_PSMUX_EXECUTABLE%" -L %DAILY_NAMESPACE% new-session -d -s %DAILY_SESSION% -e DOTFILES_PSMUX_OWNER=%DOTFILES_PSMUX_OWNER% >>"%DAILY_LOG%" 2>&1
set "DAILY_CREATE_EXIT=%errorlevel%"
>>"%DAILY_LOG%" echo [%date% %time%] new-session-exit=%DAILY_CREATE_EXIT%
if not "%DAILY_CREATE_EXIT%"=="0" exit /b %DAILY_CREATE_EXIT%
>>"%DAILY_LOG%" echo [%date% %time%] attach-start
rem The helper retains the child handle and checks cancellation while attach blocks.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File "%~dp0wait-attach.ps1"
set "DAILY_ATTACH_EXIT=%errorlevel%"
>>"%DAILY_LOG%" echo [%date% %time%] attach-exit=%DAILY_ATTACH_EXIT%
if exist "%DAILY_STOP_FILE%" exit /b 0
if not "%DAILY_ATTACH_EXIT%"=="0" exit /b %DAILY_ATTACH_EXIT%
goto loop

:refuse_recreation
rem Date text can contain parentheses; keep its expansion outside a command block.
>>"%DAILY_LOG%" echo [%date% %time%] startup-refused recreate.request-present exit=81; inspect in-flight recreation before recovery
exit /b 81

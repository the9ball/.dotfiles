@echo off
rem Request cancellation; this file never detaches clients or kills a server.
setlocal EnableExtensions DisableDelayedExpansion
set "DAILY_RUNTIME_DIRECTORY=%LOCALAPPDATA%\Dotfiles\PsmuxDaily"
if not exist "%DAILY_RUNTIME_DIRECTORY%\" exit /b 2
>"%DAILY_RUNTIME_DIRECTORY%\stop.request" echo stop
exit /b %errorlevel%

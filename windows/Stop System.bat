@echo off
rem Stops the website and the server by the ports they listen on (3000 and 5176).
rem The database keeps running; it is a Windows service and uses little memory.
rem "Stop System.bat quiet" skips the final pause.
setlocal EnableExtensions
title Inventory System - Stop

echo Stopping the Inventory System...
call :stop_port 3000
call :stop_port 5176
echo The Inventory System is stopped.
echo.
if /i not "%~1"=="quiet" (
    ping -n 4 127.0.0.1 >nul
)
exit /b 0

rem Ends every process listening on TCP port %1.
:stop_port
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do (
    taskkill /pid %%P /f >nul 2>&1
)
exit /b 0

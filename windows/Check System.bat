@echo off
rem Shows in plain words whether each part of the Inventory System is running.
setlocal EnableExtensions
title Inventory System - Check
for %%I in ("%~dp0.") do set "ROOT=%%~fI"

echo Inventory System status
echo -----------------------
if not exist "%ROOT%\config\system.cmd" (
    echo  Setup ......... NOT DONE
    echo.
    echo  The system has not been set up. Run tools\Setup.bat first.
    goto :end
)
call "%ROOT%\config\system.cmd"

set "PROBLEM="
"%PGBIN%\pg_isready.exe" -q -h %PGHOST% -p %PGPORT%
if errorlevel 1 (
    echo  Database ...... NOT RUNNING
    set "PROBLEM=1"
) else (
    echo  Database ...... OK
)

netstat -ano | findstr /r /c:":5176 .*LISTENING" >nul
if errorlevel 1 (
    echo  Server ........ NOT RUNNING
    set "PROBLEM=1"
) else (
    echo  Server ........ OK
)

netstat -ano | findstr /r /c:":3000 .*LISTENING" >nul
if errorlevel 1 (
    echo  Website ....... NOT RUNNING
    set "PROBLEM=1"
) else (
    echo  Website ....... OK
)

echo.
if defined PROBLEM (
    echo  Something is not running. Double-click "Restart System".
    echo  If the Database stays NOT RUNNING, restart the computer.
) else (
    echo  Everything is running. Open http://localhost:3000 in the browser.
)
echo.
type "%ROOT%\VERSION.txt" 2>nul

:end
echo.
pause

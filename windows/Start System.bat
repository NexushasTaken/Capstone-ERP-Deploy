@echo off
rem Starts the Inventory System (database check, server, website) and opens it in the browser.
rem "Start System.bat quiet" skips the final pause (used by Restart System and Restore Database).
setlocal EnableExtensions
title Inventory System - Start
for %%I in ("%~dp0.") do set "ROOT=%%~fI"
if not exist "%ROOT%\config\system.cmd" goto :not_set_up
call "%ROOT%\config\system.cmd"
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

echo Starting the Inventory System...
echo.

rem --- 1. Database ------------------------------------------------------------
call :db_ready
if not errorlevel 1 goto :db_ok
rem PostgreSQL is a Windows service that starts with Windows; right after boot it may need a moment.
echo  - Waiting for the database...
call :wait_db 20
if errorlevel 1 goto :db_failed
:db_ok
echo  - Database ........ OK

rem --- 2. Server (backend) ----------------------------------------------------
call :listening 5176
if not errorlevel 1 goto :server_ok
echo  - Starting the server...
if exist "%ROOT%\logs\server.log" move /y "%ROOT%\logs\server.log" "%ROOT%\logs\server.old.log" >nul
start "Inventory System - Server (do not close)" /min /d "%ROOT%\backend" cmd /c "ERP.exe > "%ROOT%\logs\server.log" 2>&1"
call :wait_port 5176 60
if errorlevel 1 goto :server_failed
:server_ok
echo  - Server .......... OK

rem --- 3. Website (frontend) --------------------------------------------------
call :listening 3000
if not errorlevel 1 goto :website_ok
echo  - Starting the website...
if exist "%ROOT%\logs\website.log" move /y "%ROOT%\logs\website.log" "%ROOT%\logs\website.old.log" >nul
set "PORT=3000"
set "HOSTNAME=127.0.0.1"
set "BACKEND_API_URL=http://127.0.0.1:5176"
set "NODE_ENV=production"
rem keep-title.js stops Next.js from renaming this window to "next-server (vX)".
start "Inventory System - Website (do not close)" /min /d "%ROOT%\frontend" cmd /c ""%NODE%" -r "%ROOT%\tools\keep-title.js" server.js > "%ROOT%\logs\website.log" 2>&1"
call :wait_port 3000 30
if errorlevel 1 goto :website_failed
:website_ok
echo  - Website ......... OK

echo.
echo The Inventory System is running. Opening it in your browser...
start "" "http://localhost:3000"
if /i not "%~1"=="quiet" call :pause_briefly
exit /b 0

rem ============================================================================

:not_set_up
echo The Inventory System has not been set up on this computer yet.
echo Ask the person who installed it to run tools\Setup.bat first.
goto :fail

:db_failed
echo.
echo The DATABASE did not start.
echo Restart the computer and try again. If it still fails, see
echo "Troubleshooting" in the Installation Manual.
goto :fail

:server_failed
echo.
echo The SERVER did not start within 60 seconds.
echo Try "Restart System". If it still fails, send this file to the installer:
echo   %ROOT%\logs\server.log
goto :fail

:website_failed
echo.
echo The WEBSITE did not start within 30 seconds.
echo Try "Restart System". If it still fails, send this file to the installer:
echo   %ROOT%\logs\website.log
goto :fail

:fail
echo.
if /i not "%~1"=="quiet" pause
exit /b 1

rem Shows the result for a few seconds, then closes the window.
:pause_briefly
ping -n 4 127.0.0.1 >nul
exit /b 0

rem errorlevel 0 when something is listening on TCP port %1.
:listening
netstat -ano | findstr /r /c:":%~1 .*LISTENING" >nul
exit /b %errorlevel%

rem Waits up to %2 seconds for TCP port %1 to listen.
:wait_port
set /a "LEFT=%~2"
:wait_port_loop
call :listening %~1
if not errorlevel 1 exit /b 0
if %LEFT% LEQ 0 exit /b 1
set /a "LEFT-=1"
ping -n 2 127.0.0.1 >nul
goto :wait_port_loop

:db_ready
"%PGBIN%\pg_isready.exe" -q -h %PGHOST% -p %PGPORT%
exit /b %errorlevel%

rem Waits up to %1 seconds for the database to accept connections.
:wait_db
set /a "LEFT=%~1"
:wait_db_loop
call :db_ready
if not errorlevel 1 exit /b 0
if %LEFT% LEQ 0 exit /b 1
set /a "LEFT-=1"
ping -n 2 127.0.0.1 >nul
goto :wait_db_loop

@echo off
rem One-time setup of the Inventory System on this computer. Safe to run again: it keeps the data,
rem gives the app a new database password and sign-in key, and recreates the desktop shortcuts.
rem
rem Needs PostgreSQL and Node.js installed first (see the Installation Manual).
setlocal EnableExtensions
title Inventory System - Setup
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "PGPORT=5432"

echo ==========================================================
echo   Inventory System setup
echo   Folder: %ROOT%
echo ==========================================================
echo.

rem --- 1. Find PostgreSQL ------------------------------------------------------
set "PGBIN="
for /d %%D in ("%ProgramFiles%\PostgreSQL\*") do (
    if exist "%%D\bin\psql.exe" set "PGBIN=%%D\bin"
)
if not defined PGBIN (
    echo PostgreSQL was not found in "%ProgramFiles%\PostgreSQL".
    echo Install PostgreSQL first, then run this setup again.
    goto :fail
)
echo [1/7] PostgreSQL found: %PGBIN%

rem The service name only lets Start System start a stopped database. Setup does not need it, so a
rem failed lookup is not an error (failing here broke setup on a PC where PostgreSQL was running).
set "PGSERVICE="
for /f "tokens=2" %%S in ('sc query state^= all ^| findstr /r /c:"^SERVICE_NAME: postgresql"') do set "PGSERVICE=%%S"

rem Give a just-installed or just-booted PostgreSQL up to 30 seconds to accept connections.
set /a "LEFT=30"
:pg_wait
"%PGBIN%\pg_isready.exe" -q -h localhost -p %PGPORT%
if not errorlevel 1 goto :pg_ok
if %LEFT% LEQ 0 goto :pg_failed
if %LEFT%==30 echo       Waiting for PostgreSQL to answer on port %PGPORT%...
set /a "LEFT-=1"
ping -n 2 127.0.0.1 >nul
goto :pg_wait
:pg_ok

rem --- 2. Find Node.js ---------------------------------------------------------
set "NODE="
for /f "delims=" %%N in ('where node 2^>nul') do (
    if not defined NODE set "NODE=%%N"
)
if not defined NODE if exist "%ProgramFiles%\nodejs\node.exe" set "NODE=%ProgramFiles%\nodejs\node.exe"
if not defined NODE (
    echo Node.js was not found. Install Node.js LTS first, then run this setup again.
    goto :fail
)
"%NODE%" -e "process.exit(+process.versions.node.split('.')[0] >= 20 ? 0 : 1)"
if errorlevel 1 (
    echo Node.js is too old. Install the current Node.js LTS, then run this setup again.
    goto :fail
)
echo [2/7] Node.js found: %NODE%

rem --- 3. Stop a running copy, make new secrets -------------------------------
call "%ROOT%\Stop System.bat" quiet >nul
for /f "usebackq delims=" %%K in (`powershell -NoProfile -Command "$b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [BitConverter]::ToString($b).Replace('-','')"`) do set "DBPASS=%%K"
for /f "usebackq delims=" %%K in (`powershell -NoProfile -Command "$b = New-Object byte[] 64; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [BitConverter]::ToString($b).Replace('-','')"`) do set "JWTKEY=%%K"
if not defined DBPASS goto :secret_failed
if not defined JWTKEY goto :secret_failed
echo [3/7] New database password and sign-in key generated.

rem --- 4. Create the database --------------------------------------------------
echo.
echo [4/7] Creating the database.
echo       Type the password you chose for the "postgres" user when you
echo       installed PostgreSQL, then press Enter. (Nothing shows while you type.)
set /a "TRIES=0"
:db_retry
set "PGPASSWORD="
"%PGBIN%\psql.exe" -h localhost -p %PGPORT% -U postgres -d postgres -q -v pw=%DBPASS% -f "%ROOT%\tools\setup-db.sql"
if not errorlevel 1 goto :db_ok
set /a "TRIES+=1"
if %TRIES% GEQ 3 (
    echo That did not work three times. Check the "postgres" password and run this setup again.
    goto :fail
)
echo       That did not work. Try again.
goto :db_retry
:db_ok
echo       Database ready.

rem --- 5. Write the settings -------------------------------------------------
powershell -NoProfile -Command "(Get-Content -Raw (Join-Path $env:ROOT 'config\appsettings.template.json')).Replace('__DB_PASSWORD__', $env:DBPASS).Replace('__JWT_KEY__', $env:JWTKEY).Replace('__DB_PORT__', $env:PGPORT) | Set-Content -Encoding UTF8 -NoNewline (Join-Path $env:ROOT 'backend\appsettings.json')"
if errorlevel 1 goto :settings_failed
if not exist "%ROOT%\backend\appsettings.json" goto :settings_failed

set "SYS=%ROOT%\config\system.cmd"
> "%SYS%" echo @rem Written by tools\Setup.bat. Settings shared by the Inventory System scripts.
>>"%SYS%" echo set "PGBIN=%PGBIN%"
>>"%SYS%" echo set "PGSERVICE=%PGSERVICE%"
>>"%SYS%" echo set "PGHOST=localhost"
>>"%SYS%" echo set "PGPORT=%PGPORT%"
>>"%SYS%" echo set "PGDATABASE=ERP"
>>"%SYS%" echo set "PGUSER=erp"
>>"%SYS%" echo set "PGPASSWORD=%DBPASS%"
>>"%SYS%" echo set "NODE=%NODE%"
echo [5/7] Settings written.

rem --- 6. Create the tables ----------------------------------------------------
echo [6/7] Creating the tables and default data...
pushd "%ROOT%\database"
migrate.exe --connection "Host=localhost;Port=%PGPORT%;Database=ERP;User Id=erp;Password=%DBPASS%;"
set "MIGRATE_RESULT=%errorlevel%"
popd
if not "%MIGRATE_RESULT%"=="0" (
    echo Creating the tables FAILED. See the messages above.
    goto :fail
)

rem --- 7. Desktop shortcuts ----------------------------------------------------
powershell -NoProfile -Command "$shell = New-Object -ComObject WScript.Shell; $desktop = [Environment]::GetFolderPath('Desktop'); foreach ($name in 'Start System', 'Stop System', 'Restart System', 'Check System', 'Backup Database') { $link = $shell.CreateShortcut((Join-Path $desktop ($name + '.lnk'))); $link.TargetPath = (Join-Path $env:ROOT ($name + '.bat')); $link.WorkingDirectory = $env:ROOT; $link.Save() }"
echo [7/7] Desktop shortcuts created.

echo.
echo ==========================================================
echo   Setup finished.
echo.
echo   Sign in with:   owner@inventory.local
echo   Password:       mypassword
echo.
echo   Change the passwords of both default accounts
echo   (owner@inventory.local and secretary@inventory.local)
echo   right after the first sign-in.
echo ==========================================================
echo.
choice /c YN /m "Start the system now"
if errorlevel 2 exit /b 0
call "%ROOT%\Start System.bat"
exit /b 0

:pg_failed
echo PostgreSQL is not answering on port %PGPORT%. It said:
"%PGBIN%\pg_isready.exe" -h localhost -p %PGPORT%
echo Check that PostgreSQL was installed with port %PGPORT%, restart the computer,
echo then run this setup again.
goto :fail

:secret_failed
echo Could not generate the database password. Check that PowerShell is available.
goto :fail

:settings_failed
echo Could not write backend\appsettings.json. Check that the folder is not read-only.
goto :fail

:fail
echo.
echo Setup did NOT finish.
pause
exit /b 1

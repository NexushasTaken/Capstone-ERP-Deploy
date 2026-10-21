@echo off
rem Saves a copy of all data to Documents\Inventory Backups\ERP-<date>-<time>.backup.
setlocal EnableExtensions
title Inventory System - Backup
for %%I in ("%~dp0.") do set "ROOT=%%~fI"
if not exist "%ROOT%\config\system.cmd" (
    echo The Inventory System has not been set up yet. Run tools\Setup.bat first.
    goto :fail
)
call "%ROOT%\config\system.cmd"

for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')"`) do set "DOCS=%%D"
set "BACKUPS=%DOCS%\Inventory Backups"
if not exist "%BACKUPS%" mkdir "%BACKUPS%"
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%T"
set "FILE=%BACKUPS%\ERP-%STAMP%.backup"

echo Backing up the database...
"%PGBIN%\pg_dump.exe" --format=custom --no-owner --no-privileges --file="%FILE%"
if errorlevel 1 (
    echo.
    echo The backup FAILED. Check that the system is running with "Check System",
    echo then try again.
    if exist "%FILE%" del "%FILE%"
    goto :fail
)

echo.
echo Backup saved:
echo   %FILE%
echo.
echo Copy this file to a USB drive or cloud storage now and then,
echo so a copy survives if this computer breaks.
explorer /select,"%FILE%"
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1

@echo off
rem Replaces ALL current data with a backup made by "Backup Database".
rem Usage: double-click and pick the file, or drag a .backup file onto this script.
rem The current data is backed up first (ERP-before-restore-<date>.backup), in case the restore goes wrong.
setlocal EnableExtensions
title Inventory System - Restore Database
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
if not exist "%ROOT%\config\system.cmd" (
    echo The Inventory System has not been set up yet. Run tools\Setup.bat first.
    goto :fail
)
call "%ROOT%\config\system.cmd"

for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')"`) do set "DOCS=%%D"
set "BACKUPS=%DOCS%\Inventory Backups"
if not exist "%BACKUPS%" mkdir "%BACKUPS%"

rem --- Pick the backup file ----------------------------------------------------
set "FILE=%~1"
if defined FILE goto :have_file
echo Choose the backup file to restore...
for /f "usebackq delims=" %%F in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.InitialDirectory = $env:BACKUPS; $d.Filter = 'Inventory backups (*.backup)|*.backup'; if ($d.ShowDialog() -eq 'OK') { $d.FileName }"`) do set "FILE=%%F"
if not defined FILE (
    echo No file chosen. Nothing was changed.
    goto :fail
)
:have_file
rem No ( ) block here: a file name like "ERP (1).backup" would end it early.
if exist "%FILE%" goto :file_ok
echo File not found: %FILE%
goto :fail
:file_ok

echo.
echo   Backup to restore:  %FILE%
echo.
echo   WARNING: this REPLACES ALL CURRENT DATA (products, stock, orders, sales,
echo   accounts) with the data in this backup. Anything added since that backup
echo   was made will be gone from the system.
echo.
set "ANSWER="
set /p "ANSWER=Type YES in capital letters to continue: "
if not "%ANSWER%"=="YES" (
    echo Cancelled. Nothing was changed.
    goto :fail
)

rem --- Stop, keep a copy of the current data ---------------------------------
echo.
echo Stopping the system...
call "%ROOT%\Stop System.bat" quiet >nul

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%T"
set "SAFETY=%BACKUPS%\ERP-before-restore-%STAMP%.backup"
echo Saving the current data first...
"%PGBIN%\pg_dump.exe" --format=custom --no-owner --no-privileges --file="%SAFETY%"
if errorlevel 1 (
    echo Could not back up the current data, so the restore was stopped. Nothing was changed.
    goto :fail
)

rem --- Restore into a fresh, empty database ----------------------------------
echo Restoring...
"%PGBIN%\dropdb.exe" --maintenance-db=postgres --if-exists --force ERP
if errorlevel 1 goto :restore_failed
"%PGBIN%\createdb.exe" --maintenance-db=postgres --encoding=UTF8 --template=template0 ERP
if errorlevel 1 goto :restore_failed
"%PGBIN%\pg_restore.exe" --no-owner --no-privileges --exit-on-error --dbname=ERP "%FILE%"
if errorlevel 1 goto :restore_failed
"%PGBIN%\psql.exe" -q -d ERP -f "%ROOT%\tools\reset-sequences.sql"
if errorlevel 1 goto :restore_failed

echo.
echo Restore finished. Starting the system...
echo.
call "%ROOT%\Start System.bat"
exit /b 0

:restore_failed
echo.
echo The restore FAILED. The data from before the restore was saved here:
echo   %SAFETY%
echo Run this tool again and choose that file to put it back.
goto :fail

:fail
echo.
pause
exit /b 1

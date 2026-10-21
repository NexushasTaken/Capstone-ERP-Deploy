@echo off
rem Stops the Inventory System, then starts it again.
setlocal EnableExtensions
title Inventory System - Restart
call "%~dp0Stop System.bat" quiet
ping -n 3 127.0.0.1 >nul
call "%~dp0Start System.bat" %1

@echo off
:: maravento.com

REM -------------------------------------------------------
REM Driver Backup and Restore
REM
REM Drivers are saved to / restored from the folder below.
REM To use a different path, change the DEFAULT variable.
REM -------------------------------------------------------

setlocal enabledelayedexpansion

set "DEFAULT=%HOMEDRIVE%\DriversBackup"

:check_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:check_os
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo Windows Version Detected: %VERSION%
if NOT "%VERSION%" == "10.0" (
    echo OS Incompatible
    echo.
    pause
    exit /b 1
)
if NOT EXIST "%PROGRAMFILES(X86)%" (
    echo OS Incompatible
    echo.
    pause
    exit /b 1
)

:check_path
if not exist "%DEFAULT%" mkdir "%DEFAULT%"

:menu
cls
echo.
echo Driver Backup and Restore
echo Folder: %DEFAULT%
echo.
echo 1. Backup
echo 2. Restore
echo 3. Exit
echo.
set /p choice="Enter option (1-3): "

if "%choice%"=="1" goto :backup
if "%choice%"=="2" goto :restore
if "%choice%"=="3" goto :end
echo.
echo Invalid option.
timeout /t 2 >nul
goto :menu


REM -------------------------------------------------------
REM BACKUP - Export installed drivers using DISM
REM -------------------------------------------------------
:backup
cls
echo.
echo Backing up drivers to: %DEFAULT%
echo.
dism /online /export-driver /destination:"%DEFAULT%"
echo.
if %errorlevel% neq 0 (
    echo ERROR: Backup failed.
) else (
    echo Done.
)
echo.
pause
goto :menu


REM -------------------------------------------------------
REM RESTORE - Install drivers from folder using pnputil
REM -------------------------------------------------------
:restore
cls
echo.
echo Restoring drivers from: %DEFAULT%
echo.
pnputil /add-driver "%DEFAULT%\*.inf" /subdirs /install
echo.
echo Done. Drivers already installed in the system were skipped.
echo.
pause
goto :menu


:end
endlocal
exit
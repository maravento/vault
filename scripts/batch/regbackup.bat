@echo off
:: by maravento.com

:: Script to Regedit Backup
:: for win 7/10/11

REM Checking Privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedexpansion

REM services
echo.
echo Regedit Backup
echo.
echo Choose an option:
echo 1. Backup
echo 2. Exit
echo.
set /p choice="Enter the number (1 or 2): "

REM Validate user input and perform the selected action
if "%choice%"=="1" (
    goto backup
) else if "%choice%"=="2" (
    goto end
) else (
    goto invalid
)

:backup
set DEST=%HOMEDRIVE%\RegBackup

if not exist %DEST% (
    mkdir %DEST%
    echo.
    echo Creating directory %DEST%...
) else (
    echo.
    echo Using existing directory %DEST%...
)

for /F "tokens=2-4 delims=/ " %%i in ('date /t') do set yyyymmdd=%%k%%j%%i
set filebk=RegBk_%yyyymmdd%.reg

echo.
echo Exporting Windows Registry to %DEST%\%filebk%
start /wait %windir%\regedit.exe /s /y /e %DEST%\%filebk%

if exist %DEST%\* (
    attrib /d /s -r -h -s %DEST%\*
)
goto end

:end
echo Done
exit /b
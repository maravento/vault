@echo off
:: maravento.com

:: Autorun Disable
:: For Windows 10/11

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"

echo.
echo Checking Autorun status...
reg query "%KEY%" /v NoDriveTypeAutoRun 2>nul | find "0xff" >nul
if %errorlevel%==0 (
    echo.
    echo Autorun is already disabled.
) else (
    reg add "%KEY%" /v NoDriveTypeAutoRun /t REG_DWORD /d 0xFF /f >nul
    if %errorlevel%==0 (
        echo.
        echo Autorun disabled successfully.
        echo Restart your PC to apply the change.
    ) else (
        echo.
        echo ERROR: Failed to write registry value.
    )
)
echo.
pause

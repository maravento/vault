@echo off
:: by maravento.com

:: script to boot PC in mode: safe with network/safe minimal/normal
:: for win 7/8/10/11
:: Run with Administrador Privileges

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

REM safe with network/safe minimal/normal mode
echo.
echo Start PC in the following modes:
echo.
echo 1. Safe Boot Minimal
echo 2. Safe Boot with Network
echo 3. Normal Boot
echo 4. Exit
echo.
set /p choice="Enter the number (1, 2, 3 or 4): "

REM Validate user input and perform the selected action
if "%choice%"=="1" (
    goto safe
) else if "%choice%"=="2" (
    goto safenet
) else if "%choice%"=="3" (
    goto normal
) else (
    goto exit
)

:safe
bcdedit /set {default} safeboot minimal
goto reboot

:safenet
bcdedit /set {default} safeboot network
goto reboot

:normal
bcdedit /deletevalue {default} safeboot
goto reboot

:reboot
shutdown -r -f -t 4
exit

:exit
echo Done
exit

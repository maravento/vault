@echo off
:: maravento.com

:: script to boot PC in mode: safe with network/safe minimal/normal
:: for win 7/8/10/11
:: Run with Administrador Privileges

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedexpansion
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
call :check_bitlocker
bcdedit /set {default} safeboot minimal
if errorlevel 1 (
    echo [ERROR] bcdedit failed. Aborting reboot.
    pause
    goto exit
)
goto reboot

:safenet
call :check_bitlocker
bcdedit /set {default} safeboot network
if errorlevel 1 (
    echo [ERROR] bcdedit failed. Aborting reboot.
    pause
    goto exit
)
goto reboot

:normal
bcdedit /deletevalue {default} safeboot
if errorlevel 1 (
    echo [ERROR] bcdedit failed. Aborting reboot.
    pause
    goto exit
)
goto reboot

:check_bitlocker
manage-bde -status %systemdrive% | find "Protection On" >nul 2>&1
if not errorlevel 1 (
    echo.
    echo WARNING: BitLocker is ON for %systemdrive%.
    echo Changing the boot entry can trigger BitLocker Recovery on next boot.
    set /p bl_confirm="Suspend BitLocker protection for one reboot? (y/n): "
    if /i "!bl_confirm!"=="y" (
        manage-bde -protectors -disable %systemdrive% -RebootCount 1 >nul 2>&1
    )
)
exit /b

:reboot
shutdown -r -f -t 4
exit /b

:exit
echo Done
exit /b

@echo off
:: by maravento.com

:: WMIC Add/Remove
:: For Windows 10/11

setlocal EnableDelayedExpansion

:check_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:check_wmic
wmic.exe /? >nul 2>&1
if %errorlevel% equ 0 (
    set "wmic_status=installed"
) else (
    set "wmic_status=not installed"
)

:menu
cls
echo.
echo ============================
echo        STATUS OF WMIC        
echo ============================
echo.
echo WMIC status: !wmic_status!
echo.
echo Available options:
echo.
echo [1] Enable WMIC
echo [2] Disable WMIC
echo [3] Exit
echo.
set /p "opcion=Select an option (1-3): "

if "%opcion%"=="1" (
    if "!wmic_status!"=="installed" (
        echo.
        echo WMIC is already installed
        pause
        goto menu
    ) else (
        echo.
        echo Installing WMIC...
        echo This process may take several minutes...
        echo.
        DISM /Online /Add-Capability /CapabilityName:WMIC~~~~ /NoRestart
        if !errorlevel! equ 0 (
            echo.
            echo WMIC has been installed successfully
            set "wmic_status=installed"
        ) else (
            echo.
            echo Error installing WMIC
        )
        pause
        goto menu
    )
)

if "%opcion%"=="2" (
    if "!wmic_status!"=="not installed" (
        echo.
        echo WMIC is already uninstalled
        pause
        goto menu
    ) else (
        echo.
        echo Uninstalling WMIC...
        echo This process may take several minutes...
        echo.
        DISM /Online /Remove-Capability /CapabilityName:WMIC~~~~ /NoRestart
        if !errorlevel! equ 0 (
            echo.
            echo WMIC has been successfully uninstalled
            set "wmic_status=not installed"
        ) else (
            echo.
            echo Error uninstalling WMIC
        )
        pause
        goto menu
    )
)

if "%opcion%"=="3" (
    exit /b
)

goto menu
@echo off
:: by maravento.com

:: Script to Activate or Deactivate SMB1 protocol
:: for win 10/11

:: chcp 65001 >nul
set "psScriptPath=%USERPROFILE%\Desktop\smb1.ps1"

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

REM Activate or Deactivate SMB1
echo.
echo SMB1 Protocol for Windows 10/11
echo.
echo Choose an option:
echo 1. Activate SMB1
echo 2. Deactivate SMB1
echo.
set /p choice="Enter the number (1 or 2): "

if "%choice%"=="1" (
    REM Create the PowerShell file to activate SMB1
    echo Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart > %psScriptPath%
) else if "%choice%"=="2" (
    REM Create the PowerShell file to deactivate SMB1
    echo Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart > %psScriptPath%
) else (
    REM Invalid choice
    echo Invalid choice. Exiting...
    timeout /t 0 >nul
    exit /b
)

REM Run the PowerShell file
powershell -ExecutionPolicy Bypass -File %psScriptPath% 2>nul

REM Pause before restarting the "Server" service
timeout /t 5 >nul

REM Loop para intentar reiniciar el servicio LanmanServer
for /l %%i in (1,2,3) do (
    echo Attempt %%i
    net stop LanmanServer /y >nul 2>&1
    net start LanmanServer >nul 2>&1
    REM Verificar si el reinicio fue exitoso
    powershell -ExecutionPolicy Bypass -Command "Get-Service -Name LanmanServer | Where-Object { $_.Status -eq 'Running' }" >nul 2>&1
    if %errorlevel% equ 0 (
        echo LanmanServer service restarted successfully
        goto end
    ) else (
        powershell -ExecutionPolicy Bypass -Command "Restart-Service -Name LanmanServer -Force" >nul 2>&1
        REM Verificar si el reinicio fue exitoso
        powershell -ExecutionPolicy Bypass -Command "Get-Service -Name LanmanServer | Where-Object { $_.Status -eq 'Running' }" >nul 2>&1
        if %errorlevel% equ 0 (
            echo LanmanServer service restarted successfully
            goto end
        )
    )
)

echo Failed to restart LanmanServer service

:end
REM Delete the PowerShell file
del %psScriptPath%
echo.
echo SMB1 completed
echo.
echo It is recommended to restart
echo Se recomienda reiniciar
echo.
ECHO Off
SET /P yesno=Do you want to reboot? [Y/N]:
IF "%yesno%"=="y" GOTO restart
IF "%yesno%"=="Y" GOTO restart
IF "%yesno%"=="n" GOTO final
IF "%yesno%"=="N" GOTO final

:restart
shutdown -r -f -t 4
GOTO EOF
:final
timeout /t 0 >nul
:EOF
exit
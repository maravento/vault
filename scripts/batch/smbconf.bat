@echo off
:: maravento.com

:: Script to SMB Config
:: for win 10/11

:: Description:
:: Activate or Deactivate SMB1 protocol
:: SMB signing
:: Disables mandatory SMB signing and enables insecure guest access in the Windows SMB client

:: How To Run:
:: For Windows 10/11: Double click and accept privileges
:: In case it fail do the following:
:: 1. Open "Windows PowerShell" as "Administrator".
:: 2. Run the following command to allow script execution:
::		Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force
:: 3. Now run `smbconf.bat` with Double click and accept privileges
:: 4. Once the script has finished, restore the execution policy to a more secure setting by running:
:: 		Set-ExecutionPolicy Restricted -Scope CurrentUser -Force

setlocal enabledelayedexpansion

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: chcp 65001 >nul
set "psScriptPath=%USERPROFILE%\Desktop\smb1.ps1"

echo.
echo SMB Config
echo.
echo Choose an option:
echo 1. Activate SMB signing
echo 2. Restore Default SMB signing
echo 3. Disable SMB Signing and Enable Insecure Guest Access
echo 4. Activate SMB1
echo 5. Deactivate SMB1
echo 6. Exit
echo.
set /p choice="Enter the number (1, 2, 3, 4, 5 or 6): "

REM Validate user input and perform the selected action

if "%choice%"=="1" goto :1
if "%choice%"=="2" goto :2
if "%choice%"=="3" goto :3
if "%choice%"=="4" goto :4
if "%choice%"=="5" goto :5
if "%choice%"=="6" goto end
goto :invalid
echo %choice% | findstr /r "^[1-6]$" >nul
if %errorlevel% neq 0 goto :invalid

:1
REM Activate SMB signing
reg add "HKLM\System\CurrentControlSet\services\LanmanWorkstation\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "EnableSecuritySignature" /t REG_DWORD /d 1 /f >nul 2>&1
echo SMB signing completed
echo Reboot to apply changes
goto end

:2
REM SMB signing restored
reg add "HKLM\System\CurrentControlSet\services\LanmanWorkstation\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "EnableSecuritySignature" /t REG_DWORD /d 0 /f >nul 2>&1
echo SMB signing restored
echo Reboot to apply changes
goto end

:3
REM disables mandatory SMB signing and enables insecure guest access in the Windows SMB client
powershell Set-SmbClientConfiguration -RequireSecuritySignature $false -Confirm:$false
powershell Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Confirm:$false
echo Successful setup
echo Reboot to apply changes
goto end

:4
REM Create the PowerShell file to activate SMB1
echo Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart > %psScriptPath%
call :RestartSMBService
exit /b

:5
REM Create the PowerShell file to deactivate SMB1
echo Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart > %psScriptPath%
call :RestartSMBService
exit /b

:RestartSMBService
REM Run the PowerShell file
powershell -ExecutionPolicy Bypass -File %psScriptPath% >nul 2>&1
REM Pause before restarting the "Server" service
timeout /t 5 >nul
REM LanmanServer
for /l %%i in (1,1,3) do (
    echo Attempt %%i
    net stop LanmanServer /y >nul 2>&1
    net start LanmanServer >nul 2>&1
    REM check service
    powershell -ExecutionPolicy Bypass -Command "if ((Get-Service -Name LanmanServer).Status -eq 'Running') { exit 0 } else { exit 1 }"
    if !errorlevel! equ 0 (
        echo LanmanServer service restarted successfully
        goto cleanup
    ) else (
        powershell -ExecutionPolicy Bypass -Command "Restart-Service -Name LanmanServer -Force" >nul 2>&1
        REM check restart
        powershell -ExecutionPolicy Bypass -Command "if ((Get-Service -Name LanmanServer).Status -eq 'Running') { exit 0 } else { exit 1 }"
        if !errorlevel! equ 0 (
            echo LanmanServer service restarted successfully
            goto cleanup
        )
    )
)
echo Failed to restart LanmanServer service. Please restart the service manually
:cleanup
REM Delete the PowerShell file
if exist %psScriptPath% del %psScriptPath%
echo SMB1 completed
echo Reboot to apply changes
goto end
exit /b

:invalid
REM Invalid choice
echo Invalid choice. Exiting...
timeout /t 1 >nul
exit /b

:end
echo Press any key to exit.
pause >nul
exit /b

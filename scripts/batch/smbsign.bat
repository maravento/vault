@echo off
:: by maravento.com

:: Script to SMB signing
:: https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/overview-server-message-block-signing
:: for win 10/11

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

REM SMB signing
echo.
echo SMB signing for Windows 10/11
echo.
echo Choose an option:
echo 1. Activate SMB signing
echo 2. Restore Default
echo 3. Exit
echo.
set /p choice="Enter the number (1, 2, or 3): "

if "%choice%"=="1" goto activate
if "%choice%"=="2" goto restore
if "%choice%"=="3" goto end
goto invalid

REM Validate user input and perform the selected action
if "%choice%"=="1" (
    goto activate
) else if "%choice%"=="2" (
    goto restore
) else if "%choice%"=="3" (
    goto end
) else (
    goto invalid
)

:activate
reg add "HKLM\System\CurrentControlSet\services\LanmanWorkstation\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "EnableSecuritySignature" /t REG_DWORD /d 1 /f >nul 2>&1
echo SMB signing completed.
goto end

:restore
reg add "HKLM\System\CurrentControlSet\services\LanmanWorkstation\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\System\CurrentControlSet\services\LanmanServer\Parameters" /v "EnableSecuritySignature" /t REG_DWORD /d 0 /f >nul 2>&1
echo SMB signing restored.
goto end

:invalid
echo Invalid choice. Exiting...
goto end

:end
echo Press any key to exit.
pause >nul
exit /b

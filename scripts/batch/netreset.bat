@echo off
:: maravento.com

:: Force reset proxy and network interfaces
:: for win 7/8/10/11

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedexpansion

:: checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -command "Start-Process '%comspec%' -ArgumentList '/c \"%~dpnx0\"' -Verb RunAs"
    exit /b
)

:: It asks if you want to continue with the reset
echo.
echo NET RESET
echo.
set /p "choice=The network parameters will be reset. Do you wish to continue? [Y/N]: "

:: Check the user's response
if /i "%choice%"=="Y" (
    echo Procedure with the reset
) else (
    echo There is no selection. End of script
    exit /b
)

:: FixNet
echo.
set "keys=HKCU HKLM"
for %%k in (%keys%) do (
    echo Delete Keys...
    reg delete "%%k\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f 2>nul >nul
    reg delete "%%k\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /f 2>nul >nul
    reg delete "%%k\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL /f 2>nul >nul
    reg delete "%%k\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v MigrateProxy /f 2>nul >nul
    reg delete "%%k\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoDetect /f 2>nul >nul
    reg delete "%%k\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /f 2>nul >nul
    reg delete "%%k\SYSTEM\ControlSet001\Services\iphlpsvc\Parameters\ProxyMgr" /va /f 2>nul >nul
    echo Add Proxy Key...
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoDetect /t REG_DWORD /d 1 /f >nul
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "<local>" /f >nul
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
    reg add "HKLM\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxySettingsPerUser /t REG_DWORD /d 1 /f >nul
)

for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "Get-NetAdapter | Select-Object -ExpandProperty Name"`) do (
    set "interface=%%a"
    setlocal disabledelayedexpansion
    echo Configuring interface: %interface%
    endlocal
    setlocal enabledelayedexpansion
    echo Reset IP...
    netsh interface ip set address name="!interface!" dhcp >nul
    echo Reset DNS...
    netsh interface ip set dnsservers name="!interface!" dhcp >nul
    echo Reset Proxy...
    netsh winhttp reset autoproxy >nul
    netsh winhttp import proxy source=ie >nul
    set http_proxy=
    set https_proxy=
    echo TCP Window Auto-Tuning Enable
    netsh int tcp set global autotuninglevel=normal >nul
    echo RSS Enable...
    netsh int tcp set global rss=enabled >nul
    echo Flush...
    ipconfig /flushdns >nul
    echo Reset winsock
    netsh winsock reset >nul
    echo Reset all...
    netsh int ip reset all 2>nul >nul
    echo Reset ie
    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 4351
    echo GPU update
    gpupdate /force
    echo.
    endlocal
)

:: Restart
set /p "choice=Reboot is required. Do you wish to continue? [Y/N]: "

if /i "!choice!"=="Y" (
    echo Restart...
    shutdown /r /f /t 0
) else (
    echo Exit.
)
endlocal

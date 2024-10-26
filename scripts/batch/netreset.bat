@echo off
:: by maravento.com

:: Force reset proxy and network interfaces
:: for win 7/8/10/11

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedexpansion

SET "TEXT1[0]=The network parameters will be reset. Do you wish to continue?"
SET "TEXT1[1]=Se van a resetear los parametros de red. Desea continuar?"
SET "TEXT2[0]=Procedure with the reset"
SET "TEXT2[1]=Procediento con el reset"
SET "TEXT3[0]=There is no selection. End of script"
SET "TEXT3[1]=No hay seleccion. Fin del script"
SET "TEXT4[0]=Configuring interface:"
SET "TEXT4[1]=Configurando interfaz:"
SET "TEXT5[0]=Reboot is required. Do you wish to continue?"
SET "TEXT5[1]=Es necesario reiniciar. Desea continuar?"

SET "KEY=HKEY_CURRENT_USER\Control Panel\International"
FOR /F "usebackq tokens=3" %%a IN (`reg query "%KEY%" ^| find /i "LocaleName"`) do set Language=%%a
SET "UL=%LANGUAGE:~0,2%"
IF "%UL%" EQU "en" (SET /A L=0)
IF "%UL%" EQU "es" (SET /A L=1)

:: checking privileges / verificando privilegios
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -command "Start-Process '%comspec%' -ArgumentList '/c \"%~dpnx0\"' -Verb RunAs"
    exit /b
)

:: It asks if you want to continue with the reset / Pregunta si desea continuar con el reset
echo.
echo NET RESET
echo.
set /p "choice=!TEXT1[%L%]! [Y/N]: "

:: Check the user's response / Verifica la respuesta del usuario
if /i "%choice%"=="Y" (
    echo !TEXT2[%L%]!
) else (
    echo !TEXT3[%L%]!
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

for /F "skip=3 tokens=3*" %%a in ('netsh interface show interface') do (
    if not "%%b"=="" (
        set "interface=%%b"
        echo !TEXT4[%L%]! !interface!
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
    )
)

:: Restart
set /p "choice=!TEXT5[%L%]! [Y/N]: "

if /i "!choice!"=="Y" (
    echo Restart...
    shutdown /r /f /t 0
) else (
    echo Exit.
)
endlocal
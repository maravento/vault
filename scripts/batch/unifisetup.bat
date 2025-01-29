@echo off
:: by maravento.com

:: UniFi Network Server Setup + Java Adoptium as a Service
:: For Windows 10/11

:: How to Use:
:: 1. Download this script to "%HOMEDRIVE%\unifi" (If it doesn't exist, create it)
:: 2. Download the latest version of UniFi Network Server to "%HOMEDRIVE%\unifi"
::    URL: https://ui.com/download/releases/network-server
:: 3. Download the latest x64 MSI version of Java Adoptium to "%HOMEDRIVE%\unifi"
::    URL: https://adoptium.net/en-GB/temurin/releases/?version=21&os=windows&arch=x64
:: 4. Open CMD with privileges and run:
::    cd "%HOMEDRIVE%\unifi" && unifisetup.bat
:: 5. Reboot

:: Access UniFi Network Server: 
:: https://localhost:8443
:: To set access by IP address, edit the file:
:: "%UserProfile%\Ubiquiti UniFi\data\system.properties"
:: And add the following line with the IP of the PC/Server where Unifi is installed. E.g:
:: system_ip=192.168.1.10
:: You will now be able to access:
:: https://192.168.1.10:8443

setlocal enabledelayedexpansion

:: Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Source folder path
set "installdir=%HOMEDRIVE%\unifi"
:: Check Install Path
cd /d "%installdir%" || (
    echo Directory not found: %installdir%
    exit /b 1
)

:Menu
cls
echo.
echo Unifi Network Server as a Service
echo.
echo 1. Install Unifi + Java Adoptium
echo 2. Remove Unifi + Java Adoptium
echo 3. Exit
echo.
echo Write your number (1, 2, 3) and
echo Press ENTER
echo.
set /p var=
if "%var%"=="1" goto :install
if "%var%"=="2" goto :remove
if "%var%"=="3" exit /0
echo Invalid option. Please select a valid number from 1 to 8
pause
goto :Menu

:install

:check_java
where java >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=3" %%v in ('java -version 2^>^&1') do (
        echo Java Version: %%v
        echo Uninstall java and run the script again
        exit /b 1
    )
)

:CheckUniFi
if exist "%UserProfile%\Ubiquiti UniFi\" (
    echo The folder "%UserProfile%\Ubiquiti UniFi\" already exists
    echo Uninstall Unifi, delete folder and run the script again
    exit /b 1
)

:install_pack
echo.
echo Installing Unifi...
"UniFi-installer.exe" /S
:wait_for_install
timeout /t 10 /nobreak >nul
tasklist /fi "imagename eq UniFi-installer.exe" 2>nul | find /i "UniFi-installer.exe" >nul
if %errorlevel% equ 0 (
    goto wait_for_install
)
mkdir "%UserProfile%\Ubiquiti UniFi\data" 2>nul
(
echo debug.device=warn
echo debug.mgmt=warn
echo debug.sdn=warn
echo debug.setting_preference=auto
echo debug.system=warn
) > "system.properties"
copy "system.properties" "%UserProfile%\Ubiquiti UniFi\data" >nul 2>&1

echo.
echo Installing Java Adoptium...
set "latest_msi="
for /f "delims=" %%f in ('dir /b /a-d /o-d /t:c "OpenJDK*-jre_x64_windows_hotspot_*.msi" 2^>nul') do (
    set "latest_msi=%%f"
    goto :install_java
)
echo MSI not found in %installdir%
exit /b 1
:install_java
:: OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.msi
start /wait msiexec /i "%latest_msi%" ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR="%ProgramFiles%\Temurin\" /quiet >nul 2>&1

echo.
echo Setup Unifi as a Service...
cd "%UserProfile%\Ubiquiti UniFi\" || (
	echo Failed to change directory to "%UserProfile%\Ubiquiti UniFi\"
	exit /b 1
)
set JAVA_PATH="%ProgramFiles%\Temurin\bin\java.exe"
%JAVA_PATH% -jar lib\ace.jar startsvc &
%JAVA_PATH% -jar lib\ace.jar installsvc

echo.
echo Add Firewall Rules...
netsh advfirewall firewall add rule name="Unifi TCP in 8080,8443,8880,8843" protocol=TCP dir=in localport=8080,8443,8880,8843 action=allow >nul 2>&1
netsh advfirewall firewall add rule name="Unifi TCP out 8080,8443,8880,8843" protocol=TCP dir=out localport=8080,8843 action=allow >nul 2>&1
netsh advfirewall firewall add rule name="Unifi UDP in 10001,3478" protocol=UDP dir=in localport=10001,3478 action=allow >nul 2>&1
netsh advfirewall firewall add rule name="Unifi UDP out 10001,3478" protocol=UDP dir=out localport=10001,3478 action=allow >nul 2>&1

echo.
echo Done
echo Access https://localhost:8443
echo Reboot your system
pause
exit

:remove
echo.
echo Delete Firewall Rules...
netsh advfirewall firewall delete rule name="Unifi TCP in 8080,8443,8880,8843" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi TCP out 8080,8443,8880,8843" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP in 10001,3478" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP out 10001,3478" >nul 2>&1

echo.
echo Uninstall UniFi...
net stop UniFi >nul 2>&1
cd "%UserProfile%\Ubiquiti UniFi\" || (
	echo Failed to change directory to "%UserProfile%\Ubiquiti UniFi\"
	exit /b 1
)
set JAVA_PATH="%ProgramFiles%\Temurin\bin\java.exe"
%JAVA_PATH% -jar lib\ace.jar uninstallsvc

set "uninstall_path=%UserProfile%\Ubiquiti UniFi\Uninstall.exe"
if exist "%uninstall_path%" (
    "%uninstall_path%" /S
    :wait_for_uninstall
    timeout /t 10 /nobreak >nul
    tasklist /fi "imagename eq Uninstall.exe" 2>nul | find /i "Uninstall.exe" >nul
    if %errorlevel% equ 0 (
        goto wait_for_uninstall
    )
    rd /s /q "%UserProfile%\Ubiquiti UniFi" >nul 2>&1
    goto :msi
)
echo UniFi Uninstaller not found
exit /b 1

:msi
echo.
echo Uninstall Java Adoptium...
cd /d "%installdir%"
set "latest_msi="
for /f "delims=" %%f in ('dir /b /a-d /o-d /t:c "OpenJDK*-jre_x64_windows_hotspot_*.msi" 2^>nul') do (
    set "latest_msi=%%f"
    goto :remove_java
)
echo Java MSI file not found in %installdir%.
exit /b 1
:remove_java
start /wait msiexec /x "%latest_msi%" /quiet

echo.
echo Done
echo Reboot your system
pause
exit

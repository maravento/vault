@echo off
:: by maravento.com

:: UniFi Network Server Setup + Java Adoptium as a Service
:: For Windows 10/11

:: Dependencies:
:: - curl
::   Microsoft Windows 10 (build 17063 or later) and Windows 11 have CURL installed by default.
::   If you don't have curl installed, you can download it from:
::   https://curl.se/download.html

:: How to Use:
:: - Download the script and open it with notepad
:: - Modify "version=9.0.108" with the version number to install
:: - Run it by double-clicking and accepting the privilege elevation
:: - Follow the on-screen instructions

:: UniFi Network Server Latest Version (variable version):
:: 1. Check out the latest version of Unifi Network for Windows at:
::    URL: https://ui.com/download/releases/network-server
:: 2. When you get the version number, modify the following variable and change the number. E.g:
::    set "version=9.0.108"

:: Access UniFi Network Server:
:: After installation, access UniFi Network Server by navigating to:
:: https://localhost:8443
:: To allow access by IP address, edit the file:
:: "%UserProfile%\Ubiquiti UniFi\data\system.properties"
:: Add the following line with the IP of the PC/Server where UniFi is installed. For example:
:: system_ip=192.168.1.10
:: After editing the file, you can access the server at:
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

:: Check if directory exists, create if it doesn't, then enter the directory
if not exist "%installdir%" (
    echo Directory not found. Creating directory: %installdir%
    mkdir "%installdir%"
)

cd /d "%installdir%" || (
    echo Failed to enter the directory: %installdir%
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

:check_unifi
if exist "%UserProfile%\Ubiquiti UniFi\" (
    echo The folder "%UserProfile%\Ubiquiti UniFi\" already exists
    echo Uninstall Unifi, delete folder and run the script again
    exit /b 1
)

:check_curl
where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo curl is not installed. Please install curl before continuing
    exit /b 1
)

:install_unifi
echo.
echo Getting the latest version of Unifi-Network...
:: Replace the variable number with the latest version available for Windows:
set "version=9.0.108"
curl -# -L -o "UniFi-installer.exe" "https://dl.ui.com/unifi/%version%/UniFi-installer.exe"
set download_status=!errorlevel!
if !download_status! equ 1 (
    echo Error downloading Unifi-Network.
    exit /b 1
)
echo OK
echo.
echo Installing Unifi-Network...
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
echo OK

:get_java
echo.
echo Getting the latest version of Adoptium Temurin 21...
:: Configuration
set "version_base_url=https://github.com/adoptium/temurin21-binaries/releases/download/"
set "version_latest_url=https://api.github.com/repos/adoptium/temurin21-binaries/releases/latest"
set "jdk_type=jre"
set "os_arch=x64_windows"
set "vm_type=hotspot"
:: Get the latest version available from the GitHub API
for /f "delims=" %%a in ('curl -s %version_latest_url% ^| findstr /i "tag_name"') do set "version=%%a"
:: Extract version number
for /f "tokens=2 delims=: " %%b in ("!version!") do set "version=%%b"
set "version=!version:jdk-=!"
set "version=!version:~1,-2!"
:: Replace "B" with "%2B" in the URL
set "url_version=!version!"
set "url_version=!url_version:B=%2B!"
:: Replace "+" with "_" in the file name
set "file_version=!version!"
for /l %%i in (1,1,10) do set "file_version=!file_version:+=_!"
:: URL for the MSI download
set "download_url=%version_base_url%jdk-!url_version!/OpenJDK21U-%jdk_type%_%os_arch%_%vm_type%_!file_version!.msi"
:: Download MSI
::echo Downloading MSI from: !download_url!
curl -# -L -o "OpenJDK21U-%jdk_type%_%os_arch%_%vm_type%_!file_version!.msi" "!download_url!"
:: Check if the download was successful by verifying errorlevel
if %errorlevel% NEQ 0 (
    echo Error downloading MSI.
    exit /b 1
)
echo OK

echo.
echo Installing Java Adoptium...
:install_java
:: Set the latest MSI filename variable
set "latest_msi=OpenJDK21U-%jdk_type%_%os_arch%_%vm_type%_!file_version!.msi"
start /wait msiexec /i "%latest_msi%" ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR="%ProgramFiles%\Temurin\" /quiet >nul 2>&1
if !errorlevel! NEQ 0 (
    echo Error installing MSI file
    exit /b 1
)
echo OK

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

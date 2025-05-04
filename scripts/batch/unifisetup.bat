@echo off
:: maravento.com

:: UniFi Network Server Setup UNS + JRE as a Service
:: For Windows 10/11
:: https://www.maravento.com/2025/02/unifi-como-servicio.html

:: Dependencies:
:: - curl
::   Microsoft Windows 10 (build 17063 or later) and Windows 11 have CURL installed by default.
::   Default Path: C:\Windows\System32\curl.exe
::   If you don't have curl installed, you can download it from:
::   https://curl.se/download.html
:: - Unifi Network Server UNS (.exe)
::   https://ui.com/download/releases/network-server
:: - Eclipse Temurin from Java Adoptium JRE x64 LTS (.msi)
::   https://adoptium.net/es/temurin/releases/?os=windows&arch=x64&package=jre

:: How to Use:
:: - Run it by double-clicking and accepting the privilege elevation
:: - Follow the on-screen instructions

:: Access UNS by localhost:
:: https://localhost:8443

:: Access UNS by IP:
:: Edit the file:
:: "%UserProfile%\Ubiquiti UniFi\data\system.properties"
:: Add the following line with the IP of the PC/Server where UNS is installed. E.g:
:: system_ip=192.168.1.10
:: Save changes and reboot. You can now access the URL:
:: https://192.168.1.10:8443

setlocal enabledelayedexpansion

:check_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:check_os
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo Windows Version Detected: %VERSION%
if NOT "%VERSION%" == "10.0" (
   echo OS Incompatible
   echo.
   pause
   exit /b 1
)
if NOT EXIST "%PROGRAMFILES(X86)%" (
   echo OS Incompatible
   echo.
   pause
   exit /b 1
)

:check_path
set "installpath=%HOMEDRIVE%\uns"
if not exist "%installpath%" (
    mkdir "%installpath%"
)
cd /d "%installpath%" || (
    echo Failed to enter the directory: %installpath%
    echo.
    pause
    exit /b 1
)

:menu
cls
echo.
echo Unifi Network Server as a Service
echo.
echo 1. Install UNS + JRE
echo 2. Remove UNS + JRE
echo 3. Backup Configuration
echo 4. Add IPv4 address
echo 5. Exit
echo.
echo Write your number (1, 2, 3, 4, 5) and
echo Press ENTER
echo.
set /p var=
if "%var%"=="1" goto :install
if "%var%"=="2" goto :remove
if "%var%"=="3" goto :backup
if "%var%"=="4" goto :ip
if "%var%"=="5" exit /0
echo Invalid option. Please select a valid number from 1 to 5
echo.
pause
goto :menu

:backup
set "unifidir=%UserProfile%\Ubiquiti UniFi\data\backup\autobackup"
set "backupdir=%HOMEDRIVE%\uns\backup"
:: Get the date in YYYYMMDD format
for /f "tokens=*" %%I in ('PowerShell -Command "Get-Date -Format 'yyyyMMdd'"') do set "date=%%I"
:: Check if the backup directory exists
if not exist "%unifidir%" (
    echo No backup directory found: %unifidir%
    echo Make sure UniFi is installed and has generated backups
    echo.
    pause
    goto :menu
)
:: Create the destination directory if it does not exist
if not exist "%backupdir%" mkdir "%backupdir%"
:: Find the most recent backup
set "latest="
for /f "delims=" %%F in ('dir /b /a-d /od "%unifidir%\autobackup_*.unf" 2^>nul') do set "latest=%%F"
:: Check if a backup was found
if not defined latest (
    echo No backup files found in %unifidir%.
    echo Ensure that UniFi has generated at least one backup
    echo.
    pause
    goto :menu
)
:: Define the source file path
set "sourcefile=%unifidir%\%latest%"
echo Autobackup: "%sourcefile%"
:: Verify that the source file exists
if not exist "%sourcefile%" (
    echo ERROR: Source file does not exist: "%sourcefile%"
    echo.
    pause
    goto :menu
)
:: Define the destination file name in secure format
set "destfile=%backupdir%\backup_%date%.unf"
:: Copiar el archivo
copy "%sourcefile%" "%destfile%" /Y
:: Check if the copy was successful
if %ERRORLEVEL% NEQ 0 (
    echo Error copying the backup file
    echo.
    pause
    goto :menu
)
echo Backup saved as "%destfile%"
echo.
pause
goto :menu

:ip
echo.
set "propsFile=%UserProfile%\Ubiquiti UniFi\data\system.properties"
set /p system_ip="Enter the IPv4 address (e.g. 192.168.1.10): "

:: Creating a backup copy of the original file
set "backupFile=%UserProfile%\Ubiquiti UniFi\data\system.properties.bak"
copy "%propsFile%" "%backupFile%" >nul
if %errorlevel% == 0 (
    echo.
    echo Backup created successfully at: %backupFile%
) else (
    echo Error creating backup
    echo.
    pause
    goto :menu
)

:: Check if the line already exists
findstr /R "^system_ip=" "%propsFile%" >nul
if %errorlevel% == 0 (
    echo.
    echo ERROR: The IP already exists in the config file
    echo.
    pause
    goto :menu
)

:: If it doesn't exist, add it to the end of the file
echo system_ip=%system_ip%>> "%propsFile%"
:: %system_ip% has been added to the file: %propsFile%
echo Reboot to apply changes
echo You can now access the URL: https://%system_ip%:8443
echo.
pause
goto :menu

:install

:check_java
where java >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=3" %%v in ('java -version 2^>^&1') do (
        echo Java Version: %%v
        echo Uninstall java and run the script again
        echo.
        pause
        goto :menu
    )
)

:check_uns
if exist "%UserProfile%\Ubiquiti UniFi\" (
    echo The folder "%UserProfile%\Ubiquiti UniFi\" already exists
    echo Uninstall Unifi, delete folder and run the script again
    echo.
    pause
    goto :menu
)

:check_curl
where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo curl is not installed. Please install curl before continuing
    echo.
    pause
    exit /b 1
)

:install_uns
echo.
echo Getting the latest version of UNS...
curl -s https://download.svc.ui.com/v1/software-downloads > temp.json
:: 9x
for /f "delims=" %%a in ('powershell -Command "(Get-Content temp.json | ConvertFrom-Json).downloads[0].version"') do set "version=%%a"
:: 8x
for /f "delims=" %%a in ('powershell -Command "(Get-Content temp.json | ConvertFrom-Json).downloads | ForEach-Object { $_.version } | Where-Object { $_ -match '^8\.6\.' } | Select-Object -First 1"') do set "version_86x=%%a"
echo Latest: %version%
if defined version_86x echo Older: %version_86x%
echo.
echo Select a UNS Version to Install:
echo 1. Latest: %version%
if defined version_86x echo 2. Older: %version_86x%
set /p choice="Enter your option (1/2): "
if "%choice%"=="1" set "selected_version=%version%"
if "%choice%"=="2" set "selected_version=%version_86x%"
if not defined selected_version (
    echo Invalid option.
    exit /b 1
)
echo.
echo Downloading UNS version %selected_version%...
curl -# -L -o "UniFi-installer.exe" "https://dl.ui.com/unifi/%selected_version%/UniFi-installer.exe"
set download_status=!errorlevel!
if !download_status! neq 0 (
    echo Error downloading UNS.
    echo.
    pause
    exit /b 1
)
del temp.json
echo OK
echo.
echo Installing UNS...
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
echo Getting the latest version of JRE...
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
echo Latest version: !version!
:: Replace "B" with "%2B" in the URL
set "url_version=!version!"
set "url_version=!url_version:B=%2B!"
:: Replace "+" with "_" in the file name
set "file_version=!version!"
for /l %%i in (1,1,10) do set "file_version=!file_version:+=_!"
:: URL for the MSI download
set "download_url=!version_base_url!jdk-!url_version!/OpenJDK21U-%jdk_type%_%os_arch%_%vm_type%_!file_version!.msi"
:: Download MSI
::echo Downloading MSI from: !download_url!
curl -# -L -o "OpenJDK21U-%jdk_type%_%os_arch%_%vm_type%_!file_version!.msi" "!download_url!"
:: Check if the download was successful by verifying errorlevel
if %errorlevel% NEQ 0 (
    echo Error downloading JRE
    echo.
    pause
    exit /b 1
)
echo OK

:install_java
echo.
echo Installing JRE...
:: Set the latest MSI filename variable
set "latest_msi=OpenJDK21U-%jdk_type%_%os_arch%_%vm_type%_!file_version!.msi"
start /wait msiexec /i "%latest_msi%" ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR="%ProgramFiles%\Temurin\" /quiet >nul 2>&1
if !errorlevel! NEQ 0 (
    echo Error installing JRE
    echo.
    pause
    exit /b 1
)
echo OK

echo.
echo Setup UNS as a Service...
cd "%UserProfile%\Ubiquiti UniFi\" || (
    echo Failed to change directory to "%UserProfile%\Ubiquiti UniFi\"
    echo.
    pause
    exit /b 1
)
set JAVA_PATH="%ProgramFiles%\Temurin\bin\java.exe"
%JAVA_PATH% -jar lib\ace.jar startsvc &
%JAVA_PATH% -jar lib\ace.jar installsvc >nul 2>&1
echo OK

:firewall_rules
echo.
echo Add Firewall Rules...
netsh advfirewall firewall add rule name="Unifi TCP in 8080,8443,8880,8843" protocol=TCP dir=in localport=8080,8443,8880,8843 action=allow >nul 2>&1
netsh advfirewall firewall add rule name="Unifi TCP out 8080,8443,8880,8843" protocol=TCP dir=out localport=8080,8843 action=allow >nul 2>&1
netsh advfirewall firewall add rule name="Unifi UDP in 10001,3478" protocol=UDP dir=in localport=10001,3478 action=allow >nul 2>&1
netsh advfirewall firewall add rule name="Unifi UDP out 10001,3478" protocol=UDP dir=out localport=10001,3478 action=allow >nul 2>&1
echo OK

:final_install
echo.
echo Done
echo Access https://localhost:8443
echo Reboot your system
echo.
pause
exit

:remove
echo.
echo Delete Firewall Rules...
netsh advfirewall firewall delete rule name="Unifi TCP in 8080,8443,8880,8843" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi TCP out 8080,8443,8880,8843" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP in 10001,3478" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP out 10001,3478" >nul 2>&1
echo OK

:uninstall_uns
echo.
echo Uninstall UNS...
net stop UniFi >nul 2>&1
cd "%UserProfile%\Ubiquiti UniFi\" || (
    echo Failed to change directory to "%UserProfile%\Ubiquiti UniFi\"
    echo.
    pause
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
	echo OK
	goto :msi
)
echo UNS Uninstaller not found
exit /b 1

:msi
echo.
echo Uninstall JRE...
set "installpath=%HOMEDRIVE%\uns"
cd /d "%installpath%"
set "latest_msi="
for /f "delims=" %%f in ('dir /b /a-d /o-d /t:c "OpenJDK*-jre_x64_windows_hotspot_*.msi" 2^>nul') do (
    set "latest_msi=%%f"
    goto :remove_jre
)
echo Java MSI file not found in %installpath%.
exit /b 1
:remove_jre
start /wait msiexec /x "%latest_msi%" /quiet
echo OK

:: delete folder
taskkill /f /im "java.exe" >nul 2>&1
taskkill /f /im "UniFi.exe" >nul 2>&1
timeout /t 2 >nul
rd /s /q "%UserProfile%\Ubiquiti UniFi" >nul 2>&1

:final_remove
echo.
echo Done
echo Reboot your system
echo.
pause
exit

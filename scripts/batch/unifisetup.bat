@echo off
:: maravento.com
:: UniFi Setup + JRE as a Service
:: For Windows 10/11
:: https://www.maravento.com/2025/02/unifi-como-servicio.html
:: Access:
:: UniFi Network Controller
:: ACCESS URL: https://localhost:8443
:: Unifi OS server
:: ACCESS URL: https://localhost:11443

setlocal enabledelayedexpansion

:: ===========================================
:: LOGGING SETUP
:: ===========================================
set "installpath=%HOMEDRIVE%\unifi"
if not exist "%installpath%" mkdir "%installpath%"

:: Create logs folder
set "logspath=%installpath%\logs"
if not exist "%logspath%" mkdir "%logspath%"

:: Get date and time for log name
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set "logname=unifi_install_%datetime:~0,8%_%datetime:~8,6%.log"
set "logfile=%logspath%\%logname%"

echo [%date% %time%] Script started > "%logfile%"
echo =========================================== >> "%logfile%"
echo UNIFI INSTALLATION LOG >> "%logfile%"
echo Started: %date% %time% >> "%logfile%"
echo Log file: %logfile% >> "%logfile%"
echo =========================================== >> "%logfile%"

cls
echo ===========================================
echo UNIFI INSTALLATION MANAGER
echo Log file: %logfile%
echo ===========================================

:check_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] Requesting admin privileges >> "%logfile%"
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:check_os
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo Windows Version Detected: %VERSION%
echo [%date% %time%] Windows Version: %VERSION% >> "%logfile%"
if NOT "%VERSION%" == "10.0" (
   echo OS Incompatible
   echo [%date% %time%] ERROR: OS Incompatible - Not Windows 10/11 >> "%logfile%"
   echo.
   pause
   exit /b 1
)
if NOT EXIST "%PROGRAMFILES(X86)%" (
   echo OS Incompatible
   echo [%date% %time%] ERROR: OS Incompatible - No x86 Program Files >> "%logfile%"
   echo.
   pause
   exit /b 1
)

:check_path
if not exist "%installpath%" (
    echo [%date% %time%] Creating directory: %installpath% >> "%logfile%"
    mkdir "%installpath%"
)
cd /d "%installpath%" || (
    echo Failed to enter the directory: %installpath%
    echo [%date% %time%] ERROR: Failed to enter %installpath% >> "%logfile%"
    echo.
    pause
    exit /b 1
)

:menu
cls
echo.
echo UniFi Installation Manager
echo Log file: %logfile%
echo.
echo 1. Install UniFi Network Controller (Runs as Windows Service)
echo 2. Install UniFi OS Server (Does NOT run as Service - See Warning)
echo 3. Backup Configuration
echo 4. Remove UniFi + JRE
echo 5. Add IPv4 address
echo 6. Exit
echo.
set /p "var=Write your number (1, 2, 3, 4, 5, 6) and Press ENTER: "
if "%var%"=="1" (
    echo [%date% %time%] User selected: Install UniFi Network Controller >> "%logfile%"
    goto :install_network
)
if "%var%"=="2" (
    echo [%date% %time%] User selected: Install UniFi OS Server >> "%logfile%"
    goto :install_os
)
if "%var%"=="3" (
    echo [%date% %time%] User selected: Backup Configuration >> "%logfile%"
    goto :backup
)
if "%var%"=="4" (
    echo [%date% %time%] User selected: Remove UniFi + JRE >> "%logfile%"
    goto :remove
)
if "%var%"=="5" (
    echo [%date% %time%] User selected: Add IPv4 address >> "%logfile%"
    goto :ip
)
if "%var%"=="6" (
    echo [%date% %time%] User selected: Exit >> "%logfile%"
    exit /b 0
)
echo Invalid option. Please select a valid number from 1 to 6
echo [%date% %time%] ERROR: Invalid option selected: %var% >> "%logfile%"
echo.
pause
goto :menu

:: ===========================================
:: COMMON FUNCTIONS
:: ===========================================

:check_java
echo [%date% %time%] Checking for existing Java installation >> "%logfile%"
where java >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=3" %%v in ('java -version 2^>^&1') do (
        echo Java Version: %%v
        echo Uninstall java and run the script again
        echo [%date% %time%] ERROR: Java already installed: %%v >> "%logfile%"
        echo.
        pause
        goto :menu
    )
)
echo [%date% %time%] No existing Java found, OK to proceed >> "%logfile%"
exit /b 0

:check_curl
echo [%date% %time%] Checking for curl >> "%logfile%"
where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo curl is not installed. Please install curl before continuing
    echo [%date% %time%] ERROR: curl not installed >> "%logfile%"
    echo.
    pause
    exit /b 1
)
echo [%date% %time%] curl found, OK to proceed >> "%logfile%"
exit /b 0

:download_jre
echo.
echo [%date% %time%] Starting JRE download >> "%logfile%"
echo Getting the latest version of JRE...
set "version_base_url=https://github.com/adoptium/temurin21-binaries/releases/download/"
set "version_latest_url=https://api.github.com/repos/adoptium/temurin21-binaries/releases/latest"
set "jdk_type=jre"
set "os_arch=x64_windows"
set "vm_type=hotspot"

echo [%date% %time%] Fetching JRE version info from: !version_latest_url! >> "%logfile%"
for /f "delims=" %%a in ('curl -s !version_latest_url! ^| findstr /i "tag_name"') do set "version=%%a"
for /f "tokens=2 delims=: " %%b in ("!version!") do set "version=%%b"
set "version=!version:jdk-=!"
set "version=!version:~1,-2!"
echo Latest version: !version!
echo [%date% %time%] JRE version detected: !version! >> "%logfile%"

set "url_version=!version!"
set "url_version=!url_version:B=%2B!"
set "file_version=!version!"
for /l %%i in (1,1,10) do set "file_version=!file_version:+=_!"

set "download_url=!version_base_url!jdk-!url_version!/OpenJDK21U-!jdk_type!_!os_arch!_!vm_type!_!file_version!.msi"
set "msi_filename=OpenJDK21U-!jdk_type!_!os_arch!_!vm_type!_!file_version!.msi"

echo [%date% %time%] Download URL: !download_url! >> "%logfile%"
cd /d "%installpath%" || exit /b 1
echo [%date% %time%] Downloading JRE to: %installpath%\!msi_filename! >> "%logfile%"
curl -# -L -o "!msi_filename!" "!download_url!"
set "curl_error=!errorlevel!"
if !curl_error! NEQ 0 (
    echo Error downloading JRE
    echo [%date% %time%] ERROR: JRE download failed with error !curl_error! >> "%logfile%"
    exit /b 1
)
echo [%date% %time%] JRE download successful: !msi_filename! >> "%logfile%"
echo OK
exit /b 0

:install_jre
echo.
echo [%date% %time%] Installing JRE... >> "%logfile%"
echo Installing JRE...
cd /d "%installpath%" || exit /b 1
set "latest_msi=OpenJDK21U-!jdk_type!_!os_arch!_!vm_type!_!file_version!.msi"
echo [%date% %time%] Installing MSI: !latest_msi! >> "%logfile%"
start /wait msiexec /i "!latest_msi!" ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR="%ProgramFiles%\Temurin\" /quiet >nul 2>&1
set "msi_error=!errorlevel!"
if !msi_error! NEQ 0 (
    echo Error installing JRE
    echo [%date% %time%] ERROR: JRE installation failed with error !msi_error! >> "%logfile%"
    exit /b 1
)
echo [%date% %time%] JRE installation successful >> "%logfile%"
echo OK
exit /b 0

:setup_firewall
echo.
echo [%date% %time%] Configuring UniFi Firewall Rules... >> "%logfile%"
echo Configuring UniFi Firewall Rules...
netsh advfirewall firewall add rule name="Unifi TCP in 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" protocol=TCP dir=in localport=8080,8443,8880,8843,8444,8881,8882,9543,10003,11443 action=allow >nul 2>&1
echo [%date% %time%] Added firewall rule: Unifi TCP in >> "%logfile%"
netsh advfirewall firewall add rule name="Unifi TCP out 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" protocol=TCP dir=out localport=8080,8443,8880,8843,8444,8881,8882,9543,10003,11443 action=allow >nul 2>&1
echo [%date% %time%] Added firewall rule: Unifi TCP out >> "%logfile%"
netsh advfirewall firewall add rule name="Unifi UDP in 3478,10001,5005,5514,6789" protocol=UDP dir=in localport=3478,10001,5005,5514,6789 action=allow >nul 2>&1
echo [%date% %time%] Added firewall rule: Unifi UDP in >> "%logfile%"
netsh advfirewall firewall add rule name="Unifi UDP out 3478,10001,5005,5514,6789" protocol=UDP dir=out localport=3478,10001,5005,5514,6789 action=allow >nul 2>&1
echo [%date% %time%] Added firewall rule: Unifi UDP out >> "%logfile%"
echo OK
exit /b 0

:kill_processes
echo.
echo [%date% %time%] Stopping UniFi processes... >> "%logfile%"
echo Stopping UniFi processes...
taskkill /f /im "java.exe" >nul 2>&1 && echo [%date% %time%] Killed: java.exe >> "%logfile%"
taskkill /f /im "UniFi.exe" >nul 2>&1 && echo [%date% %time%] Killed: UniFi.exe >> "%logfile%"
taskkill /f /im "podman.exe" >nul 2>&1 && echo [%date% %time%] Killed: podman.exe >> "%logfile%"
taskkill /f /im "UniFi OS Server.exe" >nul 2>&1 && echo [%date% %time%] Killed: UniFi OS Server.exe >> "%logfile%"
taskkill /f /im "UniFi-installer.exe" >nul 2>&1 && echo [%date% %time%] Killed: UniFi-installer.exe >> "%logfile%"
taskkill /f /im "Uninstall.exe" >nul 2>&1 && echo [%date% %time%] Killed: Uninstall.exe >> "%logfile%"
timeout /t 2 /nobreak >nul
echo [%date% %time%] Process stopping complete >> "%logfile%"
exit /b 0

:final_installation
echo.
echo [%date% %time%] Installation Complete! >> "%logfile%"
cls
echo ===========================================
echo        INSTALLATION COMPLETE
echo ===========================================
echo.

if "%detect_os%"=="1" (
    echo PRODUCT: UniFi OS Server
    echo ACCESS URL: https://localhost:11443
    echo.
    echo IMPORTANT: UniFi OS Server does NOT start automatically on boot.
    echo You must manually start "UniFi OS Server" from the Start Menu after each reboot.
    echo Alternatively, keep the application running in the background.
    echo [%date% %time%] UniFi OS Server installed at: https://localhost:11443 >> "%logfile%"
) else (
    echo PRODUCT: UniFi Network Controller
    echo ACCESS URL: https://localhost:8443
    echo [%date% %time%] UniFi Network Controller installed at: https://localhost:8443 >> "%logfile%"
)

echo.
echo ===========================================
echo IMPORTANT: REBOOT YOUR SYSTEM
echo ===========================================
echo.
echo Installation completed successfully.
echo You MUST reboot your system for changes to take effect.
echo.
echo Press any key to exit...
echo.
echo [%date% %time%] Installation finished successfully >> "%logfile%"
echo =========================================== >> "%logfile%"
pause >nul
exit /b 0

:: ===========================================
:: VERSION SELECTION FUNCTION 
:: ===========================================

:get_version_selection
set "json_file=%~1"
set "product_type=%~2"

echo [%date% %time%] Getting version selection for: %product_type% >> "%logfile%"

set "version_latest="
set "version_previous="
set "selected_version="
set "selected_url="

if "%product_type%"=="network" (
    echo [%date% %time%] Getting Network Controller versions... >> "%logfile%"
    
    :: Get all versions, sort by version number (descending)
    powershell -Command "$versions = (Get-Content '%json_file%' | ConvertFrom-Json).downloads | Where-Object { $_.name -like '*UniFi Network Application*Windows*' } | Select-Object -ExpandProperty version -Unique | ForEach-Object { [version]$_ } | Sort-Object -Descending; $versions | ForEach-Object { $_.ToString() }" > "%installpath%\network_versions.txt"
    
    :: Get latest version (first line = highest version)
    for /f "delims=" %%v in ('type "%installpath%\network_versions.txt"') do (
        if not defined version_latest (
            set "version_latest=%%v"
            for /f "tokens=1 delims=." %%m in ("%%v") do set "latest_major=%%m"
        )
    )
    
    :: Find the latest version from a different major version
    for /f "delims=" %%v in ('type "%installpath%\network_versions.txt"') do (
        for /f "tokens=1 delims=." %%m in ("%%v") do (
            if not "%%m"=="!latest_major!" (
                if not defined version_previous (
                    set "version_previous=%%v"
                )
            )
        )
    )
    
    echo Latest: !version_latest!
    if defined version_previous echo Previous: !version_previous!
    echo [%date% %time%] Network - Latest: !version_latest!, Previous: !version_previous! >> "%logfile%"
    
) else if "%product_type%"=="os" (
    echo [%date% %time%] Getting OS Server versions... >> "%logfile%"
    
    :: Get all versions, sort by version number (descending)
    powershell -Command "$versions = (Get-Content '%json_file%' | ConvertFrom-Json).downloads | Where-Object { $_.name -like '*UniFi OS Server*Windows*' } | Select-Object -ExpandProperty version -Unique | ForEach-Object { [version]$_ } | Sort-Object -Descending; $versions | ForEach-Object { $_.ToString() }" > "%installpath%\os_versions.txt"
    
    :: Get latest version (first line = highest version)
    for /f "delims=" %%v in ('type "%installpath%\os_versions.txt"') do (
        if not defined version_latest (
            set "version_latest=%%v"
            for /f "tokens=1 delims=." %%m in ("%%v") do set "latest_major=%%m"
        )
    )
    
    :: Find the latest version from a different major version
    for /f "delims=" %%v in ('type "%installpath%\os_versions.txt"') do (
        for /f "tokens=1 delims=." %%m in ("%%v") do (
            if not "%%m"=="!latest_major!" (
                if not defined version_previous (
                    set "version_previous=%%v"
                )
            )
        )
    )
    
    echo Latest: !version_latest!
    if defined version_previous echo Previous: !version_previous!
    echo [%date% %time%] OS - Latest: !version_latest!, Previous: !version_previous! >> "%logfile%"
)

:: Display version selection menu
:version_menu
cls
echo.
echo ===========================================
echo          VERSION SELECTION
echo ===========================================
echo.
echo Available versions for UniFi %product_type%:
echo.
echo 1. Latest: !version_latest!

if defined version_previous (
    echo 2. Previous: !version_previous!
    echo 3. Custom version
    echo 4. Cancel
) else (
    echo 2. Custom version
    echo 3. Cancel
)

echo.
set "choice="
set /p "choice=Enter your option: "
echo [%date% %time%] User choice: !choice! >> "%logfile%"

if "!choice!"=="" goto :version_menu

:: Option 1: Latest
if "!choice!"=="1" (
    set "selected_version=!version_latest!"
    goto :get_version_url
)

:: Option 2: Previous or Custom
if "!choice!"=="2" (
    if defined version_previous (
        set "selected_version=!version_previous!"
        goto :get_version_url
    ) else (
        goto :custom_version
    )
)

:: Option 3: Custom or Cancel
if "!choice!"=="3" (
    if defined version_previous (
        goto :custom_version
    ) else (
        goto :cancel_version
    )
)

:: Option 4: Cancel (only if previous exists)
if "!choice!"=="4" (
    if defined version_previous (
        goto :cancel_version
    )
)

echo Invalid option. Please try again.
pause
goto :version_menu

:custom_version
echo.
set "custom_ver="
set /p "custom_ver=Enter specific version number: "
if "!custom_ver!"=="" goto :custom_version

:: Check if custom version exists
set "version_exists=0"
if "%product_type%"=="network" (
    for /f "delims=" %%v in ('type "%installpath%\network_versions.txt"') do (
        if "%%v"=="!custom_ver!" (
            set "version_exists=1"
            set "selected_version=!custom_ver!"
        )
    )
) else if "%product_type%"=="os" (
    for /f "delims=" %%v in ('type "%installpath%\os_versions.txt"') do (
        if "%%v"=="!custom_ver!" (
            set "version_exists=1"
            set "selected_version=!custom_ver!"
        )
    )
)

if !version_exists! equ 0 (
    echo Version !custom_ver! not found in available versions.
    echo [%date% %time%] ERROR: Custom version not found: !custom_ver! >> "%logfile%"
    echo.
    pause
    goto :version_menu
)

:get_version_url
echo [%date% %time%] Selected version: !selected_version! >> "%logfile%"

:: Get download URL for selected version
if "%product_type%"=="network" (
    :: For Network Controller - simple URL format
    set "selected_url=https://dl.ui.com/unifi/!selected_version!/UniFi-installer.exe"
    echo [%date% %time%] Network download URL: !selected_url! >> "%logfile%"
) else if "%product_type%"=="os" (
    :: For OS Server - need to find URL from JSON
    for /f "delims=" %%a in ('powershell -Command "(Get-Content '%json_file%' | ConvertFrom-Json).downloads | Where-Object { $_.name -like '*UniFi OS Server*Windows*' -and $_.version -eq '!selected_version!' } | Select-Object -First 1 -ExpandProperty file_path"') do set "selected_url=%%a"
    if not defined selected_url (
        echo ERROR: Could not find download URL for version !selected_version!
        echo [%date% %time%] ERROR: No download URL found for version !selected_version! >> "%logfile%"
        exit /b 1
    )
    echo [%date% %time%] OS Server download URL: !selected_url! >> "%logfile%"
)

:: Cleanup temp files
if exist "%installpath%\network_versions.txt" del "%installpath%\network_versions.txt"
if exist "%installpath%\os_versions.txt" del "%installpath%\os_versions.txt"

exit /b 0

:cancel_version
:: Cleanup and return to menu
if exist "%installpath%\network_versions.txt" del "%installpath%\network_versions.txt"
if exist "%installpath%\os_versions.txt" del "%installpath%\os_versions.txt"
echo [%date% %time%] User cancelled version selection >> "%logfile%"
exit /b 1

:wait_installer
set "process_name=%~1"
echo [%date% %time%] Waiting for installer: %process_name% >> "%logfile%"
:wait_loop
timeout /t 10 /nobreak >nul
tasklist /fi "imagename eq %process_name%" 2>nul | find /i "%process_name%" >nul
if %errorlevel% equ 0 goto wait_loop
echo [%date% %time%] Installer finished: %process_name% >> "%logfile%"
exit /b 0

:: ===========================================
:: FORCE REMOVE FOLDER FUNCTION
:: ===========================================

:force_remove_folder
set "folder_to_remove=%~1"
if not exist "!folder_to_remove!" exit /b 0

echo [%date% %time%] Force removing folder: !folder_to_remove! >> "%logfile%"
echo Removing: !folder_to_remove!

:: Method 1: Try normal removal first
rd /s /q "!folder_to_remove!" >nul 2>&1
if not exist "!folder_to_remove!" (
    echo [%date% %time%] Successfully removed with rd command >> "%logfile%"
    exit /b 0
)

:: Method 2: Take ownership and remove
echo Taking ownership and retrying...
takeown /f "!folder_to_remove!" /r /d y >nul 2>&1
icacls "!folder_to_remove!" /grant "%username%":F /t /q >nul 2>&1
rd /s /q "!folder_to_remove!" >nul 2>&1
if not exist "!folder_to_remove!" (
    echo [%date% %time%] Successfully removed with takeown >> "%logfile%"
    exit /b 0
)

:: Method 3: Use PowerShell to force delete
echo Using PowerShell to force delete...
powershell -Command "if (Test-Path '!folder_to_remove!') { Remove-Item -Path '!folder_to_remove!' -Recurse -Force -ErrorAction SilentlyContinue }" >nul 2>&1
timeout /t 2 /nobreak >nul
if not exist "!folder_to_remove!" (
    echo [%date% %time%] Successfully removed with PowerShell >> "%logfile%"
    exit /b 0
)

:: Method 4: Kill any processes that might be locking files
echo Stopping processes that might lock the folder...
call :kill_processes
timeout /t 3 /nobreak >nul
rd /s /q "!folder_to_remove!" >nul 2>&1
if not exist "!folder_to_remove!" (
    echo [%date% %time%] Successfully removed after killing processes >> "%logfile%"
    exit /b 0
)

:: Final check
if exist "!folder_to_remove!" (
    echo.
    echo WARNING: Could not completely remove: !folder_to_remove!
    echo The folder may contain locked files or require a system restart.
    echo [%date% %time%] WARNING: Could not remove folder: !folder_to_remove! >> "%logfile%"
    echo.
    echo The script will continue, but please manually delete this folder after reboot.
    timeout /t 3
) else (
    echo [%date% %time%] Successfully removed folder: !folder_to_remove! >> "%logfile%"
)
exit /b 0

:: ===========================================
:: UNIFI NETWORK CONTROLLER INSTALLATION
:: ===========================================

:install_network
echo =========================================== >> "%logfile%"
echo [%date% %time%] STARTING UNIFI NETWORK CONTROLLER INSTALLATION >> "%logfile%"
echo =========================================== >> "%logfile%"

:: FIX 1: Improved folder check - only block if UniFi is actually running
:: Check if UniFi service is running
sc query "UniFi" >nul 2>&1
if %errorlevel% equ 0 (
    echo UniFi Network Controller service is running.
    echo Please uninstall UniFi first using option 4.
    echo [%date% %time%] ERROR: UniFi service is running >> "%logfile%"
    echo.
    pause
    goto :menu
)

:: Check if folder exists but allow if it's empty or from failed installation
if exist "%UserProfile%\Ubiquiti UniFi\" (
    echo.
    echo ===========================================
    echo    EXISTING UNIFI FOLDER DETECTED
    echo ===========================================
    echo.
    echo The UniFi folder already exists at:
    echo %UserProfile%\Ubiquiti UniFi\
    echo.
    
    :: Check if it's a complete installation
    if exist "%UserProfile%\Ubiquiti UniFi\Uninstall.exe" (
        echo This appears to be a complete UniFi installation.
        echo Please use option 4 to uninstall it first.
        echo [%date% %time%] ERROR: Complete UniFi installation found >> "%logfile%"
        echo.
        pause
        goto :menu
    )
    
    :: It's incomplete or leftover - offer to clean
    echo This appears to be an incomplete or leftover installation.
    echo.
    echo Options:
    echo 1. Clean up and continue with fresh installation
    echo 2. Cancel and return to main menu
    echo.
    set /p "cleanup_choice=Enter your choice (1 or 2): "
    
    if "!cleanup_choice!"=="1" (
        echo.
        echo Cleaning up incomplete installation...
        echo [%date% %time%] User chose to clean up incomplete installation >> "%logfile%"
        call :kill_processes
        call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
        
        :: Verify removal
        if exist "%UserProfile%\Ubiquiti UniFi\" (
            echo.
            echo ERROR: Could not remove the folder completely.
            echo Please manually delete: %UserProfile%\Ubiquiti UniFi\
            echo Then run the script again.
            echo [%date% %time%] ERROR: Failed to clean up folder >> "%logfile%"
            echo.
            pause
            goto :menu
        )
        
        echo Cleanup successful! Continuing with installation...
        echo [%date% %time%] Cleanup successful, proceeding with installation >> "%logfile%"
        timeout /t 2 /nobreak >nul
    ) else (
        echo Installation cancelled.
        echo [%date% %time%] User cancelled installation >> "%logfile%"
        echo.
        pause
        goto :menu
    )
)

:check_java_network
call :check_java
if errorlevel 1 goto :menu

call :check_curl
if errorlevel 1 exit /b 1

echo.
echo Getting available versions of UniFi Network...
curl -s https://download.svc.ui.com/v1/software-downloads > temp_network.json
echo [%date% %time%] Downloaded version info to temp_network.json >> "%logfile%"

call :get_version_selection "temp_network.json" "network"
if errorlevel 1 (
    del temp_network.json
    echo [%date% %time%] Version selection cancelled or failed >> "%logfile%"
    goto :menu
)

echo.
echo Downloading UniFi Network version !selected_version!...
echo [%date% %time%] Downloading UniFi Network version: !selected_version! >> "%logfile%"
cd /d "%installpath%" || (
    del temp_network.json
    echo [%date% %time%] ERROR: Failed to change to install directory >> "%logfile%"
    goto :menu
)
curl -# -L -o "UniFi-installer.exe" "!selected_url!"
set "unifi_dl_error=!errorlevel!"
if !unifi_dl_error! neq 0 (
    echo Error downloading UniFi Network.
    echo [%date% %time%] ERROR: UniFi download failed with error !unifi_dl_error! >> "%logfile%"
    del temp_network.json
    echo.
    pause
    goto :menu
)

del temp_network.json
echo OK
echo [%date% %time%] UniFi download successful: UniFi-installer.exe >> "%logfile%"

echo.
echo Installing UniFi Network...
echo [%date% %time%] Running UniFi installer... >> "%logfile%"
"%installpath%\UniFi-installer.exe" /S

call :wait_installer "UniFi-installer.exe"

echo [%date% %time%] Creating UniFi data directory... >> "%logfile%"
mkdir "%UserProfile%\Ubiquiti UniFi\data" 2>nul
(
echo debug.device=warn
echo debug.mgmt=warn
echo debug.sdn=warn
echo debug.setting_preference=auto
echo debug.system=warn
) > "%installpath%\system.properties"
copy "%installpath%\system.properties" "%UserProfile%\Ubiquiti UniFi\data" >nul 2>&1
echo [%date% %time%] Created system.properties configuration file >> "%logfile%"
echo OK

echo [%date% %time%] Starting JRE installation phase >> "%logfile%"
call :download_jre
if errorlevel 1 (
    echo [%date% %time%] ERROR: JRE download failed >> "%logfile%"
    goto :cleanup_network
)

call :install_jre
if errorlevel 1 (
    echo [%date% %time%] ERROR: JRE installation failed >> "%logfile%"
    goto :cleanup_network
)

echo.
echo Setting up UniFi Network as a Service...
echo [%date% %time%] Setting up UniFi as Windows Service... >> "%logfile%"
cd "%UserProfile%\Ubiquiti UniFi\" || (
    echo Failed to change directory
    echo [%date% %time%] ERROR: Failed to change to UniFi directory >> "%logfile%"
    pause
    goto :cleanup_network
)
set "JAVA_PATH=%ProgramFiles%\Temurin\bin\java.exe"
echo [%date% %time%] Java path: %JAVA_PATH% >> "%logfile%"

echo [%date% %time%] Running: %JAVA_PATH% -jar lib\ace.jar startsvc >> "%logfile%"
"%JAVA_PATH%" -jar lib\ace.jar startsvc &
echo [%date% %time%] Running: %JAVA_PATH% -jar lib\ace.jar installsvc >> "%logfile%"
"%JAVA_PATH%" -jar lib\ace.jar installsvc >nul 2>&1
set "service_error=!errorlevel!"
if !service_error! neq 0 (
    echo Error setting up service
    echo [%date% %time%] ERROR: Service setup failed with error !service_error! >> "%logfile%"
    pause
    goto :cleanup_network
)
echo [%date% %time%] Service setup successful >> "%logfile%"
echo OK

call :setup_firewall

set detect_os=0
echo [%date% %time%] UNIFI NETWORK CONTROLLER INSTALLATION COMPLETE >> "%logfile%"
goto :final_installation

:cleanup_network
echo Installation failed. Cleaning up...
echo [%date% %time%] INSTALLATION FAILED - CLEANING UP >> "%logfile%"
call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
echo [%date% %time%] Cleanup complete, returning to menu >> "%logfile%"
pause
goto :menu

:: ===========================================
:: UNIFI OS SERVER INSTALLATION
:: ===========================================

:install_os
cls
set "errors=0"
set "virt_ok=0"
set "wsl_ok=0"
set "distro_ok=0"

echo ===========================================
echo        UniFi OS Server - PRE-CHECK
echo ===========================================
echo.

:: 1. Check virtualization
powershell -Command "if ((Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled) {exit 0} else {exit 1}"
if %errorlevel% equ 0 (
    echo [OK] Virtualization enabled
    set "virt_ok=1"
) else (
    echo [FAIL] Virtualization not enabled
)

:: 2. Check WSL2 installation
wsl --status >nul 2>&1
if %errorlevel% equ 0 (
    wsl --status | findstr "Default Version: 2" >nul 2>&1
    if %errorlevel% equ 0 (
        echo [OK] WSL2 installed
        set "wsl_ok=1"
    ) else (
        echo [FAIL] WSL installed but not version 2
    )
) else (
    echo [FAIL] WSL not installed
)

:: 3. Check WSL distribution
set "distro="
for /f %%i in ('wsl --list --quiet 2^>nul') do set distro=%%i
if defined distro (
    echo [OK] WSL distribution installed (%distro%)
    set "distro_ok=1"
) else (
    echo [FAIL] No WSL distribution installed
)

echo.
:: DECISION LOGIC
if %virt_ok% neq 1 (
    echo Virtualization is required. Cannot continue.
    pause
    goto :menu
)

:: If virtualization is ok but WSL2 or distro fail, try to fix
if %wsl_ok% neq 1 (
    echo Installing WSL2...
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul
    call :install_wsl_kernel
    if %errorlevel% neq 0 (
        echo Failed to install WSL2. Cannot continue.
        pause
        goto :menu
    )
    wsl --set-default-version 2 >nul
    set "wsl_ok=1"
    echo [OK] WSL2 installed
)

if %distro_ok% neq 1 (
    echo Installing Ubuntu in WSL2...
    wsl --install -d Ubuntu
    if %errorlevel% neq 0 (
        echo Failed to install Ubuntu. Cannot continue.
        pause
        goto :menu
    )
    set "distro_ok=1"
    echo [OK] Ubuntu installed
)

echo.
if %virt_ok% equ 1 if %wsl_ok% equ 1 if %distro_ok% equ 1 (
    echo All checks passed. Press any key to continue.
    pause
    goto :install_os_continue
)


echo.
echo ===========================================
echo        UniFi OS Server - IMPORTANT
echo ===========================================
echo.
echo NOTE: UniFi OS Server runs via WSL2 and Podman containers.
echo.
echo - NOT a native Windows Service
echo - Does NOT auto-start with Windows
echo - Requires WSL2 running
echo - Uses Podman containers
echo - Access via https://localhost:11443
echo.
echo Do you want to install UniFi OS Server?
set /p continue_os="Continue? (y/n): "
if /i not "%continue_os%"=="y" goto :menu

if exist "%UserProfile%\AppData\Local\Programs\UniFi OS Server\" (
    echo UniFi OS Server is already installed.
    echo Uninstall it first.
    pause
    goto :menu
)

echo.
echo Step 1: Enabling WSL features...
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul

echo.
echo Step 2: Installing WSL2 Kernel Update...
call :install_wsl_kernel
if %errorlevel% neq 0 goto :cleanup_os

echo.
echo Step 3: Setting WSL default version to 2...
wsl --set-default-version 2 >nul

echo.
echo Step 4: Restarting WSL service...
net stop LxssManager >nul
timeout /t 2 /nobreak >nul
net start LxssManager >nul

echo.
echo WSL setup complete.
echo If this is new WSL install, reboot required.
pause
goto :menu

:install_os_continue
call :check_curl
if errorlevel 1 exit /b 1

echo.
echo Step 5: Getting UniFi OS Server version...
curl -s https://download.svc.ui.com/v1/software-downloads > temp_os.json

call :get_version_selection "temp_os.json" "os"
if errorlevel 1 (
    del temp_os.json
    goto :menu
)

echo.
echo Downloading UniFi OS Server version %selected_version%...
cd /d "%installpath%"
curl -# -L -o "UniFi-OS-Server-installer.exe" "%selected_url%"
if %errorlevel% neq 0 (
    echo Error downloading UniFi OS Server.
    del temp_os.json
    pause
    goto :menu
)

del temp_os.json
echo OK

echo.
echo Step 6: Installing UniFi OS Server...
"%installpath%\UniFi-OS-Server-installer.exe" /S

call :wait_installer "UniFi-OS-Server-installer.exe"
echo OK

call :setup_firewall

echo.
echo Installation Complete!
echo Launch "UniFi OS Server" from Start Menu
echo Access at https://localhost:11443
pause
goto :menu

:cleanup_os
echo Installation failed. Cleaning up...
if exist "%UserProfile%\AppData\Local\Programs\UniFi OS Server\" rd /s /q "%UserProfile%\AppData\Local\Programs\UniFi OS Server"
if exist "UniFi-OS-Server-installer.exe" del "UniFi-OS-Server-installer.exe"
if exist "temp_os.json" del "temp_os.json"
pause
goto :menu

:: ===========================================
:: REQUIRED FUNCTION ADDED HERE
:: ===========================================

:install_wsl_kernel
echo Downloading WSL2 kernel update...
curl -# -L -o "%installpath%\wsl_update_x64.msi" "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
if %errorlevel% neq 0 (
    echo Failed to download WSL2 kernel update.
    exit /b 1
)

echo Installing WSL2 kernel update...
msiexec /i "%installpath%\wsl_update_x64.msi" /quiet /norestart
if %errorlevel% neq 0 (
    echo Failed to install WSL2 kernel update.
    exit /b 1
)

echo OK
exit /b 0

:: ===========================================
:: REMOVE UNIFI + JRE FUNCTION
:: ===========================================

:remove
set "detect_network=0"
set "detect_os=0"
set "detect_java=0"
set "found_any_folder=0"

:: Check for UniFi Network folders (even if empty or incomplete)
if exist "%UserProfile%\Ubiquiti UniFi\" (
    set "detect_network=1"
    set "found_any_folder=1"
)

:: Check for UniFi OS Server folders
if exist "%UserProfile%\AppData\Local\Programs\UniFi OS Server\" (
    set "detect_os=1"
    set "found_any_folder=1"
)

:: Check for Java
if exist "%ProgramFiles%\Temurin\" (
    set "detect_java=1"
    set "found_any_folder=1"
)

:: Check for running services
sc query "UniFi" >nul 2>&1
if %errorlevel% equ 0 (
    set "detect_network=1"
    set "found_any_folder=1"
)

:: If nothing found at all, exit
if %found_any_folder% equ 0 (
    cls
    echo.
    echo ===========================================
    echo            REMOVE UNIFI + JRE
    echo ===========================================
    echo.
    echo No UniFi installations or folders detected.
    echo Everything is already clean.
    echo.
    pause
    goto :menu
)

cls
echo.
echo ===========================================
echo            REMOVE UNIFI + JRE
echo ===========================================
echo.
echo The following will be removed:
echo.
if %detect_network% equ 1 echo - UniFi Network Controller
if %detect_os% equ 1 echo - UniFi OS Server
if %detect_java% equ 1 echo - Java JRE (Temurin)
echo.
echo WARNING: This action cannot be undone!
echo.
set /p "confirm=Do you want to continue? (y/n): "
if /i not "%confirm%"=="y" (
    echo.
    echo Operation cancelled.
    echo.
    pause
    goto :menu
)

echo.
echo [%date% %time%] Starting removal process >> "%logfile%"

echo Delete Firewall Rules...
netsh advfirewall firewall delete rule name="Unifi TCP in 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi TCP out 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP in 3478,10001,5005,5514,6789" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP out 3478,10001,5005,5514,6789" >nul 2>&1
echo OK
echo [%date% %time%] Firewall rules deleted >> "%logfile%"

call :kill_processes

if %detect_network% equ 1 (
    echo.
    echo Uninstalling UniFi Network Controller...
    echo [%date% %time%] Uninstalling UniFi Network Controller >> "%logfile%"
    
    :: Stop UniFi service if running
    net stop UniFi >nul 2>&1
    echo [%date% %time%] Stopped UniFi service >> "%logfile%"
    
    :: Uninstall service using Java if available
    if exist "%ProgramFiles%\Temurin\bin\java.exe" (
        if exist "%UserProfile%\Ubiquiti UniFi\lib\ace.jar" (
            echo Removing UniFi service...
            "%ProgramFiles%\Temurin\bin\java.exe" -jar "%UserProfile%\Ubiquiti UniFi\lib\ace.jar" uninstallsvc >nul 2>&1
            echo [%date% %time%] Ran uninstallsvc command >> "%logfile%"
        )
    )
    
    :: Run the uninstaller if it exists
    set "uninstall_path=%UserProfile%\Ubiquiti UniFi\Uninstall.exe"
    if exist "!uninstall_path!" (
        echo Running UniFi uninstaller...
        echo [%date% %time%] Running Uninstall.exe >> "%logfile%"
        "!uninstall_path!" /S
        call :wait_installer "Uninstall.exe"
        timeout /t 5 /nobreak >nul
    ) else (
        echo No uninstaller found, cleaning up files...
    )
    
    :: Force remove folder after uninstallation
    timeout /t 3 /nobreak >nul
    call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
    echo OK
    echo [%date% %time%] Network Controller removal complete >> "%logfile%"
)

if %detect_os% equ 1 (
    echo.
    echo Uninstalling UniFi OS Server...
    echo [%date% %time%] Uninstalling UniFi OS Server >> "%logfile%"
    
    :: Stop containers if WSL is available
    wsl --list >nul 2>&1
    if %errorlevel% equ 0 (
        echo Stopping UniFi OS Server containers...
        wsl -d Ubuntu -u uosserver podman stop --all >nul 2>&1
        wsl -d Ubuntu -u uosserver podman rm --all >nul 2>&1
        echo [%date% %time%] Stopped containers >> "%logfile%"
        
        echo Unregistering WSL distribution...
        wsl --unregister Ubuntu >nul 2>&1
        echo [%date% %time%] Unregistered Ubuntu WSL >> "%logfile%"
    )
    
    :: Run OS Server uninstaller if it exists
    set "os_uninstaller=%UserProfile%\AppData\Local\Programs\UniFi OS Server\Uninstall UniFi OS Server.exe"
    if exist "!os_uninstaller!" (
        echo Running UniFi OS Server uninstaller...
        echo [%date% %time%] Running OS Server uninstaller >> "%logfile%"
        "!os_uninstaller!" /S
        call :wait_installer "Uninstall UniFi OS Server.exe"
        timeout /t 5 /nobreak >nul
    )
    
    :: Force remove OS Server folders
    timeout /t 3 /nobreak >nul
    call :force_remove_folder "%UserProfile%\AppData\Local\Programs\UniFi OS Server"
    call :force_remove_folder "%UserProfile%\AppData\Local\uosserver-updater"
    call :force_remove_folder "%UserProfile%\AppData\Roaming\UniFi OS Server"
    
    echo OK
    echo [%date% %time%] OS Server removal complete >> "%logfile%"
)

if %detect_java% equ 1 (
    echo.
    echo Uninstalling JRE...
    echo [%date% %time%] Uninstalling JRE >> "%logfile%"
    cd /d "%installpath%" 2>nul || cd /d "%HOMEDRIVE%\"
    set "latest_msi="
    
    :: Find the latest JRE MSI
    for /f "delims=" %%f in ('dir /b /a-d /o-d /t:c "OpenJDK*-jre_x64_windows_hotspot_*.msi" 2^>nul') do (
        set "latest_msi=%%f"
        goto :remove_jre
    )
    echo Java MSI file not found. Skipping MSI uninstall.
    goto :cleanup_folders
    
    :remove_jre
    echo Uninstalling Java MSI: !latest_msi!
    echo [%date% %time%] Uninstalling JRE MSI: !latest_msi! >> "%logfile%"
    start /wait msiexec /x "!latest_msi!" /quiet
    echo OK
    echo [%date% %time%] JRE uninstalled >> "%logfile%"
)

:cleanup_folders
echo.
echo Cleaning up residual folders...
echo [%date% %time%] Cleaning up residual folders >> "%logfile%"

:: Remove any remaining UniFi folders with force method
call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
call :force_remove_folder "%UserProfile%\AppData\Local\Programs\UniFi OS Server"
call :force_remove_folder "%UserProfile%\AppData\Local\uosserver-updater"
call :force_remove_folder "%UserProfile%\AppData\Roaming\UniFi OS Server"

:: Clean empty Programs folder
if exist "%UserProfile%\AppData\Local\Programs\" (
    dir /b "%UserProfile%\AppData\Local\Programs\" | findstr "^" >nul || (
        rd "%UserProfile%\AppData\Local\Programs" >nul 2>&1
    )
)

echo OK
echo [%date% %time%] Folder cleanup complete >> "%logfile%"

echo.
echo ===========================================
echo      REMOVAL COMPLETED SUCCESSFULLY
echo ===========================================
echo.
echo All detected components have been removed.
echo.
echo IMPORTANT: Please reboot your system to complete the process.
echo.
echo [%date% %time%] Removal process completed successfully >> "%logfile%"
pause
goto :menu

:: ===========================================
:: BACKUP CONFIGURATION
:: ===========================================

:backup
set "backup_network=0"
set "backup_os=0"

if exist "%UserProfile%\Ubiquiti UniFi\" set "backup_network=1"
if exist "%UserProfile%\AppData\Local\Programs\UniFi OS Server\" set "backup_os=1"

if %backup_network% equ 0 if %backup_os% equ 0 (
    echo No UniFi products found installed.
    echo.
    pause
    goto :menu
)

if %backup_network% equ 1 (
    set "unifidir=%UserProfile%\Ubiquiti UniFi\data\backup"
    set "product_name=UniFi Network Controller"
    set "file_pattern=*.unf"
)
if %backup_os% equ 1 (
    set "unifidir=%UserProfile%\AppData\Local\Programs\UniFi OS Server\backups"
    set "product_name=UniFi OS Server"
    set "file_pattern=*.unf"
)

if not exist "%unifidir%" (
    echo No backup directory found for %product_name%
    echo Directory: %unifidir%
    echo.
    pause
    goto :menu
)

set "backupdir=%installpath%\backup"
for /f "tokens=*" %%I in ('PowerShell -Command "Get-Date -Format 'yyyyMMdd'"') do set "date=%%I"

if not exist "%backupdir%" mkdir "%backupdir%"

set "latest="
for /f "delims=" %%F in ('dir /b /a-d /od "%unifidir%\%file_pattern%" 2^>nul') do set "latest=%%F"

if not defined latest (
    echo No backup files found for %product_name%
    echo Directory: %unifidir%
    echo Looking for: %file_pattern%
    echo.
    echo TIP: Create a backup from the UniFi Controller web interface first:
    echo Settings ^> System ^> Backup ^> Download Backup
    echo.
    pause
    goto :menu
)

set "sourcefile=%unifidir%\%latest%"
echo Latest backup found: "%latest%"
echo.

set "destfile=%backupdir%\%product_name%_backup_%date%.unf"

copy "%sourcefile%" "%destfile%" /Y
if %ERRORLEVEL% NEQ 0 (
    echo Error copying the backup file
    echo.
    pause
    goto :menu
)

echo.
echo ===========================================
echo    BACKUP COMPLETED SUCCESSFULLY
echo ===========================================
echo.
echo Source: %sourcefile%
echo Destination: %destfile%
echo.
pause
goto :menu

:: ===========================================
:: ADD IP ADDRESS
:: ===========================================

:ip
echo.
set "propsFile=%UserProfile%\Ubiquiti UniFi\data\system.properties"
if not exist "%propsFile%" (
    echo UniFi Network Controller not found
    echo Please install it first
    echo.
    pause
    goto :menu
)

set /p "system_ip=Enter the IPv4 address (e.g. 192.168.1.10): "

set "backupFile=%UserProfile%\Ubiquiti UniFi\data\system.properties.bak"
copy "%propsFile%" "%backupFile%" >nul
if %errorlevel% == 0 (
    echo Backup created successfully
) else (
    echo Error creating backup
    echo.
    pause
    goto :menu
)

findstr /R "^system_ip=" "%propsFile%" >nul
if %errorlevel% == 0 (
    echo.
    echo ERROR: The IP already exists in the config file
    echo.
    pause
    goto :menu
)

echo system_ip=%system_ip%>> "%propsFile%"
echo.
echo Reboot to apply changes
echo You can now access the URL: https://%system_ip%:8443
echo.
pause
goto :menu
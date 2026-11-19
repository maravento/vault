@echo off
:: maravento.com
:: UniFi Setup + JRE as a Service
:: FILE: unifisetup.bat
:: For Windows 10/11
:: https://www.maravento.com/2025/02/unifi-como-servicio.html
:: Access:
:: UniFi Network Controller
:: ACCESS URL: https://localhost:8443

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
for /f "tokens=*" %%I in ('powershell -Command "Get-Date -Format yyyyMMddHHmmss"') do set "datetime=%%I"
set "logname=unifi_install_%datetime:~0,8%_%datetime:~8,6%.log"
set "logfile=%logspath%\%logname%"

type nul > "%logfile%"
call :log "INFO: unifisetup start..."
call :log "INFO: unifisetup start..." con

cls
echo ===========================================
echo UNIFI INSTALLATION MANAGER
echo Log file: %logfile%
echo ===========================================

:check_admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    call :log "INFO: Requesting admin privileges"
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:check_os
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo Windows Version Detected: %VERSION%
call :log "INFO: Windows Version: %VERSION%"
if NOT "%VERSION%" == "10.0" (
   echo OS Incompatible
   call :log "ERROR: OS Incompatible - Not Windows 10/11 -abort"
   echo.
   pause
   exit /b 1
)
if NOT EXIST "%PROGRAMFILES(X86)%" (
   echo OS Incompatible
   call :log "ERROR: OS Incompatible - No x86 Program Files -abort"
   echo.
   pause
   exit /b 1
)

:check_path
if not exist "%installpath%" (
    call :log "INFO: Creating directory: %installpath%"
    mkdir "%installpath%"
)
cd /d "%installpath%" || (
    echo Failed to enter the directory: %installpath%
    call :log "ERROR: Failed to enter %installpath% -abort"
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
echo 2. Backup Configuration
echo 3. Remove UniFi + JRE
echo 4. Add IPv4 address
echo 5. Exit
echo.
set "var="
set /p "var=Write your number (1, 2, 3, 4, 5) [5] and Press ENTER: "
if not defined var (
    call :log "INFO: no option selected, exit -skip" con
    call :log "INFO: no option selected, exit -skip"
    set "var=5"
)
if "%var%"=="1" (
    call :log "INFO: User selected: Install UniFi Network Controller"
    goto :install_network
)
if "%var%"=="2" (
    call :log "INFO: User selected: Backup Configuration"
    goto :backup
)
if "%var%"=="3" (
    call :log "INFO: User selected: Remove UniFi + JRE"
    goto :remove
)
if "%var%"=="4" (
    call :log "INFO: User selected: Add IPv4 address"
    goto :ip
)
if "%var%"=="5" (
    call :log "INFO: User selected: Exit"
    exit /b 0
)
echo Invalid option. Please select a valid number from 1 to 5
call :log "WARNING: Invalid option selected: %var% -alert"
echo.
goto :menu

:: ===========================================
:: COMMON FUNCTIONS
:: ===========================================

:check_java
call :log "INFO: Checking for existing Java installation"
where java >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=3" %%v in ('java -version 2^>^&1') do (
        echo Java Version: %%v
        echo Uninstall java and run the script again
        call :log "ERROR: Java already installed: %%v -abort"
        echo.
        exit /b 1
    )
)
call :log "INFO: No existing Java found, OK to proceed"
exit /b 0

:check_curl
call :log "INFO: Checking for curl"
where curl >nul 2>&1
if %errorlevel% neq 0 (
    echo curl is not installed. Please install curl before continuing
    call :log "ERROR: curl not installed -abort"
    echo.
    pause
    exit /b 1
)
call :log "INFO: curl found, OK to proceed"
exit /b 0

:download_jre
echo.
call :log "INFO: Starting JRE download"
echo Getting the latest version of JRE...
set "jdk_major=25"
set "version_base_url=https://github.com/adoptium/temurin!jdk_major!-binaries/releases/download/"
set "version_latest_url=https://api.github.com/repos/adoptium/temurin!jdk_major!-binaries/releases/latest"
set "jdk_type=jre"
set "os_arch=x64_windows"
set "vm_type=hotspot"

call :log "INFO: Fetching JRE version info from: !version_latest_url!"
for /f "delims=" %%a in ('curl -s !version_latest_url! ^| findstr /i "tag_name"') do set "version=%%a"
for /f "tokens=2 delims=: " %%b in ("!version!") do set "version=%%b"
set "version=!version:jdk-=!"
set "version=!version:~1,-2!"
echo Latest version: !version!
call :log "INFO: JRE version detected: !version!"

set "file_version=!version!"
for /l %%i in (1,1,10) do set "file_version=!file_version:+=_!"

set "download_url=!version_base_url!jdk-!version!/OpenJDK!jdk_major!U-!jdk_type!_!os_arch!_!vm_type!_!file_version!.msi"
set "msi_filename=OpenJDK!jdk_major!U-!jdk_type!_!os_arch!_!vm_type!_!file_version!.msi"

call :log "INFO: Download URL: !download_url!"
cd /d "%installpath%" || exit /b 1
call :log "INFO: Downloading JRE to: %installpath%\!msi_filename!"
curl -# -L -o "!msi_filename!" "!download_url!"
set "curl_error=!errorlevel!"
if !curl_error! NEQ 0 (
    echo Error downloading JRE
    call :log "ERROR: JRE download failed with error !curl_error! -abort"
    exit /b 1
)
call :log "INFO: JRE download successful: !msi_filename!"
echo OK
exit /b 0

:install_jre
echo.
call :log "INFO: Installing JRE..."
echo Installing JRE...
cd /d "%installpath%" || exit /b 1
set "latest_msi=OpenJDK!jdk_major!U-!jdk_type!_!os_arch!_!vm_type!_!file_version!.msi"
call :log "INFO: Installing MSI: !latest_msi!"
start /wait msiexec /i "!latest_msi!" ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome INSTALLDIR="%ProgramFiles%\Temurin" /quiet >nul 2>&1
set "msi_error=!errorlevel!"
if !msi_error! NEQ 0 (
    echo Error installing JRE
    call :log "ERROR: JRE installation failed with error !msi_error! -abort"
    exit /b 1
)
call :log "INFO: JRE installation successful"
echo OK
exit /b 0

:setup_firewall
echo.
call :log "INFO: Configuring UniFi Firewall Rules..."
echo Configuring UniFi Firewall Rules...
netsh advfirewall firewall add rule name="Unifi TCP in 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" protocol=TCP dir=in localport=8080,8443,8880,8843,8444,8881,8882,9543,10003,11443 action=allow >nul 2>&1
call :log "INFO: Added firewall rule: Unifi TCP in"
netsh advfirewall firewall add rule name="Unifi TCP out 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" protocol=TCP dir=out localport=8080,8443,8880,8843,8444,8881,8882,9543,10003,11443 action=allow >nul 2>&1
call :log "INFO: Added firewall rule: Unifi TCP out"
netsh advfirewall firewall add rule name="Unifi UDP in 3478,10001,5005,5514,6789" protocol=UDP dir=in localport=3478,10001,5005,5514,6789 action=allow >nul 2>&1
call :log "INFO: Added firewall rule: Unifi UDP in"
netsh advfirewall firewall add rule name="Unifi UDP out 3478,10001,5005,5514,6789" protocol=UDP dir=out localport=3478,10001,5005,5514,6789 action=allow >nul 2>&1
call :log "INFO: Added firewall rule: Unifi UDP out"
echo OK
exit /b 0

:kill_processes
echo.
call :log "INFO: Stopping UniFi processes..."
echo Stopping UniFi processes...
powershell -NoProfile -Command "$p = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'java.exe' -and $_.ExecutablePath -like ($env:ProgramFiles + '\Temurin\*') -and $_.CommandLine -like '*ace.jar*' }; if (-not $p) { exit 1 }; $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1 && call :log "INFO: Killed: java.exe (UniFi)"
taskkill /f /im "UniFi.exe" >nul 2>&1 && call :log "INFO: Killed: UniFi.exe"
taskkill /f /im "UniFi-installer.exe" >nul 2>&1 && call :log "INFO: Killed: UniFi-installer.exe"
taskkill /f /im "Uninstall.exe" >nul 2>&1 && call :log "INFO: Killed: Uninstall.exe"
timeout /t 2 /nobreak >nul
call :log "INFO: Process stopping complete"
exit /b 0

:final_installation
echo.
call :log "INFO: Installation Complete!"
cls
echo ===========================================
echo        INSTALLATION COMPLETE
echo ===========================================
echo.
echo PRODUCT: UniFi Network Controller
echo ACCESS URL: https://localhost:8443
call :log "INFO: UniFi Network Controller installed at: https://localhost:8443"

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
call :log "INFO: Installation finished successfully"
echo =========================================== >> "%logfile%"
call :log "INFO: unifisetup done"
call :log "INFO: unifisetup done" con
exit /b 0

:: ===========================================
:: VERSION SELECTION FUNCTION 
:: ===========================================

:get_version_selection
set "json_file=%~1"
set "product_type=%~2"

call :log "INFO: Getting version selection for: %product_type%"

set "version_latest="
set "version_previous="
set "selected_version="
set "selected_url="

if "%product_type%"=="network" (
    call :log "INFO: Getting Network Controller versions..."
    
    REM Get all versions, sort by version number (descending)
    powershell -Command "$versions = (Get-Content '%json_file%' | ConvertFrom-Json).downloads | Where-Object { $_.name -like '*UniFi Network Application*Windows*' } | Select-Object -ExpandProperty version -Unique | ForEach-Object { [version]$_ } | Sort-Object -Descending; $versions | ForEach-Object { $_.ToString() }" > "%installpath%\network_versions.txt"
    
    REM Get latest version (first line = highest version)
    for /f "delims=" %%v in ('type "%installpath%\network_versions.txt"') do (
        if not defined version_latest (
            set "version_latest=%%v"
            for /f "tokens=1 delims=." %%m in ("%%v") do set "latest_major=%%m"
        )
    )
    
    REM Find the latest version from a different major version
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
    call :log "INFO: Network - Latest: !version_latest!, Previous: !version_previous!"
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
call :log "INFO: User choice: !choice!"

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
)

if !version_exists! equ 0 (
    echo Version !custom_ver! not found in available versions.
    call :log "WARNING: Custom version not found: !custom_ver! -alert"
    echo.
    goto :version_menu
)

:get_version_url
call :log "INFO: Selected version: !selected_version!"

:: Get download URL for selected version
if "%product_type%"=="network" (
    REM For Network Controller - simple URL format
    set "selected_url=https://dl.ui.com/unifi/!selected_version!/UniFi-installer.exe"
    call :log "INFO: Network download URL: !selected_url!"
)

:: Cleanup temp files
if exist "%installpath%\network_versions.txt" del "%installpath%\network_versions.txt"

exit /b 0

:cancel_version
:: Cleanup and return to menu
if exist "%installpath%\network_versions.txt" del "%installpath%\network_versions.txt"
call :log "INFO: User cancelled version selection"
exit /b 1

:wait_installer
set "process_name=%~1"
call :log "INFO: Waiting for installer: %process_name%"
:wait_loop
timeout /t 10 /nobreak >nul
tasklist /fi "imagename eq %process_name%" 2>nul | find /i "%process_name%" >nul
if %errorlevel% equ 0 goto wait_loop
call :log "INFO: Installer finished: %process_name%"
exit /b 0

:: ===========================================
:: FORCE REMOVE FOLDER FUNCTION
:: ===========================================

:force_remove_folder
set "folder_to_remove=%~1"
if not exist "!folder_to_remove!" exit /b 0

call :log "INFO: Force removing folder: !folder_to_remove!"
echo Removing: !folder_to_remove!

:: Method 1: Try normal removal first
rd /s /q "!folder_to_remove!" >nul 2>&1
if not exist "!folder_to_remove!" (
    call :log "INFO: Successfully removed with rd command"
    exit /b 0
)

:: Method 2: Take ownership and remove
echo Taking ownership and retrying...
takeown /f "!folder_to_remove!" /r /d y >nul 2>&1
icacls "!folder_to_remove!" /grant "%username%":F /t /q >nul 2>&1
rd /s /q "!folder_to_remove!" >nul 2>&1
if not exist "!folder_to_remove!" (
    call :log "INFO: Successfully removed with takeown"
    exit /b 0
)

:: Method 3: Use PowerShell to force delete
echo Using PowerShell to force delete...
powershell -Command "if (Test-Path '!folder_to_remove!') { Remove-Item -Path '!folder_to_remove!' -Recurse -Force -ErrorAction SilentlyContinue }" >nul 2>&1
timeout /t 2 /nobreak >nul
if not exist "!folder_to_remove!" (
    call :log "INFO: Successfully removed with PowerShell"
    exit /b 0
)

:: Method 4: Kill any processes that might be locking files
echo Stopping processes that might lock the folder...
call :kill_processes
timeout /t 3 /nobreak >nul
rd /s /q "!folder_to_remove!" >nul 2>&1
if not exist "!folder_to_remove!" (
    call :log "INFO: Successfully removed after killing processes"
    exit /b 0
)

:: Final check
if exist "!folder_to_remove!" (
    echo.
    echo WARNING: Could not completely remove: !folder_to_remove!
    echo The folder may contain locked files or require a system restart.
    call :log "WARNING: Could not remove folder: !folder_to_remove!"
    echo.
    echo The script will continue, but please manually delete this folder after reboot.
    timeout /t 3
) else (
    call :log "INFO: Successfully removed folder: !folder_to_remove!"
)
exit /b 0

:: ===========================================
:: UNIFI NETWORK CONTROLLER INSTALLATION
:: ===========================================

:install_network
echo =========================================== >> "%logfile%"
call :log "INFO: STARTING UNIFI NETWORK CONTROLLER INSTALLATION"
echo =========================================== >> "%logfile%"

:: Check if UniFi service is running
sc query "UniFi" >nul 2>&1
if %errorlevel% equ 0 (
    echo UniFi Network Controller service is running.
    echo Please uninstall UniFi first using option 3.
    call :log "ERROR: UniFi service is running -abort"
    echo.
    exit /b 1
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
    
    REM Check if it's a complete installation
    if exist "%UserProfile%\Ubiquiti UniFi\Uninstall.exe" (
        echo This appears to be a complete UniFi installation.
        echo Please use option 3 to uninstall it first.
        call :log "ERROR: Complete UniFi installation found -abort"
        echo.
        exit /b 1
    )
    
    REM It's incomplete or leftover - offer to clean
    echo This appears to be an incomplete or leftover installation.
    echo.
    echo Options:
    echo 1. Clean up and continue with fresh installation
    echo 2. Cancel and exit
    echo.
    set "cleanup_choice="
    set /p "cleanup_choice=Enter your choice (1 or 2) [2]: "
    if not defined cleanup_choice (
        call :log "INFO: no option selected, exit -skip" con
        call :log "INFO: no option selected, exit -skip"
        set "cleanup_choice=2"
    )
    
    if "!cleanup_choice!"=="1" (
        echo.
        echo Cleaning up incomplete installation...
        call :log "INFO: User chose to clean up incomplete installation"
        call :kill_processes
        call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
        
        REM Verify removal
        if exist "%UserProfile%\Ubiquiti UniFi\" (
            echo.
            echo ERROR: Could not remove the folder completely.
            echo Please manually delete: %UserProfile%\Ubiquiti UniFi\
            echo Then run the script again.
            call :log "ERROR: Failed to clean up folder -abort"
            echo.
            exit /b 1
        )
        
        echo Cleanup successful! Continuing with installation...
        call :log "INFO: Cleanup successful, proceeding with installation"
        timeout /t 2 /nobreak >nul
    ) else (
        echo Installation cancelled.
        call :log "INFO: User cancelled installation"
        echo.
        exit /b 1
    )
)

:check_java_network
call :check_java
if errorlevel 1 exit /b 1

call :check_curl
if errorlevel 1 exit /b 1

echo.
echo Getting available versions of UniFi Network...
curl -s https://download.svc.ui.com/v1/software-downloads > temp_network.json
call :log "INFO: Downloaded version info to temp_network.json"

call :get_version_selection "temp_network.json" "network"
if errorlevel 1 (
    del temp_network.json
    call :log "ERROR: Version selection cancelled or failed -abort"
    exit /b 1
)

echo.
echo Downloading UniFi Network version !selected_version!...
call :log "INFO: Downloading UniFi Network version: !selected_version!"
cd /d "%installpath%" || (
    del temp_network.json
    call :log "ERROR: Failed to change to install directory -abort"
    exit /b 1
)
curl -# -L -o "UniFi-installer.exe" "!selected_url!"
set "unifi_dl_error=!errorlevel!"
if !unifi_dl_error! neq 0 (
    echo Error downloading UniFi Network.
    call :log "ERROR: UniFi download failed with error !unifi_dl_error! -abort"
    del temp_network.json
    echo.
    exit /b 1
)

del temp_network.json
echo OK
call :log "INFO: UniFi download successful: UniFi-installer.exe"

echo.
echo Installing UniFi Network...
call :log "INFO: Running UniFi installer..."
"%installpath%\UniFi-installer.exe" /S

call :wait_installer "UniFi-installer.exe"

call :log "INFO: Creating UniFi data directory..."
mkdir "%UserProfile%\Ubiquiti UniFi\data" 2>nul
(
echo debug.device=warn
echo debug.mgmt=warn
echo debug.sdn=warn
echo debug.setting_preference=auto
echo debug.system=warn
) > "%installpath%\system.properties"
copy "%installpath%\system.properties" "%UserProfile%\Ubiquiti UniFi\data" >nul 2>&1
call :log "INFO: Created system.properties configuration file"
echo OK

call :log "INFO: Starting JRE installation phase"
call :download_jre
if errorlevel 1 (
    call :log "ERROR: JRE download failed -abort"
    goto :cleanup_network
)

call :install_jre
if errorlevel 1 (
    call :log "ERROR: JRE installation failed -abort"
    goto :cleanup_network
)

echo.
echo Setting up UniFi Network as a Service...
call :log "INFO: Setting up UniFi as Windows Service..."
cd "%UserProfile%\Ubiquiti UniFi\" || (
    echo Failed to change directory
    call :log "ERROR: Failed to change to UniFi directory -abort"
    goto :cleanup_network
)
set "JAVA_PATH=%ProgramFiles%\Temurin\bin\java.exe"
call :log "INFO: Java path: %JAVA_PATH%"

call :log "INFO: Running: %JAVA_PATH% -jar lib\ace.jar startsvc"
"%JAVA_PATH%" -jar lib\ace.jar startsvc
timeout /t 5 /nobreak >nul
call :log "INFO: Running: %JAVA_PATH% -jar lib\ace.jar installsvc"
"%JAVA_PATH%" -jar lib\ace.jar installsvc >nul 2>&1
set "service_error=!errorlevel!"
if !service_error! neq 0 (
    echo Error setting up service
    call :log "ERROR: Service setup failed with error !service_error! -abort"
    goto :cleanup_network
)
call :log "INFO: Service setup successful"
echo OK

call :setup_firewall

call :log "INFO: UNIFI NETWORK CONTROLLER INSTALLATION COMPLETE"
goto :final_installation

:cleanup_network
echo Installation failed. Cleaning up...
call :log "ERROR: INSTALLATION FAILED - CLEANING UP -abort"
call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
call :log "INFO: Cleanup complete, exiting"
exit /b 1

:: ===========================================
:: REMOVE UNIFI + JRE FUNCTION
:: ===========================================

:remove
set "detect_network=0"
set "detect_java=0"
set "found_any_folder=0"

:: Check for UniFi Network folders (even if empty or incomplete)
if exist "%UserProfile%\Ubiquiti UniFi\" (
    set "detect_network=1"
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
    call :log "INFO: unifisetup done"
    call :log "INFO: unifisetup done" con
    exit /b 0
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
if %detect_java% equ 1 echo - Java JRE (Temurin)
echo.
echo WARNING: This action cannot be undone!
echo.
set /p "confirm=Do you want to continue? (y/n): "
if /i not "%confirm%"=="y" (
    echo.
    echo Operation cancelled.
    echo.
    exit /b 1
)

echo.
call :log "INFO: Starting removal process"

echo Delete Firewall Rules...
netsh advfirewall firewall delete rule name="Unifi TCP in 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi TCP out 8080,8443,8880,8843,8444,8881,8882,9543,10003,11443" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP in 3478,10001,5005,5514,6789" >nul 2>&1
netsh advfirewall firewall delete rule name="Unifi UDP out 3478,10001,5005,5514,6789" >nul 2>&1
echo OK
call :log "INFO: Firewall rules deleted"

call :kill_processes

if %detect_network% equ 1 (
    echo.
    echo Uninstalling UniFi Network Controller...
    call :log "INFO: Uninstalling UniFi Network Controller"
    
    REM Stop UniFi service if running
    net stop UniFi >nul 2>&1
    call :log "INFO: Stopped UniFi service"
    
    REM Uninstall service using Java if available
    if exist "%ProgramFiles%\Temurin\bin\java.exe" (
        if exist "%UserProfile%\Ubiquiti UniFi\lib\ace.jar" (
            echo Removing UniFi service...
            "%ProgramFiles%\Temurin\bin\java.exe" -jar "%UserProfile%\Ubiquiti UniFi\lib\ace.jar" uninstallsvc >nul 2>&1
            call :log "INFO: Ran uninstallsvc command"
        )
    )
    
    REM Run the uninstaller if it exists
    set "uninstall_path=%UserProfile%\Ubiquiti UniFi\Uninstall.exe"
    if exist "!uninstall_path!" (
        echo Running UniFi uninstaller...
        call :log "INFO: Running Uninstall.exe"
        "!uninstall_path!" /S
        call :wait_installer "Uninstall.exe"
        timeout /t 5 /nobreak >nul
    ) else (
        echo No uninstaller found, cleaning up files...
    )
    
    REM Force remove folder after uninstallation
    timeout /t 3 /nobreak >nul
    call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"
    echo OK
    call :log "INFO: Network Controller removal complete"
)

if %detect_java% equ 1 (
    echo.
    echo Uninstalling JRE...
    call :log "INFO: Uninstalling JRE"
    cd /d "%installpath%" 2>nul || cd /d "%HOMEDRIVE%\"
    set "latest_msi="
    
    REM Find the latest JRE MSI
    for /f "delims=" %%f in ('dir /b /a-d /o-d /t:c "OpenJDK*-jre_x64_windows_hotspot_*.msi" 2^>nul') do (
        set "latest_msi=%%f"
        goto :remove_jre
    )
    echo Java MSI file not found. Skipping MSI uninstall.
    goto :cleanup_folders
    
    :remove_jre
    echo Uninstalling Java MSI: !latest_msi!
    call :log "INFO: Uninstalling JRE MSI: !latest_msi!"
    start /wait msiexec /x "!latest_msi!" /quiet
    echo OK
    call :log "INFO: JRE uninstalled"
)

:cleanup_folders
echo.
echo Cleaning up residual folders...
call :log "INFO: Cleaning up residual folders"

:: Remove any remaining UniFi folders with force method
call :force_remove_folder "%UserProfile%\Ubiquiti UniFi"

:: Clean empty Programs folder
if exist "%UserProfile%\AppData\Local\Programs\" (
    dir /b "%UserProfile%\AppData\Local\Programs\" | findstr "^" >nul || (
        rd "%UserProfile%\AppData\Local\Programs" >nul 2>&1
    )
)

echo OK
call :log "INFO: Folder cleanup complete"

echo.
echo ===========================================
echo      REMOVAL COMPLETED SUCCESSFULLY
echo ===========================================
echo.
echo All detected components have been removed.
echo.
echo IMPORTANT: Please reboot your system to complete the process.
echo.
call :log "INFO: Removal process completed successfully"
call :log "INFO: unifisetup done"
call :log "INFO: unifisetup done" con
exit /b 0

:: ===========================================
:: BACKUP CONFIGURATION
:: ===========================================

:backup
set "backup_network=0"

if exist "%UserProfile%\Ubiquiti UniFi\" set "backup_network=1"

if %backup_network% equ 0 (
    echo No UniFi products found installed.
    echo.
    exit /b 1
)

set "unifidir=%UserProfile%\Ubiquiti UniFi\data\backup"
set "product_name=UniFi Network Controller"
set "file_pattern=*.unf"

if not exist "%unifidir%" (
    echo No backup directory found for %product_name%
    echo Directory: %unifidir%
    echo.
    exit /b 1
)

set "backupdir=%installpath%\backup"
for /f "tokens=*" %%I in ('PowerShell -Command "Get-Date -Format 'yyyyMMdd'"') do set "backup_date=%%I"

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
    exit /b 1
)

set "sourcefile=%unifidir%\%latest%"
echo Latest backup found: "%latest%"
echo.

set "destfile=%backupdir%\%product_name%_backup_%backup_date%.unf"

copy "%sourcefile%" "%destfile%" /Y
if %ERRORLEVEL% NEQ 0 (
    echo Error copying the backup file
    echo.
    exit /b 1
)

echo.
echo ===========================================
echo    BACKUP COMPLETED SUCCESSFULLY
echo ===========================================
echo.
echo Source: %sourcefile%
echo Destination: %destfile%
echo.
call :log "INFO: unifisetup done"
call :log "INFO: unifisetup done" con
exit /b 0

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
    exit /b 1
)

set "system_ip="
set /p "system_ip=Enter the IPv4 address (e.g. 192.168.1.10): "
if "%system_ip%"=="" (
    echo IPv4 address cannot be empty
    call :log "ERROR: IPv4 address cannot be empty -abort"
    exit /b 1
)

set "backupFile=%UserProfile%\Ubiquiti UniFi\data\system.properties.bak"
copy "%propsFile%" "%backupFile%" >nul
if %errorlevel% == 0 (
    echo Backup created successfully
) else (
    echo Error creating backup
    echo.
    exit /b 1
)

findstr /R "^system_ip=" "%propsFile%" >nul
if %errorlevel% == 0 (
    echo.
    echo ERROR: The IP already exists in the config file
    echo.
    exit /b 1
)

echo system_ip=%system_ip%>> "%propsFile%"
echo.
echo Reboot to apply changes
echo You can now access the URL: https://%system_ip%:8443
echo.
call :log "INFO: unifisetup done"
call :log "INFO: unifisetup done" con
exit /b 0


:: ===========================================
:: LOG
:: ===========================================
:: arg 1 message, arg 2 "con" prints to console instead of the log; keeps ERRORLEVEL
:log
set "log_rc=%errorlevel%"
set "log_ts="
for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "log_ts=%%I"
if /i "%~2"=="con" goto :log_con
>> "%logfile%" echo %log_ts% %~1
exit /b %log_rc%
:log_con
echo %log_ts% %~1
exit /b %log_rc%

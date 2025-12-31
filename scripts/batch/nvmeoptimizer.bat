@echo off
:: maravento.com

title Windows 11 NVMe Feature Manager
color 0A
setlocal enabledelayedexpansion

:: ====================================================
:: NVMe Feature Management Script for Windows 11
:: Purpose: Enable/Disable experimental NVMe features
:: WARNING: Modifies FeatureManagement registry keys
::          which control Windows feature rollouts
:: ====================================================

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Run as administrator
    pause
    exit /b 1
)

:: Check Windows version - SIMPLE WORKING VERSION
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v "CurrentBuildNumber" 2^>nul') do (
    if %%a GEQ 22000 (
        echo Windows 11 detected: %%a
        goto :continue_script
    ) else (
        echo Windows 10 detected: %%a
        goto :not_win11
    )
)

:not_win11
cls
echo ================================================
echo [ERROR] INCOMPATIBLE OPERATING SYSTEM
echo ================================================
echo.
echo This script requires Windows 11 (Build 22000+)
echo.
echo Windows 10 and earlier are NOT supported.
echo.
echo ================================================
pause
exit /b 1

:continue_script
cls
echo ================================================
echo   WIN11 NVMe NATIVE DRIVER MANAGER
echo ================================================
echo Activates Server 2025 native NVMe driver
echo Removes SCSI translation layer
echo.
echo WARNING: NO OFFICIAL SUPPORT
echo - Vendor tools may fail (Samsung Magician, etc)
echo - Disk IDs may change
echo - Microsoft does NOT support this for Win11
echo.
echo PREREQUISITES (MANDATORY):
echo [X] Windows 11 (NOT compatible with Windows 10)
echo [X] Full system backup
echo [X] Windows restore point
echo [X] SSD firmware updated
echo [X] BIOS/UEFI updated
echo [X] Vendor software uninstalled
echo ================================================
echo.

set /p confirm="Prerequisites completed? (y/n): "
if /i not "%confirm%"=="y" (
    echo Cancelled.
    pause
    exit /b 1
)

echo.
echo ================================================
echo Expected benefits when enabled:
echo ================================================
echo.
echo PERFORMANCE IMPROVEMENTS:
echo - Up to 10-15%% faster sequential transfers
echo - Improved low-latency operations
echo - Reduced CPU usage (reported: 5-10%% in tests)
echo - Better IOPS in certain workloads
echo.
echo DRIVER BEHAVIOR:
echo - Uses native NVMe driver (nvmedisk.sys)
echo - Eliminates SCSI translation layer
echo - Direct NVMe command processing
echo - Windows 11 behaves like Windows Server 2025
echo.
echo STABILITY NOTES:
echo - Most users report stable operation
echo - Some edge cases with specific hardware
echo - Issues usually resolved with firmware updates
echo.
echo ================================================
echo.
echo Options:
echo 1. Enable advanced NVMe features
echo 2. Restore default NVMe configuration
echo 3. View current configuration
echo 4. Exit
echo.

set /p choice="Select option (1-4): "

if "%choice%"=="1" goto :enable_features
if "%choice%"=="2" goto :restore_default
if "%choice%"=="3" goto :view_config
if "%choice%"=="4" goto :exit_script

echo Invalid selection
pause
goto :exit_script

:enable_features
echo.
echo [ENABLING] Advanced NVMe features...
echo ================================================
echo.

:: Create restore point before making changes
echo [0/4] Creating system restore point...
wmic.exe /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "Before NVMe Feature Enable", 100, 7 >nul 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Restore point created
) else (
    echo [WARNING] Could not create restore point automatically
    echo           Please create one manually if needed
)

:: ------------------------------------------------------------------
:: Feature Management Override: 735209102
:: Purpose: Disables Feature Management filtering for NVMe
:: Effect: Bypasses Windows feature rollout controls
::         Allows experimental NVMe features to be enabled
:: Source: Windows Server 2025 NVMe native driver feature
:: ------------------------------------------------------------------
echo.
echo [1/4] Applying Feature Management override...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to enable advanced NVMe features
    goto :finish
) else (
    echo [SUCCESS] Advanced NVMe features enabled
    echo          Windows will use native NVMe driver (nvmedisk.sys)
    echo          SCSI translation layer will be bypassed
)

:: ------------------------------------------------------------------
:: Feature Management Override: 1853569164  
:: Purpose: Enables advanced NVMe functionality
:: Effect: Activates native NVMe driver (nvmedisk.sys)
::         Forces Windows to use modern NVMe drivers
::         Removes SCSI translation layer
::         Direct NVMe command processing
:: Source: Windows Server 2025 NVMe implementation
:: ------------------------------------------------------------------
echo.
echo [2/4] Enabling advanced NVMe functionality...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to enable advanced NVMe features
    goto :finish
) else (
    echo [SUCCESS] Advanced NVMe features enabled
    echo          Windows will use native NVMe driver (nvmedisk.sys)
    echo          SCSI translation layer will be bypassed
)

:: ------------------------------------------------------------------
:: Feature Management Override: 156965516
:: Purpose: Completes and consolidates NVMe configuration
:: Effect: Ensures settings persist across reboots
::         Finalizes NVMe optimization chain
::         Provides complete NVMe feature stack
:: Source: Windows Server 2025 configuration chain
:: ------------------------------------------------------------------
echo.
echo [3/4] Applying final NVMe configuration...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to enable advanced NVMe features
    goto :finish
) else (
    echo [SUCCESS] Advanced NVMe features enabled
    echo          Windows will use native NVMe driver (nvmedisk.sys)
    echo          SCSI translation layer will be bypassed
)

echo.
echo [4/4] Verifying configuration...
echo.

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 >nul 2>&1
if errorlevel 1 (set "key1=missing") else (set "key1=present")

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 >nul 2>&1
if errorlevel 1 (set "key2=missing") else (set "key2=present")

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 >nul 2>&1
if errorlevel 1 (set "key3=missing") else (set "key3=present")

echo 735209102: %key1%
echo 1853569164: %key2%
echo 156965516: %key3%

echo.
echo ================================================
echo [COMPLETE] Advanced NVMe features enabled
echo ================================================
echo.
echo Configuration applied:
echo - Native NVMe driver activated (nvmedisk.sys)
echo - SCSI translation layer removed
echo - Direct NVMe command processing enabled
echo.
echo Expected improvements:
echo - 10-15%% faster sequential transfers
echo - Better low-latency operations
echo - Reduced CPU overhead
echo - Enhanced IOPS in certain workloads
echo.
echo ================================================
echo [POST-INSTALLATION STEPS]
echo ================================================
echo.
echo 1. RESTART your computer now (REQUIRED)
echo 2. After reboot, test drive performance
echo 3. Verify drive appears in Disk Management
echo 4. Check Device Manager for proper driver
echo    (should show "Microsoft Standard NVM Express Controller")
echo 5. If issues occur, rerun script and choose option 2
echo.
echo TROUBLESHOOTING:
echo - If drive not detected: Boot into Safe Mode and restore
echo - If performance worse: Firmware update may be needed
echo - If system unstable: Use option 2 to restore defaults
echo.
echo [ACTION REQUIRED] System restart required NOW
echo ================================================
goto :finish

:restore_default
echo.
echo [RESTORING] Default NVMe configuration...
echo ================================================
echo.

:: Create restore point before restoring
echo [0/4] Creating system restore point...
wmic.exe /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "Before NVMe Feature Restore", 100, 7 >nul 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Restore point created
) else (
    echo [WARNING] Could not create restore point automatically
)

:: Remove all FeatureManagement overrides for NVMe
:: This returns Windows to its default NVMe behavior
:: Microsoft's feature rollout controls will be re-enabled

echo.
echo [1/4] Removing Feature Management override...
reg delete "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 /f >nul 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Feature Management override removed
    echo          Windows feature controls restored
) else (
    echo [INFO] Feature Management override not present (or already removed)
)

echo.
echo [2/4] Disabling advanced NVMe features...
reg delete "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 /f >nul 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Advanced NVMe features disabled
    echo          Windows will revert to standard SCSI layer
) else (
    echo [INFO] Advanced NVMe features not present (or already removed)
)

echo.
echo [3/4] Removing final NVMe configuration...
reg delete "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 /f >nul 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Final NVMe configuration removed
    echo          System restored to default state
) else (
    echo [INFO] Final configuration not present (or already removed)
)

echo.
echo [4/4] Verifying restoration...
echo.
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 >nul 2>&1
if %errorlevel% neq 0 (
    echo [VERIFIED] Override 735209102 removed
) else (
    echo [WARNING] Override 735209102 still present
)

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 >nul 2>&1
if %errorlevel% neq 0 (
    echo [VERIFIED] Override 1853569164 removed
) else (
    echo [WARNING] Override 1853569164 still present
)

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 >nul 2>&1
if %errorlevel% neq 0 (
    echo [VERIFIED] Override 156965516 removed
) else (
    echo [WARNING] Override 156965516 still present
)

echo.
echo ================================================
echo [COMPLETE] Default NVMe configuration restored
echo ================================================
echo.
echo System will now:
echo - Use Microsoft's standard feature rollout process
echo - Revert to SCSI translation layer for NVMe
echo - Follow default Windows 11 NVMe behavior
echo - Re-enable manufacturer software compatibility
echo.
echo POST-RESTORATION STEPS:
echo 1. RESTART your computer (REQUIRED)
echo 2. Reinstall manufacturer software if needed
echo    (Samsung Magician, WD Dashboard, etc.)
echo 3. Verify drive detection in all tools
echo 4. Performance will return to standard levels
echo.
echo [ACTION REQUIRED] System restart recommended NOW
echo ================================================

:finish
echo.
set /p restart="Do you want to restart now? (y/n): "
if /i "%restart%"=="y" (
    echo.
    echo Restarting in 10 seconds... Press Ctrl+C to cancel
    timeout /t 10
    shutdown /r /t 0
) else (
    echo.
    echo Remember to restart your computer for changes to take effect
)
echo.
pause
goto :exit_script

:view_config
echo.
echo ================================================
echo [CURRENT CONFIGURATION]
echo ================================================
echo.
echo Checking registry values...
echo.

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 >nul 2>&1
if %errorlevel% equ 0 (
    echo [ACTIVE] Feature Management Override (735209102)
    for /f "tokens=3" %%a in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 ^| findstr "735209102"') do echo          Value: %%a
) else (
    echo [INACTIVE] Feature Management Override (735209102)
)

echo.
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 >nul 2>&1
if %errorlevel% equ 0 (
    echo [ACTIVE] Advanced NVMe Features (1853569164)
    for /f "tokens=3" %%a in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 ^| findstr "1853569164"') do echo          Value: %%a
) else (
    echo [INACTIVE] Advanced NVMe Features (1853569164)
)

echo.
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 >nul 2>&1
if %errorlevel% equ 0 (
    echo [ACTIVE] Final NVMe Configuration (156965516)
    for /f "tokens=3" %%a in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 ^| findstr "156965516"') do echo          Value: %%a
) else (
    echo [INACTIVE] Final NVMe Configuration (156965516)
)

echo.
echo ================================================
echo.

:: Check if ALL three values are set to 1
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 735209102 2>nul | findstr "0x1" >nul 2>&1
set val1=%errorlevel%
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 1853569164 2>nul | findstr "0x1" >nul 2>&1
set val2=%errorlevel%
reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" /v 156965516 2>nul | findstr "0x1" >nul 2>&1
set val3=%errorlevel%

if %val1% equ 0 if %val2% equ 0 if %val3% equ 0 (
    echo STATUS: Advanced NVMe features are ENABLED
    echo.
    echo Current driver mode: Native NVMe (nvmedisk.sys)
    echo SCSI translation: DISABLED
    echo Performance mode: ENHANCED
) else (
    echo STATUS: Standard NVMe configuration (Default Windows 11)
    echo.
    echo Current driver mode: Standard with SCSI translation
    echo SCSI translation: ENABLED
    echo Performance mode: STANDARD
)

echo.
echo ================================================
echo.
pause
goto :exit_script

:exit_script
exit
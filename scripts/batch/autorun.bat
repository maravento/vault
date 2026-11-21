@echo off
:: maravento.com

:: Autorun Control
:: FILE: autorun.bat
:: For Windows 10/11

:: NOTE: In Windows 10/11, autorun.inf execution on removable/USB drives
:: is disabled by default at the system level, regardless of this registry value.
:: Disable enforces NoDriveTypeAutoRun=0xFF, in case a malware, app, or user
:: action has enabled Autorun. Enable removes only that 0xFF block, so Windows
:: applies its default; any other custom policy value is kept.

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set "KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"

:Menu
cls
echo.
echo AUTORUN CONTROL
echo.
echo 1. Enable AutoRun
echo 2. Disable AutoRun
echo 3. Exit
echo.
set "var="
set /p "var=Option [3]: "
if not defined var set "var=3"
if "%var%"=="1" goto :Enable
if "%var%"=="2" goto :Disable
if "%var%"=="3" goto :End
echo Invalid option -retry
pause
goto :Menu

:: Reads the current value; empty when the value does not exist
:ReadValue
set "VALUE="
for /f "tokens=3" %%V in ('reg query "%KEY%" /v NoDriveTypeAutoRun 2^>nul ^| find "NoDriveTypeAutoRun"') do set "VALUE=%%V"
exit /b 0

:Enable
call :ReadValue
if not defined VALUE (
    echo.
    echo AutoRun already uses the Windows default.
    goto :End
)
if /i not "%VALUE%"=="0xff" (
    echo.
    echo Custom policy found: NoDriveTypeAutoRun=%VALUE%. Kept unchanged.
    goto :End
)
reg delete "%KEY%" /v NoDriveTypeAutoRun /f >nul
if errorlevel 1 (
    echo.
    echo ERROR: Failed to delete registry value.
    goto :End
)
echo.
echo AutoRun block removed. Windows default applies.
echo Restart your PC to apply the change.
goto :End

:Disable
call :ReadValue
if /i "%VALUE%"=="0xff" (
    echo.
    echo Autorun is already disabled.
    goto :End
)
reg add "%KEY%" /v NoDriveTypeAutoRun /t REG_DWORD /d 0xFF /f >nul
if errorlevel 1 (
    echo.
    echo ERROR: Failed to write registry value.
    goto :End
)
echo.
echo Autorun disabled successfully.
echo Restart your PC to apply the change.
goto :End

:End
echo.
pause
exit /b

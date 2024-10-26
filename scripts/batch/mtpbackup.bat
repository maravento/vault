@echo off
:: by maravento.com

:: Thunderbird Email Profiles Backup
:: for win 10/11

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Source folder path
set "source_folder=%APPDATA%\Thunderbird\Profiles"

:: Enter the USB drive letter
echo.
echo Thunderbird Email Profiles Backup
echo.
set /p usb_letter=Enter the USB letter / Ingrese la letra de la USB (example E): 

echo Log File: %usb_letter%:\profiles_bk.txt

:: Check if USB drive is available
if exist "%usb_letter%:\" (
    echo USB drive is available at %usb_letter%:\

    :: Create Profiles folder on USB drive if it does not exist
    if not exist "%usb_letter%:\Profiles" (
        echo Creating Profiles folder on USB drive...
        mkdir "%usb_letter%:\Profiles"
        echo Profiles folder created on USB drive
    ) else (
        echo Profiles folder already exists on the USB drive
    )

    echo Running the backup...

    :: Copy Profiles folder to USB drive
    robocopy "%source_folder%" "%usb_letter%:\Profiles" /E /COPYALL /MIR /IS /IT /TEE /ETA /R:10 /W:5 /ZB /V /LOG:"%usb_letter%:\profiles_bk.txt"

    :: Check for errors during copying
    if %errorlevel% gtr 0 (
        echo Error copying folder to USB drive
    ) else (
        echo Folder successfully copied to %usb_letter%:\
        echo Check the profiles_bk.txt file on %usb_letter%:\
    )
) else (
    echo USB drive is not available in %usb_letter%:\
)

:end
endlocal
exit /b 1
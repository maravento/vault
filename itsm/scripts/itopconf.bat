@echo off
:: by maravento.com

:: iTop - IT Service Management & CMDB - Config
:: Support: Win 10/11
:: Tested iTop v3.2.0-2-14758
:: Download and unzip iTop to folder \www\iTop
:: https://sourceforge.net/projects/itop/
:: Dependencies: Find and Replace (FNR) http://findandreplace.io/downloads/fnr.zip
:: Download and unzip fnr.exe to %WINDIR%\System32\fnr.exe

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set winfnr=%WINDIR%\System32\fnr.exe

:Check64Bit
IF NOT EXIST "%PROGRAMFILES(X86)%" (
    echo The system is not 64-bit
    exit /1
)

:iTopMenu
cls
echo.
echo iTop Config
echo.
echo WARNING:
echo Make sure iTop is installed and configured
echo iTop Route for Wamp and UZero: \www\itop
echo iTop Route for Xampp: \htdocs\itop
echo.
echo Select the web server where iTop is located:
echo.
echo 1. WampServer
echo 2. Xampp
echo 3. UniServerZ
echo 4. Exit
echo.
echo Write your number (1, 2, 3, 4) and
echo Press ENTER
echo.
set /p var=

if "%var%"=="1" set "iTopPath=%HOMEDRIVE%\wamp64\www\itop" & goto :iTopConfig
if "%var%"=="2" set "iTopPath=%HOMEDRIVE%\xampp\htdocs\itop" & goto :iTopConfig
if "%var%"=="3" set "iTopPath=%HOMEDRIVE%\UniServerZ\www\itop" & goto :iTopConfig
if "%var%"=="4" exit /0
echo Invalid option. Please select a valid number from 1 to 4
echo.
pause
goto :iTopMenu

REM check iTop path
if not exist "%iTopPath%" (
    goto :ErrorHandler
)
if not exist "%iTopPath%\web\conf\production" (
    goto :ErrorHandler
)
goto :iTopConfig

:iTopConfig
cls
echo.
echo Select An Option:
echo.
echo 1. Change MySQL Port for iTop (Default 3306)
echo 2. Restore MySQL Port for iTop to Default 3306
echo 3. Change Apache Port for iTop (Default 80)
echo 4. Restore Apache Port for iTop To Default 80
echo 5. Reboot
echo 6. Exit
echo.
echo Write your number (1, 2, 3, 4, 5, 6) and
echo Press ENTER
echo.
set /p var=
if "%var%"=="1" goto :ChangeMySQLiTop
if "%var%"=="2" goto :RestoreMySQLiTop
if "%var%"=="3" goto :ChangeApacheiTop
if "%var%"=="4" goto :RestoreApacheiTop
if "%var%"=="5" shutdown /r /t 0
if "%var%"=="6" exit /0
echo Invalid option. Please select a valid number from 1 to 6
echo.
pause
goto :iTopConfig

:ChangeMySQLiTop
echo Change MySQL Port for iTop (Default is 3306)
attrib -r "%iTopPath%\web\conf\production\config-itop.php"
if ERRORLEVEL 1 goto :ErrorHandler
call :Port
%winfnr% --cl --dir "%iTopPath%\web\conf\production" --fileMask config-itop.php --useRegEx --find "'db_host' => 'localhost'," --replace "'db_host' => 'localhost:%port%',"
if ERRORLEVEL 1 goto :ErrorHandler
attrib +r "%iTopPath%\web\conf\production\config-itop.php"
echo MySQL iTop Port changed to %port%
echo Restart MySQL to Apply Changes
goto :ReturnToMenu

:RestoreMySQLiTop
echo Reset to Default MySQL Port
attrib -r "%iTopPath%\web\conf\production\config-itop.php"
if ERRORLEVEL 1 goto :ErrorHandler
%winfnr% --cl --dir "%iTopPath%\web\conf\production" --fileMask config-itop.php --useRegEx --find "'db_host' => 'localhost:\d+'," --replace "'db_host' => 'localhost',"
if ERRORLEVEL 1 goto :ErrorHandler
attrib +r "%iTopPath%\web\conf\production\config-itop.php"
echo MySQL iTop Port Restored to Default 3306
echo Restart MySQL to Apply Changes
goto :ReturnToMenu

:ChangeApacheiTop
echo Change Apache Port for iTop (Default is 80)
attrib -r "%iTopPath%\web\conf\production\config-itop.php"
if ERRORLEVEL 1 goto :ErrorHandler
call :Port
%winfnr% --cl --dir "%iTopPath%\web\conf\production" --fileMask config-itop.php --useRegEx --find "'app_root_url' => 'http://localhost/itop/web/'," --replace "'app_root_url' => 'http://localhost:%port%/itop/web/',"
if ERRORLEVEL 1 goto :ErrorHandler
attrib +r "%iTopPath%\web\conf\production\config-itop.php"
echo Apache iTop Port changed to %port%
echo Restart Apache to Apply Changes
goto :ReturnToMenu

:RestoreApacheiTop
echo Reset to Default Apache Port
attrib -r "%iTopPath%\web\conf\production\config-itop.php"
if ERRORLEVEL 1 goto :ErrorHandler
%winfnr% --cl --dir "%iTopPath%\web\conf\production" --fileMask config-itop.php --useRegEx --find "'app_root_url' => 'http://localhost:\d+/itop/web/'," --replace "'app_root_url' => 'http://localhost/itop/web/',"
if ERRORLEVEL 1 goto :ErrorHandler
attrib +r "%iTopPath%\web\conf\production\config-itop.php"
echo Apache iTop Port Restored to Default 80
echo Restart Apache to Apply Changes
goto :ReturnToMenu

:ReturnToMenu
echo.
echo Press a Key to Menu Return
pause > NUL
goto :iTopConfig

:Port
set /p port=Enter the new port: 
for /f "delims=0123456789" %%a in ("%port%") do (
    echo Is not a port number
    exit /B 1
)
if %port% LSS 1 (
    echo Port must be greater than or equal to 1
    exit /B 1
) else if %port% GTR 65535 (
    echo Port must be less than or equal to 65535
    exit /B 1
)
echo The port %port% is valid.
exit /B 0

:ErrorHandler
echo.
echo An error has occurred. Check the Stack and iTop Paths
exit /1

@echo off
:: maravento.com

:: Uniform Server Config
:: Tested  v15_0_2_ZeroXV
:: Support: Win 10/11
:: Path Scripts: %HOMEDRIVE%\UniServerZ
:: Dependencies: Find and Replace (FNR) http://findandreplace.io/downloads/fnr.zip
:: Download fnr.exe to %WINDIR%\System32\fnr.exe

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set uzero=%HOMEDRIVE%\UniServerZ
set winfnr=%WINDIR%\System32\fnr.exe

:Menu
cls
echo.
echo UZERO CONFIG
echo You must reboot to take effect
echo.
echo 1. Change MySQL Port (Default 3306)
echo 2. Restore MySQL Port to Default 3306
echo 3. Change Apache Port (Default 80)
echo 4. Restore Apache Port To Default 80
echo 5. Set UZero Permanent (Start with System)
echo 6. Restore UZero Portable
echo 7. Reboot
echo 8. Exit
echo.
echo Write your number (1, 2, 3, 4, 5, 6, 7, 8) and
echo Press ENTER
echo.
set /p var=
if "%var%"=="1" goto :ChangeMySQLUZero
if "%var%"=="2" goto :RestoreMySQLUZero
if "%var%"=="3" goto :ChangeApacheUZero
if "%var%"=="4" goto :RestoreApacheUZero
if "%var%"=="5" goto :Permanent
if "%var%"=="6" goto :Portable
if "%var%"=="7" shutdown /r /t 0
if "%var%"=="8" exit /0
echo Invalid option. Please select a valid number from 1 to 8
pause
goto :Menu

:ChangeMySQLUZero
call :StopServices
echo Change MySQL port (Default is 3306)
call :Port
%winfnr% --cl --dir "%uzero%\home\us_config" --fileMask us_user.ini --useRegEx --find "MYSQL_TCP_PORT=3306" --replace "MYSQL_TCP_PORT=%port%"
if ERRORLEVEL 1 goto :ErrorHandler
echo MySQL port changed to %port%
call :StartServices
goto :ReturnToMenu

:RestoreMySQLUZero
call :StopServices
echo Restoring MySQL port to default (3306)...
%winfnr% --cl --dir "%uzero%\home\us_config" --fileMask us_user.ini --useRegEx --find "MYSQL_TCP_PORT=\d+" --replace "MYSQL_TCP_PORT=3306"
if ERRORLEVEL 1 goto :ErrorHandler
echo MySQL port restored to default 3306
call :StartServices
goto :ReturnToMenu

:ChangeApacheUZero
call :StopServices
echo Change Apache port (Default is 80)
call :Port
%winfnr% --cl --dir "%uzero%\home\us_config" --fileMask us_user.ini --useRegEx --find "AP_PORT=80" --replace "AP_PORT=%port%"
%winfnr% --cl --dir "%uzero%\home\us_pac" --fileMask proxy.pac --useRegEx --find "if \(shExpMatch\(host, ""\*localhost""\)\) return ""PROXY 127.0.0.1:80"";" --replace "if (shExpMatch(host, \"*localhost\")) return \"PROXY 127.0.0.1:%port%\";"
if ERRORLEVEL 1 goto :ErrorHandler
echo Apache port changed to %port%
call :StartServices
goto :ReturnToMenu

:RestoreApacheUZero
call :StopServices
%winfnr% --cl --dir "%uzero%\home\us_config" --fileMask us_user.ini --useRegEx --find "AP_PORT=\d+" --replace "AP_PORT=80"
%winfnr% --cl --dir "%uzero%\home\us_pac" --fileMask proxy.pac --useRegEx --find "if \(shExpMatch\(host, \"\*localhost\"\)\) return \"PROXY 127\.0\.0\.1:\d+\";" --replace "if (shExpMatch(host, \"*localhost\")) return \"PROXY 127.0.0.1:80\";"
if ERRORLEVEL 1 goto :ErrorHandler
echo Apache port restored to default 80
call :StartServices
goto :ReturnToMenu

:Permanent
REG ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "UniServer" /t REG_SZ /F /D "\"%uzero%\UniController.exe\" start_both" >NUL 2>NUL
echo Permanent Configuration Set
goto :ReturnToMenu

:Portable
REG DELETE "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "UniServer" /F >NUL 2>NUL
echo Restored Portable Configuration
goto :ReturnToMenu

:ReturnToMenu
echo.
echo Press a Key to Menu Return
pause > NUL
goto :Menu

:StopServices
taskkill /F /IM UniController.exe > NUL 2>NUL
start /w %uzero%\UniController.exe stop_both
exit /B 0

:StartServices
start /w %uzero%\UniController.exe start_both
exit /B 0

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
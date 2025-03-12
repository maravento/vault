@echo off
REM by maravento.com

REM FixPrint
REM for win 10/11

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
   exit /b 1
)
if NOT EXIST "%PROGRAMFILES(X86)%" (
   echo OS Incompatible
   exit /b 1
)

cls
echo.
echo FixPrint has started. Please wait...
echo.
echo Stopping the print spooler service...
net stop spooler >nul 2>&1

echo.
echo Deleting print jobs...
del /Q /F /S "%systemroot%\System32\Spool\Printers\*.*"

echo.
echo Setting spooler recovery options...
sc failure spooler reset= 240 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1

echo.
echo Resetting spooler dependencies...
sc config spooler depend= RPCSS >nul 2>&1

echo.
echo Restoring service configuration...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Spooler" /v Start /t REG_DWORD /d 2 /f >nul 2>&1

echo.
echo Deleting printer settings...
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" /v Device /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" /v LegacyDefaultPrinterMode /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" /v UserSelectedDefault /f >nul 2>&1

echo.
echo Starting the print spooler service...
net start spooler >nul 2>&1

echo.
echo Print queue cleanup complete
echo.
pause

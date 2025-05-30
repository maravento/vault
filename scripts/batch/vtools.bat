@echo off
:: maravento.com

:: VTools QEMU/KVM
:: Spice, VirtIO, and WinFsp Setup as a Service for Windows VMs
:: For Windows 10/11
:: https://www.maravento.com/2022/11/cockpit.html

:: This script downloads and silently installs the latest guest tools
:: VirtioFsSvc Windows service automatically.

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
set "DIR=%HOMEDRIVE%\vtools"
if not exist "%DIR%" (
    mkdir "%DIR%"
)
cd /d "%DIR%" || (
    echo Failed to enter the directory: %DIR%
    echo.
    pause
    exit /b 1
)

cls
echo.
echo Spice + VirtIO + and WinFsp Setup Starting. Wait...
echo.

:: SPICE
echo Download latest Spice version...
call :download "https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe" "spice-guest-tools-latest.exe"

echo Installing Spice and Red Hat drivers...
start /wait "" "spice-guest-tools-latest.exe" /S

:: Check vdservice status using PowerShell
for /f "usebackq delims=" %%s in (`powershell -NoProfile -Command "(Get-Service -Name 'vdservice').Status"`) do set "svcstate=%%s"

echo vdservice status: %svcstate%

if /I "%svcstate%"=="Running" (
    echo vdservice is already running.
) else (
    echo Starting vdservice service...

    :: Start the service with error handling
    powershell -NoProfile -Command "Start-Service -Name 'vdservice'" || (
        echo ERROR: Failed to start vdservice service.
        exit /b 1
    )
)

:: Check if vdagent.exe is running
tasklist /FI "IMAGENAME eq vdagent.exe" | find /I "vdagent.exe" >nul
if %errorlevel%==0 (
    echo vdagent.exe is running.
) else (
    echo ERROR: vdagent.exe is not running.
    exit /b 1
)

echo OK
echo.

:: WinFSP
echo Detecting latest WinFSP version...
:: Detect version from GitHub API
for /F "usebackq delims=" %%v in (`powershell -NoProfile -Command ^
    "try {" ^
    "    $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/winfsp/winfsp/releases/latest';" ^
    "    Write-Output $response.tag_name" ^
    "} catch {" ^
    "    Write-Error 'Failed to get version'" ^
    "}"`) do set "version=%%v"

if not defined version (
    echo Error: Could not detect the version
    exit /b 1
)
echo Detected version: %version%

echo Searching for MSI file...
for /F "usebackq delims=" %%f in (`powershell -NoProfile -Command ^
    "try {" ^
    "    $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/winfsp/winfsp/releases/latest';" ^
    "    $msiAsset = $response.assets | Where-Object { $_.name -like '*.msi' } | Select-Object -First 1;" ^
    "    if ($msiAsset) {" ^
    "        Write-Output $msiAsset.name" ^
    "    } else {" ^
    "        Write-Error 'MSI file not found'" ^
    "    }" ^
    "} catch {" ^
    "    Write-Error 'Error searching MSI file'" ^
    "}"`) do set "msi_name=%%f"

if not defined msi_name (
    echo Error: MSI file name not found
    exit /b 1
)
echo MSI file found: %msi_name%

echo Downloading %msi_name%
call :download "https://github.com/winfsp/winfsp/releases/download/%version%/%msi_name%" "%msi_name%"

echo Installing WinFsp...
start /wait msiexec /i "%msi_name%" /quiet /norestart
echo OK
echo.

:: VirtIO
echo Detecting latest VirtIO version...
call :download "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/" "virtio.html"

set "PSFILE=%DIR%\get_latest_virtio.ps1"

> "%PSFILE%" echo $content = Get-Content -Raw -Path "%DIR%\virtio.html"
>>"%PSFILE%" echo $matches = [regex]::Matches($content, 'href="(virtio-win-[\d\.]+-\d+)/"')
>>"%PSFILE%" echo $versions = $matches ^| ForEach-Object { $_.Groups[1].Value }
>>"%PSFILE%" echo $latest = $versions ^| Sort-Object -Descending ^| Select-Object -First 1
>>"%PSFILE%" echo Write-Output $latest

echo Extracting latest version...
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"`) do (
    set "latest=%%a"
)

del "%PSFILE%"
del virtio.html

if not defined latest (
    echo ERROR: Could not extract the latest version.
    exit /b 1
)

echo Latest version found: !latest!

set "virtio_url=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/!latest!/virtio-win-guest-tools.exe"
call :download "!virtio_url!" "virtio-win-guest-tools.exe"

echo Installing VirtIO tools...
start /wait "" "virtio-win-guest-tools.exe" /quiet /norestart
echo OK
echo.

echo Configuring VirtioFsSvc service...
set "VIRTIOFS_EXE=C:\Program Files\Virtio-Win\VioFS\virtiofs.exe"
:: check .exe
if not exist "%VIRTIOFS_EXE%" (
    echo ERROR: virtiofs.exe not found at "%VIRTIOFS_EXE%"
    echo Make sure VirtIO Guest Tools were installed correctly.
    exit /b 1
)

:: check service
sc query VirtioFsSvc >nul 2>&1
if errorlevel 1 (
    echo Service not found, creating service...
    sc create VirtioFsSvc binPath= "\"%VIRTIOFS_EXE%\"" start= auto
) else (
    echo Service already exists, updating binPath and setting to auto...
    sc config VirtioFsSvc binPath= "\"%VIRTIOFS_EXE%\"" start= auto
)

timeout /t 3 /nobreak >nul
echo.

:: check status
for /f "usebackq delims=" %%s in (`powershell -NoProfile -Command "(Get-Service -Name 'VirtioFsSvc').Status"`) do set "svcstate=%%s"

echo Service status: %svcstate%

if /I "%svcstate%"=="Running" (
    echo Service is already running.
) else (
    echo Starting VirtioFsSvc service...

    :: error handling
    powershell -NoProfile -Command "Start-Service -Name 'VirtioFsSvc'" || (
        echo ERROR: Failed to start VirtioFsSvc service.
        exit /b 1
    )
)

echo.
echo Done
echo Reboot your system to apply changes
echo.
pause
endlocal
exit /b 0

:download
:: %1 = URL
:: %2 = output filename
curl -# -L -o "%~2" "%~1"
if errorlevel 1 (
    echo ERROR: Failed to download %~2 from %~1
    exit /b 1
)
if not exist "%~2" (
    echo ERROR: File %~2 not found after download attempt.
    exit /b 1
)
goto :eof


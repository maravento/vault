@echo off
:: maravento.com

:: Sysprep preparation
:: for win 10/11

:: LIMITATION: Sysprep only supports local user accounts on an unencrypted
:: system drive, with no active network connection. It does not support
:: Microsoft accounts (email-linked accounts) or an active network connection,
:: since Store apps can be reinstalled/updated automatically in either case.
:: It also fails if BitLocker is enabled on the OS drive.

for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-LocalUser -Name $env:USERNAME).PrincipalSource"`) do set "acctsource=%%a"
if /i "%acctsource%"=="MicrosoftAccount" (
    echo ERROR: This account is a Microsoft account. Sysprep requires a local account -- abort.
    pause
    exit /b 1
)

manage-bde -status %systemdrive% | find "Protection On" >nul 2>&1
if not errorlevel 1 (
    echo ERROR: BitLocker is enabled on %systemdrive%. Disable it before running Sysprep -- abort.
    pause
    exit /b 1
)

for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-NetConnectionProfile | Where-Object {$_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet'}).Count"`) do set "netcount=%%a"
if not "%netcount%"=="0" (
    echo ERROR: An active network connection was detected. Disconnect from the network before running Sysprep -- abort.
    pause
    exit /b 1
)

@echo . 2>"sysprep.ps1"
(
  echo;Import-Module appx
  echo;Import-Module dism
  echo;Get-AppxPackage -AllUsers ^| Remove-AppxPackage
  echo;Get-AppxProvisionedPackage -Online ^| Remove-AppxProvisionedPackage -Online
) >>"sysprep.ps1"
start /wait PowerShell.exe -NoProfile -Command "& {Start-Process -Wait PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dpn0.ps1""' -Verb RunAs}"
del sysprep.ps1
start /w %windir%\system32\sysprep\sysprep.exe
exit

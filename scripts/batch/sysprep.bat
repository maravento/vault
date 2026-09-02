@echo off
:: maravento.com

:: Sysprep preparation
:: for win 10/11

:: LIMITATION: Sysprep only supports local user accounts on an unencrypted
:: system drive, with no active network connection. It does not support
:: Microsoft accounts (email-linked accounts) or an active network connection,
:: since Store apps can be reinstalled/updated automatically in either case.
:: It also fails if BitLocker is enabled on the OS drive.

:: APPX REMOVAL: Sysprep also fails validation ("Sysprep no pudo validar la
:: instalacion de Windows", see %WINDIR%\System32\Sysprep\Panther\setupact.log)
:: when Appx packages installed per-user for OTHER accounts on this machine
:: are not deprovisioned at the image level. Known offenders include the
:: Microsoft Store and preinstalled antivirus apps (e.g. Windows Security /
:: third-party AV Store apps) -- there may be others depending on what came
:: preinstalled. This is why this script removes all Appx packages for all
:: users and deprovisions them, instead of limiting the removal to the
:: account being generalized. After deployment, the end user will need to
:: reinstall any Store apps they need (Store, antivirus, etc.).
::
:: Manual restore commands (run in an elevated PowerShell):
::   Microsoft Store:
::     wsreset.exe -i
::   All remaining/registered Appx packages (re-registers what is still
::   present on disk; does not re-download anything that was fully removed):
::     Get-AppxPackage -AllUsers | Foreach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml"}

set "tmpdir=%windir%\Temp\sysprep_tmp"
if /i not "%~dp0"=="%tmpdir%\" (
    mkdir "%tmpdir%" 2>nul
    copy /y "%~f0" "%tmpdir%\sysprep.bat" >nul
    start /min "" "%tmpdir%\sysprep.bat"
    exit
)

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit
)

title Sysprep - Unattended Generalization
echo ============================================================
echo   Sysprep - Unattended Generalization Tool
echo   maravento.com
echo ============================================================
echo.

set /p "pwd=Enter password for account %username% (leave blank if none): "

for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-Culture).Name"`) do set "def_locale=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-WinSystemLocale).Name"`) do set "def_syslocale=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-WinUserLanguageList)[0].InputMethodTips[0]"`) do set "def_inputlocale=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$id='%def_inputlocale%'.Split(':')[1]; (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\' + $id)).'Layout Text'"`) do set "def_inputlocale_name=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-TimeZone).Id"`) do set "def_timezone=%%a"

set "uilang=%def_locale%"
echo Detected UI language: %def_locale%
set /p "chg=Modify it? y/n (Default: Enter = N): "
if /i "%chg%"=="y" set /p "uilang=Enter UI language, e.g. es-MX, en-US: "

set "syslocale=%def_syslocale%"
echo Detected system locale: %def_syslocale%
set /p "chg=Modify it? y/n (Default: Enter = N): "
if /i "%chg%"=="y" set /p "syslocale=Enter system locale, e.g. es-MX, en-US: "

set "userlocale=%def_locale%"
echo Detected user locale: %def_locale%
set /p "chg=Modify it? y/n (Default: Enter = N): "
if /i "%chg%"=="y" set /p "userlocale=Enter user locale, e.g. es-MX, en-US: "

set "inputlocale=%def_inputlocale%"
echo Detected keyboard layout: %def_inputlocale_name% (%def_inputlocale%)
set /p "chg=Modify it? y/n (Default: Enter = N): "
if /i "%chg%"=="y" set /p "inputlocale=Enter keyboard layout, e.g. 0409:00000409 (US), 080a:0000080a (Mexico): "

set "timezone=%def_timezone%"
echo Detected time zone: %def_timezone%
set /p "chg=Modify it? y/n (Default: Enter = N): "
if /i "%chg%"=="y" set /p "timezone=Enter time zone, e.g. Central Standard Time (Mexico), SA Pacific Standard Time: "

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

@echo . 2>"%tmpdir%\sysprep.ps1"
(
  echo;Import-Module appx
  echo;Import-Module dism
  echo;Get-AppxPackage -AllUsers ^| Remove-AppxPackage
  echo;Get-AppxProvisionedPackage -Online ^| Remove-AppxProvisionedPackage -Online
) >>"%tmpdir%\sysprep.ps1"
start /wait PowerShell.exe -NoProfile -Command "& {Start-Process -Wait PowerShell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%tmpdir%\sysprep.ps1""' -Verb RunAs}"

@echo . 2>"%tmpdir%\sysprep_unattend.xml"
(
  echo;^<?xml version="1.0" encoding="utf-8"?^>
  echo;^<unattend xmlns="urn:schemas-microsoft-com:unattend"^>
  echo;  ^<settings pass="oobeSystem"^>
  echo;    ^<component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"^>
  echo;      ^<UILanguage^>%uilang%^</UILanguage^>
  echo;      ^<SystemLocale^>%syslocale%^</SystemLocale^>
  echo;      ^<UserLocale^>%userlocale%^</UserLocale^>
  echo;      ^<InputLocale^>%inputlocale%^</InputLocale^>
  echo;    ^</component^>
  echo;    ^<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"^>
  echo;      ^<TimeZone^>%timezone%^</TimeZone^>
  echo;      ^<OOBE^>
  echo;        ^<HideEULAPage^>true^</HideEULAPage^>
  echo;        ^<HideOEMRegistrationScreen^>true^</HideOEMRegistrationScreen^>
  echo;        ^<HideOnlineAccountScreens^>true^</HideOnlineAccountScreens^>
  echo;        ^<HideWirelessSetupInOOBE^>true^</HideWirelessSetupInOOBE^>
  echo;        ^<NetworkLocation^>Home^</NetworkLocation^>
  echo;        ^<ProtectYourPC^>3^</ProtectYourPC^>
  echo;      ^</OOBE^>
  echo;      ^<AutoLogon^>
  echo;        ^<Password^>
  echo;          ^<Value^>%pwd%^</Value^>
  echo;          ^<PlainText^>true^</PlainText^>
  echo;        ^</Password^>
  echo;        ^<Enabled^>true^</Enabled^>
  echo;        ^<LogonCount^>1^</LogonCount^>
  echo;        ^<Username^>%username%^</Username^>
  echo;      ^</AutoLogon^>
  echo;    ^</component^>
  echo;  ^</settings^>
  echo;^</unattend^>
) >>"%tmpdir%\sysprep_unattend.xml"

schtasks /create /tn "SysprepCleanup" /sc onlogon /ru "%username%" /it /rl highest /f /tr "cmd /c rmdir /s /q \"%tmpdir%\" & schtasks /delete /tn \"SysprepCleanup\" /f"

start /w %windir%\system32\sysprep\sysprep.exe /generalize /oobe /unattend:"%tmpdir%\sysprep_unattend.xml" /shutdown
exit

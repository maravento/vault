@echo off
:: maravento.com

:: Script to Disable or Auto Non-Essential Services
:: for win 10/11

REM Checking privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedexpansion

REM services
echo.
echo Disable or Auto Non-Essential Services
echo.
echo Choose an option:
echo 1. Disable: Windows Search, WAP, SysMain, Telemetry
echo 2. Auto: Windows Search, WAP, SysMain, Telemetry
echo 3. Exit
echo.
set /p choice="Enter the number (1, 2 or 3): "

REM Validate user input and perform the selected action
if "%choice%"=="1" (
    goto disable
) else if "%choice%"=="2" (
    goto restore
) else if "%choice%"=="3" (
    goto end
) else (
    goto invalid
)

:disable
REM List of services to stop and disable
set SERVICES="wsearch" "SysMain" "DiagTrack" "dmwappushservice"

for %%S in (%SERVICES%) do (
    sc config %%S start=disabled >nul 2>&1
    if !errorlevel!==0 (
        echo %%S has been disabled.
        sc stop %%S >nul 2>&1
    ) else (
        echo Unable to disable %%S.
    )
)
echo Note: some services may remain running until next reboot.

endlocal
goto end

:restore
REM List of services to start and enable
set SERVICES="wsearch" "SysMain" "DiagTrack" "dmwappushservice"

for %%S in (%SERVICES%) do (
    sc config %%S start=auto >nul 2>&1
    echo %%S has been enabled.
    sc start %%S >nul 2>&1
    call :wait_running %%S
)
endlocal
goto end

:wait_running
set /a _retries=0
:wait_running_loop
sc query %1 | find /i "RUNNING" >nul 2>&1
if not errorlevel 1 (
    echo %~1 has been started.
    exit /b 0
)
set /a _retries+=1
if %_retries% geq 15 (
    echo Warning: %~1 did not start after waiting. Continuing...
    exit /b 1
)
ping 127.0.0.1 -n 2 >nul
goto wait_running_loop

:invalid
echo Invalid choice. Exiting...
goto end

:end
echo Done
exit /b

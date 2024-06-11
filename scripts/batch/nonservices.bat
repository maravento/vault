@echo off
:: by maravento.com

:: Script to Disable or Auto Non-Essential Services
:: for win 10/11

REM Checking Privileges
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
    REM Stop service and redirect errors to null
    sc stop %%S >nul 2>&1

    :loop_stop
    REM Wait for the service to stop
    sc query %%S | find "STATE" | find /i "STOPPED" > nul
    if %errorlevel%==0 (
        echo %%S has been stopped.
        :disable_service
        REM Disable the service
        sc config %%S start=disabled >nul 2>&1
        if %errorlevel%==0 (
            echo %%S has been disabled.
        ) else (
            echo Unable to disable %%S.
        )
    ) else (
        ping 127.0.0.1 -n 2 > nul
        goto loop_stop
    )
)

endlocal
goto end

:restore
REM List of services to start and enable
set SERVICES="wsearch" "SysMain" "DiagTrack" "dmwappushservice"

for %%S in (%SERVICES%) do (
    REM Enable the service
    sc config %%S start=auto >nul 2>&1
    echo %%S has been enable

    REM Start the service
    sc start %%S >nul 2>&1

    :loop
    REM Wait for the service to start
    sc query %%S | find /i "RUNNING" > nul
    if %errorlevel%==0 (
        echo %%S has been started.
    ) else (
        ping 127.0.0.1 -n 2 > nul
        goto loop
    )
)
:endlocal
goto end

:invalid
echo Invalid choice. Exiting...
goto end

:end
echo Done
exit /b

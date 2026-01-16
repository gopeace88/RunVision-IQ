@echo off
title RunVision-IQ Simulator

REM === Settings ===
set SDK_PATH=C:\Users\jinhee\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.4.0-2025-12-03-5122605dc\bin
set JAVA_PATH=C:\Program Files\Java\jdk-11.0.2\bin\java.exe
set PRG_FILE=D:\00.Projects\00.RunVision\runvision-iq\bin\RunVisionIQ.prg
set DEVICE=fr265

REM === Override device if parameter provided ===
if not "%~1"=="" set DEVICE=%~1

echo.
echo === RunVision-IQ Simulator ===
echo Device: %DEVICE%
echo.

REM === Check Java ===
if not exist "%JAVA_PATH%" (
    echo [ERROR] Java not found: %JAVA_PATH%
    pause
    exit /b 1
)

REM === Check PRG file ===
if not exist "%PRG_FILE%" (
    echo [ERROR] PRG file not found: %PRG_FILE%
    pause
    exit /b 1
)

REM === 1. Start simulator ===
echo [1/3] Starting simulator...
start "" "%SDK_PATH%\simulator.exe"

REM === 2. Wait for simulator ===
echo [2/3] Waiting for simulator (5 seconds)...
timeout /t 5 /nobreak > nul

REM === 3. Load app ===
echo [3/3] Loading app to %DEVICE%...
"%JAVA_PATH%" -classpath "%SDK_PATH%\monkeybrains.jar" com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f "%PRG_FILE%" -d %DEVICE% -s "%SDK_PATH%\shell.exe"

echo.
echo === Done! Device: %DEVICE% ===
pause

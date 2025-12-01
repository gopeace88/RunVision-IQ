@echo off
title RunVision-IQ Simulator

set SDK_BIN=%APPDATA%\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin
set PRG_FILE=D:\00.Projects\00.RunVision-IQ\bin\RunVisionIQ.prg
set DEVICE=fr265

echo === RunVision-IQ Simulator ===
echo.

echo [1] Starting simulator...
start "" "%SDK_BIN%\simulator.exe"

echo [2] Waiting for simulator (5 seconds)...
timeout /t 5 /nobreak > nul

echo [3] Loading app...
call "%SDK_BIN%\monkeydo.bat" "%PRG_FILE%" %DEVICE%

echo.
echo === Done! Check simulator window ===
pause

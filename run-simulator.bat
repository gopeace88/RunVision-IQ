@echo off
title RunVision-IQ Simulator
chcp 65001 > nul

REM ============================================================
REM RunVision-IQ Simulator Launcher
REM
REM 주의사항:
REM   1. Java 11이 설치되어 있어야 함
REM   2. Windows 방화벽에서 Java가 허용되어야 함
REM      (제어판 > 방화벽 > 앱 허용 > Java 체크)
REM   3. SDK 버전이 변경되면 SDK_PATH 수정 필요
REM ============================================================

REM === 설정 ===
set SDK_PATH=C:\Users\jinhee\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.4.0-2025-12-03-5122605dc\bin
set JAVA_PATH=C:\Program Files\Java\jdk-11.0.2\bin\java.exe
set PRG_FILE=D:\00.Projects\00.RunVision\runvision-iq\bin\RunVisionIQ.prg
set DEVICE=fr265

echo.
echo === RunVision-IQ Simulator ===
echo.

REM === Java 확인 ===
if not exist "%JAVA_PATH%" (
    echo [ERROR] Java not found at: %JAVA_PATH%
    echo Please install Java 11 or update JAVA_PATH
    pause
    exit /b 1
)

REM === PRG 파일 확인 ===
if not exist "%PRG_FILE%" (
    echo [ERROR] PRG file not found: %PRG_FILE%
    echo Please build the project first
    pause
    exit /b 1
)

REM === 1. 시뮬레이터 실행 ===
echo [1/3] Starting simulator...
start "" "%SDK_PATH%\simulator.exe"

REM === 2. 시뮬레이터 초기화 대기 ===
echo [2/3] Waiting for simulator (5 seconds)...
timeout /t 5 /nobreak > nul

REM === 3. 앱 로드 (Java 직접 호출 - monkeydo.bat 우회) ===
echo [3/3] Loading app to %DEVICE%...
"%JAVA_PATH%" -classpath "%SDK_PATH%\monkeybrains.jar" com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f "%PRG_FILE%" -d %DEVICE% -s "%SDK_PATH%\shell.exe"

echo.
echo === Done! Device: %DEVICE% ===
pause

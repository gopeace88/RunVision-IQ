@echo off
setlocal enabledelayedexpansion

REM Custom monkeydo that connects to port 42877 (for Hyper-V systems)
REM Usage: monkeydo-custom.bat program.prg device_id

IF "%~2"=="" GOTO usage

SET prg_path=%1
SET device_id=%2
SET SDK_HOME=C:\Users\jinhee\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin

REM Execute MonkeyDoDeux with custom shell wrapper for port 42877
cd /d "%SDK_HOME%"
java -classpath monkeybrains.jar com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f %prg_path% -d %device_id% -s "D:\00.Projects\00.RunVision\runvision-iq\shell-42877.bat"
GOTO :eof

:usage
@echo Custom MonkeyDo for Hyper-V systems (uses port 42877)
@echo Usage: %0 program.prg device_id
exit /B 1

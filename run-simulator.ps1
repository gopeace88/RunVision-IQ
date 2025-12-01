# RunVision-IQ Simulator 실행 스크립트
# PowerShell에서 실행: .\run-simulator.ps1

$SDK_BIN = "$env:APPDATA\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin"
$PRG_FILE = "D:\00.Projects\00.RunVision-IQ\bin\RunVisionIQ.prg"
$DEVICE = "fr265"

Write-Host "=== RunVision-IQ Simulator ===" -ForegroundColor Green

# 1. 시뮬레이터 실행
Write-Host "`n[1] Starting simulator..." -ForegroundColor Yellow
Start-Process "$SDK_BIN\simulator.exe"

# 2. 시뮬레이터가 시작될 때까지 대기
Write-Host "[2] Waiting for simulator to start (5 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# 3. 앱 로드
Write-Host "[3] Loading app: $PRG_FILE" -ForegroundColor Yellow
Write-Host "    Device: $DEVICE" -ForegroundColor Yellow

& "$SDK_BIN\monkeydo.bat" $PRG_FILE $DEVICE

Write-Host "`n=== Done! ===" -ForegroundColor Green
Write-Host "Check the simulator window for the app." -ForegroundColor Cyan

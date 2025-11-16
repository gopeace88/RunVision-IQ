# Garmin 기기 연결 확인 스크립트

Write-Host "`n🔍 Garmin 기기 연결 확인" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""

# 1. USB 연결 확인
Write-Host "📱 USB 연결 확인:" -ForegroundColor Yellow

# 방법 1: PSDrive로 찾기 (일부 기기)
$garminDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like "*GARMIN*" }

# 방법 2: MTP 장치 확인
$garminDevices = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Garmin*" -and $_.Status -eq "OK" }

# 방법 3: WMI로 찾기
$garminVolumes = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.VolumeName -like "*GARMIN*" }

$found = $false

if ($garminDrives) {
    foreach ($drive in $garminDrives) {
        Write-Host "   ✅ 드라이브 발견: $($drive.Root)" -ForegroundColor Green
        $found = $true
        
        $appsPath = $drive.Root + "Garmin\Apps\"
        if (Test-Path $appsPath) {
            Write-Host "      Apps 폴더: $appsPath" -ForegroundColor White
            
            $installedApps = Get-ChildItem -Path $appsPath -Filter "*.prg" -ErrorAction SilentlyContinue
            if ($installedApps) {
                Write-Host "      설치된 앱:" -ForegroundColor White
                foreach ($app in $installedApps) {
                    Write-Host "         - $($app.Name)" -ForegroundColor Gray
                }
            }
        }
    }
}

if ($garminDevices) {
    Write-Host "   ✅ Garmin USB 장치 발견:" -ForegroundColor Green
    foreach ($device in $garminDevices) {
        Write-Host "      - $($device.FriendlyName)" -ForegroundColor White
    }
    $found = $true
}

if ($garminVolumes) {
    foreach ($volume in $garminVolumes) {
        Write-Host "   ✅ 볼륨 발견: $($volume.DeviceID) ($($volume.VolumeName))" -ForegroundColor Green
        $found = $true
    }
}

# 방법 4: MTP 경로 확인 (Forerunner 165/265 등)
$mtpBasePaths = @(
    "$env:USERPROFILE\Desktop\내 PC\Forerunner 165\Internal Storage\GARMIN",
    "$env:USERPROFILE\Desktop\내 PC\Forerunner 265\Internal Storage\GARMIN",
    "$env:USERPROFILE\Desktop\내 PC\Fenix 7\Internal Storage\GARMIN"
)

foreach ($mtpPath in $mtpBasePaths) {
    if (Test-Path $mtpPath) {
        Write-Host "   ✅ MTP 경로 발견: $mtpPath" -ForegroundColor Green
        $appsPath = $mtpPath + "\Apps"
        if (Test-Path $appsPath) {
            Write-Host "      Apps 폴더: $appsPath" -ForegroundColor White
            
            $installedApps = Get-ChildItem -Path $appsPath -Filter "*.prg" -ErrorAction SilentlyContinue
            if ($installedApps) {
                Write-Host "      설치된 앱:" -ForegroundColor White
                foreach ($app in $installedApps) {
                    Write-Host "         - $($app.Name)" -ForegroundColor Gray
                }
            }
        }
        $found = $true
    }
}

if (-not $found) {
    Write-Host "   ⚠️  PowerShell로 자동 감지되지 않았습니다." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   💡 Garmin Express로 연결이 잘 되고 있다면:" -ForegroundColor Cyan
    Write-Host "      1. Windows 탐색기에서 '내 PC\Forerunner 165\Internal Storage\GARMIN' 확인" -ForegroundColor White
    Write-Host "      2. 또는 다른 드라이브 문자 확인 (예: G:\GARMIN)" -ForegroundColor White
    Write-Host "      3. 또는 monkeydo를 사용하여 Wi-Fi로 설치" -ForegroundColor White
    Write-Host ""
    Write-Host "   📝 수동 설치 방법:" -ForegroundColor Cyan
    Write-Host "      Windows 탐색기에서 다음 경로로 이동:" -ForegroundColor White
    Write-Host "      내 PC\Forerunner 165\Internal Storage\GARMIN\Apps" -ForegroundColor Gray
    Write-Host "      → bin\RunVisionIQ.prg 파일을 복사" -ForegroundColor White
}

Write-Host ""

# 2. Wi-Fi 연결 확인 (Connect IQ Manager)
Write-Host "📡 Wi-Fi 연결 확인:" -ForegroundColor Yellow
$sdkPath = "C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0"
$connectIQ = "$sdkPath\bin\connectiq.exe"

if (Test-Path $connectIQ) {
    Write-Host "   Connect IQ Manager 경로: $connectIQ" -ForegroundColor White
    Write-Host "   💡 Connect IQ Manager를 실행하여 Wi-Fi 연결을 확인하세요." -ForegroundColor Cyan
} else {
    Write-Host "   ⚠️  Connect IQ Manager를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host ""

# 3. 블루투스 확인
Write-Host "🔵 블루투스 확인:" -ForegroundColor Yellow
$bluetooth = Get-PnpDevice -Class Bluetooth -Status OK -ErrorAction SilentlyContinue
if ($bluetooth) {
    Write-Host "   ✅ 블루투스 어댑터 활성화됨" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  블루투스 어댑터를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host ""

# 4. 권장 사항
Write-Host "💡 권장 사항:" -ForegroundColor Cyan
Write-Host "   1. USB 연결: 가장 안정적이고 빠름" -ForegroundColor White
Write-Host "   2. Wi-Fi 연결: Connect IQ Manager에서 기기 등록 필요" -ForegroundColor White
Write-Host "   3. 디버깅: VS Code에서 F5 또는 디버그 설정 선택" -ForegroundColor White
Write-Host ""


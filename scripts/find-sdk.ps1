# Connect IQ SDK 경로 찾기 스크립트

Write-Host "`n🔍 Connect IQ SDK 경로 찾기" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

$foundSdk = $false

# 방법 1: 일반적인 설치 경로 확인
Write-Host "방법 1: 일반적인 설치 경로 확인" -ForegroundColor Yellow
$commonPaths = @(
    "C:\Garmin\ConnectIQ\Sdks",
    "$env:USERPROFILE\.Garmin\ConnectIQ\Sdks",
    "$env:LOCALAPPDATA\Garmin\ConnectIQ\Sdks",
    "$env:APPDATA\Garmin\ConnectIQ\Sdks",
    "C:\Users\$env:USERNAME\.Garmin\ConnectIQ\Sdks",
    "C:\Users\$env:USERNAME\AppData\Local\Garmin\ConnectIQ\Sdks",
    "C:\Users\$env:USERNAME\AppData\Roaming\Garmin\ConnectIQ\Sdks",
    "D:\Garmin\ConnectIQ\Sdks"
)

foreach ($basePath in $commonPaths) {
    if (Test-Path $basePath) {
        Write-Host "   ✅ 경로 발견: $basePath" -ForegroundColor Green
        
        $sdkDirs = Get-ChildItem $basePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "connectiq-sdk-*" }
        if ($sdkDirs) {
            foreach ($sdkDir in $sdkDirs) {
                $binPath = Join-Path $sdkDir.FullName "bin\monkeyc.exe"
                if (Test-Path $binPath) {
                    Write-Host "      ✅ SDK 발견: $($sdkDir.FullName)" -ForegroundColor Green
                    Write-Host "         monkeyc.exe: $binPath" -ForegroundColor White
                    $foundSdk = $true
                }
            }
        }
    }
}

Write-Host ""

# 방법 2: SDK Manager 경로에서 확인
Write-Host "방법 2: SDK Manager 경로 확인" -ForegroundColor Yellow
$sdkManagerPath = "D:\OneDrive\000.바탕화면\connectiq-sdk-manager-windows"
if (Test-Path $sdkManagerPath) {
    Write-Host "   ✅ SDK Manager 경로 발견: $sdkManagerPath" -ForegroundColor Green
    
    # SDK Manager 실행 파일 찾기
    $managerExe = Get-ChildItem $sdkManagerPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "*manager*.exe" -or $_.Name -like "*connectiq*.exe" 
    } | Select-Object -First 1
    
    if ($managerExe) {
        Write-Host "      SDK Manager 실행 파일: $($managerExe.FullName)" -ForegroundColor White
        Write-Host "      💡 SDK Manager를 실행하여 SDK를 설치하세요." -ForegroundColor Cyan
    }
} else {
    Write-Host "   ⚠️  SDK Manager 경로를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host ""

# 방법 3: 전체 시스템 검색 (느릴 수 있음)
if (-not $foundSdk) {
    Write-Host "방법 3: monkeyc.exe 파일 검색 (시간이 걸릴 수 있습니다)..." -ForegroundColor Yellow
    Write-Host "   검색 중..." -ForegroundColor Gray
    
    $monkeycPaths = @(
        "C:\Garmin",
        "$env:USERPROFILE\.Garmin",
        "$env:LOCALAPPDATA\Garmin",
        "D:\Garmin"
    )
    
    foreach ($searchPath in $monkeycPaths) {
        if (Test-Path $searchPath) {
            $monkeyc = Get-ChildItem $searchPath -Recurse -File -Filter "monkeyc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($monkeyc) {
                $sdkPath = Split-Path (Split-Path $monkeyc.FullName -Parent) -Parent
                Write-Host "   ✅ SDK 발견: $sdkPath" -ForegroundColor Green
                Write-Host "      monkeyc.exe: $($monkeyc.FullName)" -ForegroundColor White
                $foundSdk = $true
                break
            }
        }
    }
}

Write-Host ""

if (-not $foundSdk) {
    Write-Host "❌ SDK를 찾을 수 없습니다." -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 해결 방법:" -ForegroundColor Cyan
    Write-Host "   1. SDK Manager 실행: $sdkManagerPath" -ForegroundColor White
    Write-Host "   2. SDK 다운로드 및 설치" -ForegroundColor White
    Write-Host "   3. 또는 https://developer.garmin.com/connect-iq/sdk/ 에서 직접 다운로드" -ForegroundColor White
    Write-Host ""
    Write-Host "   설치 후 workspace 파일을 업데이트하세요:" -ForegroundColor White
    Write-Host "   runvision-iq-windows.code-workspace" -ForegroundColor Gray
} else {
    Write-Host "✅ SDK를 찾았습니다!" -ForegroundColor Green
    Write-Host ""
    Write-Host "💡 workspace 파일에 경로를 업데이트하세요:" -ForegroundColor Cyan
    Write-Host "   runvision-iq-windows.code-workspace" -ForegroundColor White
}

Write-Host ""


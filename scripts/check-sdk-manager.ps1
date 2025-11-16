# SDK Manager 설정 및 설치 경로 확인

Write-Host "`n🔍 SDK Manager 설정 확인" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""

$sdkManagerPath = "D:\OneDrive\000.바탕화면\connectiq-sdk-manager-windows"

if (Test-Path $sdkManagerPath) {
    Write-Host "✅ SDK Manager 경로: $sdkManagerPath" -ForegroundColor Green
    
    # SDK Manager 실행 파일 찾기
    $managerExe = Get-ChildItem $sdkManagerPath -Recurse -File -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($managerExe) {
        Write-Host "   실행 파일: $($managerExe.FullName)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "📁 SDK Manager 폴더 내용:" -ForegroundColor Yellow
    Get-ChildItem $sdkManagerPath -ErrorAction SilentlyContinue | Select-Object Name, @{Name="Type";Expression={if($_.PSIsContainer){"폴더"}else{"파일"}}} | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "💡 SDK Manager에서 SDK 설치 경로 확인 방법:" -ForegroundColor Cyan
    Write-Host "   1. SDK Manager 실행" -ForegroundColor White
    Write-Host "   2. Settings 또는 Preferences 메뉴 확인" -ForegroundColor White
    Write-Host "   3. 'SDK Path' 또는 'Installation Path' 확인" -ForegroundColor White
    Write-Host ""
    Write-Host "   일반적인 설치 경로:" -ForegroundColor White
    Write-Host "   - $env:USERPROFILE\.Garmin\ConnectIQ\Sdks" -ForegroundColor Gray
    Write-Host "   - C:\Garmin\ConnectIQ\Sdks" -ForegroundColor Gray
    Write-Host "   - $env:LOCALAPPDATA\Garmin\ConnectIQ\Sdks" -ForegroundColor Gray
    Write-Host ""
    
    # SDK Manager 설정 파일 확인
    Write-Host "🔍 설정 파일 검색 중..." -ForegroundColor Yellow
    $configFiles = Get-ChildItem $sdkManagerPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "*.json" -or 
        $_.Name -like "*.config" -or 
        $_.Name -like "*.ini" -or 
        $_.Name -like "*.properties" -or
        $_.Name -like "*.xml"
    }
    
    if ($configFiles) {
        Write-Host "   설정 파일 발견:" -ForegroundColor Green
        foreach ($file in $configFiles) {
            Write-Host "      - $($file.Name)" -ForegroundColor White
            if ($file.Name -like "*.json") {
                try {
                    $content = Get-Content $file.FullName -Raw | ConvertFrom-Json
                    if ($content.sdkPath -or $content.'sdk-path' -or $content.installationPath) {
                        Write-Host "         SDK 경로: $($content.sdkPath ?? $content.'sdk-path' ?? $content.installationPath)" -ForegroundColor Cyan
                    }
                } catch {
                    # JSON 파싱 실패 시 무시
                }
            }
        }
    }
} else {
    Write-Host "❌ SDK Manager 경로를 찾을 수 없습니다." -ForegroundColor Red
}

Write-Host ""


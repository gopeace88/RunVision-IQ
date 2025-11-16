# Connect IQ 메뉴 찾기 가이드 스크립트

Write-Host "`n🔍 Garmin Connect IQ 개발자 설정 찾기 가이드" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "워치에서 Connect IQ 개발자 설정을 찾을 수 없다면 다음을 시도하세요:" -ForegroundColor Yellow
Write-Host ""

Write-Host "📱 1단계: Connect IQ Store 앱 설치 확인" -ForegroundColor Cyan
Write-Host "   - 워치에서 Apps 메뉴 열기" -ForegroundColor White
Write-Host "   - 'Connect IQ Store' 앱이 설치되어 있는지 확인" -ForegroundColor White
Write-Host "   - 없으면 설치하고 최소 한 번 실행" -ForegroundColor White
Write-Host ""

Write-Host "🔍 2단계: 다음 경로들을 순서대로 시도" -ForegroundColor Cyan
Write-Host ""

Write-Host "   경로 A (가장 일반적):" -ForegroundColor Yellow
Write-Host "   Settings → Apps → Connect IQ → Developer Settings → USB Debugging" -ForegroundColor White
Write-Host ""

Write-Host "   경로 B:" -ForegroundColor Yellow
Write-Host "   Settings → System → Connect IQ → Developer Settings → USB Debugging" -ForegroundColor White
Write-Host ""

Write-Host "   경로 C:" -ForegroundColor Yellow
Write-Host "   Apps → Connect IQ (또는 Connect IQ Store) → Settings → Developer Settings" -ForegroundColor White
Write-Host ""

Write-Host "   경로 D:" -ForegroundColor Yellow
Write-Host "   Settings → Connect IQ (직접 표시) → Developer Settings" -ForegroundColor White
Write-Host ""

Write-Host "💡 3단계: 여전히 찾을 수 없다면" -ForegroundColor Cyan
Write-Host "   1. 워치 펌웨어가 최신인지 확인" -ForegroundColor White
Write-Host "   2. Connect IQ Store에서 앱을 하나 설치해보기" -ForegroundColor White
Write-Host "   3. 워치 재시작 후 다시 시도" -ForegroundColor White
Write-Host "   4. Connect IQ Manager 사용 (대안)" -ForegroundColor White
Write-Host ""

Write-Host "📡 4단계: Connect IQ Manager 사용 (대안)" -ForegroundColor Cyan
$sdkPath = "C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0"
$connectIQ = "$sdkPath\bin\connectiq.exe"

if (Test-Path $connectIQ) {
    Write-Host "   Connect IQ Manager 경로: $connectIQ" -ForegroundColor White
    Write-Host "   Manager를 실행하면 기기 연결 시 자동으로 개발자 모드 안내" -ForegroundColor White
} else {
    Write-Host "   ⚠️  Connect IQ Manager를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host ""

Write-Host "📚 자세한 내용은 Docs/DEVICE-SETUP.md 파일을 참고하세요." -ForegroundColor Cyan
Write-Host ""


# MTP 장치 경로 찾기 스크립트

Write-Host "`n🔍 MTP 장치 경로 찾기" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host ""

# 방법 1: Shell.Application 사용
Write-Host "방법 1: Shell.Application으로 MTP 장치 찾기" -ForegroundColor Yellow
$foundAppsPath = $null

try {
    $shell = New-Object -ComObject Shell.Application
    $namespace = $shell.NameSpace("shell:::{20D04FE0-3AEA-1069-A2D8-08002B30309D}") # 내 PC
    
    if ($namespace) {
        Write-Host "   내 PC 네임스페이스 접근 성공" -ForegroundColor Green
        
        $items = $namespace.Items()
        foreach ($item in $items) {
            if ($item.Name -like "*Forerunner*" -or $item.Name -like "*Garmin*") {
                Write-Host "   ✅ 발견: $($item.Name)" -ForegroundColor Green
                Write-Host "      경로: $($item.Path)" -ForegroundColor White
                
                # Internal Storage 찾기
                try {
                    $deviceFolder = $item.GetFolder
                    $deviceItems = $deviceFolder.Items()
                    
                    $internalStorage = $deviceItems | Where-Object { $_.Name -eq "Internal Storage" }
                    if ($internalStorage) {
                        Write-Host "      ✅ Internal Storage 발견" -ForegroundColor Green
                        
                        $internalFolder = $internalStorage.GetFolder
                        $internalItems = $internalFolder.Items()
                        
                        $garminFolder = $internalItems | Where-Object { $_.Name -eq "GARMIN" }
                        if ($garminFolder) {
                            Write-Host "      ✅ GARMIN 폴더 발견" -ForegroundColor Green
                            
                            $garminFolderObj = $garminFolder.GetFolder
                            $garminItems = $garminFolderObj.Items()
                            
                            $appsFolder = $garminItems | Where-Object { $_.Name -eq "Apps" }
                            if ($appsFolder) {
                                $foundAppsPath = $appsFolder.Path
                                Write-Host "      ✅ Apps 폴더 발견!" -ForegroundColor Green
                                Write-Host "      📁 전체 경로: $foundAppsPath" -ForegroundColor Cyan
                                
                                # 설치된 앱 확인
                                try {
                                    $appsFolderObj = $appsFolder.GetFolder
                                    $appsItems = $appsFolderObj.Items()
                                    $prgFiles = $appsItems | Where-Object { $_.Name -like "*.prg" }
                                    if ($prgFiles) {
                                        Write-Host "      설치된 앱:" -ForegroundColor White
                                        foreach ($prg in $prgFiles) {
                                            Write-Host "         - $($prg.Name)" -ForegroundColor Gray
                                        }
                                    } else {
                                        Write-Host "      (설치된 앱 없음)" -ForegroundColor Gray
                                    }
                                } catch {
                                    Write-Host "      ⚠️  앱 목록 확인 실패: $_" -ForegroundColor Yellow
                                }
                            } else {
                                Write-Host "      ⚠️  Apps 폴더를 찾을 수 없습니다." -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "      ⚠️  GARMIN 폴더를 찾을 수 없습니다." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "      ⚠️  Internal Storage를 찾을 수 없습니다." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "      ⚠️  폴더 탐색 실패: $_" -ForegroundColor Yellow
                }
            }
        }
    }
} catch {
    Write-Host "   ⚠️  Shell.Application 접근 실패: $_" -ForegroundColor Yellow
}

if ($foundAppsPath) {
    Write-Host ""
    Write-Host "✅ 사용 가능한 경로:" -ForegroundColor Green
    Write-Host "   $foundAppsPath" -ForegroundColor Cyan
}

Write-Host ""

# 방법 2: 직접 경로 시도
Write-Host "방법 2: 알려진 MTP 경로 확인" -ForegroundColor Yellow
$testPaths = @(
    "$env:USERPROFILE\Desktop\내 PC\Forerunner 165\Internal Storage\GARMIN",
    "$env:USERPROFILE\Desktop\내 PC\Forerunner 265\Internal Storage\GARMIN",
    "$env:USERPROFILE\Desktop\내 PC\Fenix 7\Internal Storage\GARMIN",
    "C:\Users\$env:USERNAME\Desktop\내 PC\Forerunner 165\Internal Storage\GARMIN"
)

foreach ($path in $testPaths) {
    if (Test-Path $path) {
        Write-Host "   ✅ 경로 발견: $path" -ForegroundColor Green
        $appsPath = $path + "\Apps"
        if (Test-Path $appsPath) {
            Write-Host "      Apps 폴더: $appsPath" -ForegroundColor White
        }
    }
}

Write-Host ""

# 방법 3: WMI로 MTP 장치 확인
Write-Host "방법 3: WMI로 MTP 장치 확인" -ForegroundColor Yellow
$mtpDevices = Get-WmiObject -Class Win32_PnPEntity | Where-Object { 
    $_.Name -like "*Garmin*" -or $_.Name -like "*Forerunner*" -or $_.PNPClass -eq "WPD"
}

if ($mtpDevices) {
    foreach ($device in $mtpDevices) {
        Write-Host "   ✅ 장치: $($device.Name)" -ForegroundColor Green
        Write-Host "      클래스: $($device.PNPClass)" -ForegroundColor White
    }
} else {
    Write-Host "   ⚠️  MTP 장치를 찾을 수 없습니다." -ForegroundColor Yellow
}

Write-Host ""

Write-Host "💡 Windows 탐색기에서 확인한 경로를 직접 사용하세요:" -ForegroundColor Cyan
Write-Host "   내 PC\Forerunner 165\Internal Storage\GARMIN\Apps" -ForegroundColor White
Write-Host ""


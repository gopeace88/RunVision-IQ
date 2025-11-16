# RunVision-IQ 실제 기기 디버깅 스크립트
# 사용법: .\scripts\debug-device.ps1 -Device fr265

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("fr165", "fr165s", "fr265", "fr265s", "fr955", "fr965", "fenix7", "fenix7s", "fenix7x")]
    [string]$Device = "fr265",
    
    [Parameter(Mandatory=$false)]
    [switch]$BuildOnly = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$InstallOnly = $false
)

# SDK 경로 설정 (workspace 설정에서 읽기 또는 기본값 사용)
$workspaceFile = Join-Path $PSScriptRoot "..\runvision-iq-windows.code-workspace"
$SDKPath = $null
$DeveloperKey = $null

# workspace 파일에서 SDK 경로 읽기
if (Test-Path $workspaceFile) {
    try {
        $workspace = Get-Content $workspaceFile -Raw | ConvertFrom-Json
        if ($workspace.settings.'monkeyC.sdkPath') {
            $SDKPath = $workspace.settings.'monkeyC.sdkPath'
        }
        if ($workspace.settings.'monkeyC.developerKeyPath') {
            $DeveloperKey = $workspace.settings.'monkeyC.developerKeyPath'
        }
    } catch {
        Write-Host "⚠️  workspace 파일 읽기 실패: $_" -ForegroundColor Yellow
    }
}

# 기본값 설정 (workspace에서 읽지 못한 경우)
if (-not $SDKPath) {
    $SDKPath = "C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0"
}
if (-not $DeveloperKey) {
    $DeveloperKey = "C:\Users\jhkim\Garmin\ConnectIQ\developer_key.der"
}

$ProjectRoot = $PSScriptRoot + "\.."
$OutputPath = "$ProjectRoot\bin\RunVisionIQ.prg"

# SDK 존재 확인
if (-not (Test-Path $SDKPath)) {
    Write-Host "❌ SDK를 찾을 수 없습니다: $SDKPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 해결 방법:" -ForegroundColor Cyan
    Write-Host "   1. runvision-iq-windows.code-workspace 파일에서 SDK 경로 확인" -ForegroundColor White
    Write-Host "   2. 또는 SDK 설치 경로 확인" -ForegroundColor White
    Write-Host "   3. WINDOWS-SDK-SETUP.md 참고" -ForegroundColor White
    Write-Host ""
    
    # SDK 경로 찾기 시도
    $possiblePaths = @(
        "$env:USERPROFILE\.Garmin\ConnectIQ\Sdks",
        "C:\Garmin\ConnectIQ\Sdks",
        "D:\Garmin\ConnectIQ\Sdks"
    )
    
    Write-Host "🔍 가능한 SDK 경로 검색 중..." -ForegroundColor Yellow
    foreach ($basePath in $possiblePaths) {
        if (Test-Path $basePath) {
            $sdkDirs = Get-ChildItem $basePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "connectiq-sdk-*" }
            if ($sdkDirs) {
                Write-Host "   ✅ 발견: $($sdkDirs[0].FullName)" -ForegroundColor Green
                Write-Host "   💡 이 경로를 사용하려면 workspace 파일을 업데이트하세요." -ForegroundColor Cyan
            }
        }
    }
    
    exit 1
}

# Developer Key 확인
if (-not (Test-Path $DeveloperKey)) {
    Write-Host "❌ Developer Key를 찾을 수 없습니다: $DeveloperKey" -ForegroundColor Red
    Write-Host "Developer Key를 생성하거나 복사하세요." -ForegroundColor Yellow
    exit 1
}

$MonkeyC = "$SDKPath\bin\monkeyc.exe"
$MonkeyDo = "$SDKPath\bin\monkeydo.exe"

Write-Host "`n🔧 RunVision-IQ 실제 기기 디버깅" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host "기기: $Device" -ForegroundColor White
Write-Host "프로젝트: $ProjectRoot" -ForegroundColor White
Write-Host ""

# 1. 빌드
if (-not $InstallOnly) {
    Write-Host "📦 빌드 중..." -ForegroundColor Yellow
    
    $buildArgs = @(
        "-o", $OutputPath,
        "-f", "$ProjectRoot\monkey.jungle",
        "-y", $DeveloperKey,
        "-d", $Device,
        "-w"  # 경고 표시
    )
    
    & $MonkeyC $buildArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ 빌드 실패!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ 빌드 완료: $OutputPath" -ForegroundColor Green
}

if ($BuildOnly) {
    Write-Host "`n✅ 빌드만 완료했습니다." -ForegroundColor Green
    exit 0
}

# 2. 기기 연결 확인
Write-Host "`n🔍 기기 연결 확인 중..." -ForegroundColor Yellow

# USB 연결 확인 (여러 방법 시도)
$garminPath = $null
$garminDrive = $null

# 방법 1: PSDrive로 찾기
$garminDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like "*GARMIN*" }
if ($garminDrives) {
    $garminDrive = $garminDrives[0]
    $garminPath = $garminDrive.Root + "Garmin\Apps\"
    Write-Host "✅ 드라이브 발견: $($garminDrive.Root)" -ForegroundColor Green
}

# 방법 2: WMI로 찾기
if (-not $garminPath) {
    $garminVolumes = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.VolumeName -like "*GARMIN*" }
    if ($garminVolumes) {
        $volume = $garminVolumes[0]
        $garminPath = $volume.DeviceID + "\Garmin\Apps\"
        Write-Host "✅ 볼륨 발견: $($volume.DeviceID)" -ForegroundColor Green
    }
}

# 방법 3: MTP 장치 확인 및 경로 찾기
$garminDevices = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Garmin*" -or $_.FriendlyName -like "*Forerunner*" -and $_.Status -eq "OK" }
if ($garminDevices) {
    Write-Host "✅ Garmin USB 장치 감지됨" -ForegroundColor Green
    foreach ($device in $garminDevices) {
        Write-Host "   - $($device.FriendlyName)" -ForegroundColor White
    }
    
    # MTP 장치 경로 시도 (Forerunner 165/265 등)
    if (-not $garminPath) {
        # Shell.Application으로 MTP 장치 찾기
        try {
            $shell = New-Object -ComObject Shell.Application
            $namespace = $shell.NameSpace("shell:::{20D04FE0-3AEA-1069-A2D8-08002B30309D}") # 내 PC
            
            if ($namespace) {
                $items = $namespace.Items()
                foreach ($item in $items) {
                    if ($item.Name -like "*Forerunner*" -or $item.Name -like "*Garmin*") {
                        try {
                            # Internal Storage 찾기
                            $deviceFolder = $item.GetFolder
                            $deviceItems = $deviceFolder.Items()
                            
                            $internalStorage = $deviceItems | Where-Object { $_.Name -eq "Internal Storage" }
                            if ($internalStorage) {
                                $internalFolder = $internalStorage.GetFolder
                                $internalItems = $internalFolder.Items()
                                
                                $garminFolder = $internalItems | Where-Object { $_.Name -eq "GARMIN" }
                                if ($garminFolder) {
                                    $garminFolderObj = $garminFolder.GetFolder
                                    $garminItems = $garminFolderObj.Items()
                                    
                                    $appsFolder = $garminItems | Where-Object { $_.Name -eq "Apps" }
                                    if ($appsFolder) {
                                        $garminPath = $appsFolder.Path
                                        Write-Host "✅ MTP 경로 발견: $garminPath" -ForegroundColor Green
                                        break
                                    }
                                }
                            }
                        } catch {
                            # 폴더 탐색 실패 시 다음 항목 시도
                            continue
                        }
                    }
                }
            }
        } catch {
            Write-Host "   ⚠️  Shell.Application 접근 실패: $_" -ForegroundColor Yellow
        }
        
        if (-not $garminPath) {
            Write-Host "   ⚠️  MTP 경로를 자동으로 찾을 수 없습니다." -ForegroundColor Yellow
            Write-Host "   💡 .\scripts\find-mtp-path.ps1 스크립트를 실행하여 경로를 확인하세요." -ForegroundColor Cyan
        }
    }
}

# 3. 기기에 설치
if (-not $BuildOnly) {
    Write-Host "`n📱 기기에 설치 중..." -ForegroundColor Yellow
    
    if ($garminPath -and (Test-Path (Split-Path $garminPath -Parent))) {
        # USB 설치 (드라이브 경로 확인됨)
        $targetPath = $garminPath + "RunVisionIQ.prg"
        try {
            Copy-Item -Path $OutputPath -Destination $targetPath -Force
            Write-Host "✅ USB로 설치 완료: $targetPath" -ForegroundColor Green
            Write-Host "`n💡 워치에서 앱을 실행하세요:" -ForegroundColor Cyan
            Write-Host "   1. 워치에서 Run 앱 실행" -ForegroundColor White
            Write-Host "   2. Data Screen 추가" -ForegroundColor White
            Write-Host "   3. RunVision IQ 선택" -ForegroundColor White
        } catch {
            Write-Host "❌ 파일 복사 실패: $_" -ForegroundColor Red
            Write-Host "   수동으로 복사하세요: $OutputPath → $targetPath" -ForegroundColor Yellow
        }
    } else {
        # MTP 경로로 설치 시도 (Shell.Application으로 찾은 경로 사용)
        if ($garminPath) {
            $targetPath = $garminPath + "\RunVisionIQ.prg"
            try {
                # Shell.Application을 사용하여 파일 복사
                $shell = New-Object -ComObject Shell.Application
                $appsFolder = $shell.NameSpace($garminPath)
                $sourceFile = $shell.NameSpace((Split-Path $OutputPath -Parent)).ParseName((Split-Path $OutputPath -Leaf))
                
                if ($appsFolder -and $sourceFile) {
                    $appsFolder.CopyHere($sourceFile, 0x14) # 0x14 = SHFILEOP_FLAGS.FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR
                    Write-Host "✅ MTP 경로로 설치 완료: $targetPath" -ForegroundColor Green
                    Write-Host "`n💡 워치에서 앱을 실행하세요:" -ForegroundColor Cyan
                    Write-Host "   1. 워치에서 Run 앱 실행" -ForegroundColor White
                    Write-Host "   2. Data Screen 추가" -ForegroundColor White
                    Write-Host "   3. RunVision IQ 선택" -ForegroundColor White
                } else {
                    throw "Shell.Application으로 파일 복사 실패"
                }
            } catch {
                Write-Host "   ⚠️  MTP 경로 복사 실패: $_" -ForegroundColor Yellow
                Write-Host "   💡 수동으로 복사하세요:" -ForegroundColor Cyan
                Write-Host "      Windows 탐색기에서 $garminPath 열기" -ForegroundColor White
                Write-Host "      → $OutputPath 파일을 복사" -ForegroundColor White
            }
        } else {
            # Wi-Fi 설치 시도 또는 수동 안내
            Write-Host "📡 Wi-Fi 연결로 설치 시도..." -ForegroundColor Yellow
            & $MonkeyDo $OutputPath $Device
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Wi-Fi로 설치 완료" -ForegroundColor Green
            } else {
                Write-Host "❌ 자동 설치 실패" -ForegroundColor Red
                Write-Host ""
                Write-Host "💡 수동 설치 방법:" -ForegroundColor Cyan
                Write-Host "   1. Windows 탐색기 열기" -ForegroundColor White
                Write-Host "   2. '내 PC\Forerunner 165\Internal Storage\GARMIN\Apps' 경로로 이동" -ForegroundColor White
                Write-Host "   3. 다음 파일을 복사:" -ForegroundColor White
                Write-Host "      $OutputPath" -ForegroundColor Gray
                Write-Host "      → 내 PC\Forerunner 165\Internal Storage\GARMIN\Apps\RunVisionIQ.prg" -ForegroundColor Gray
            }
        }
    }
}

# 4. 로그 확인 안내
Write-Host "`n📋 디버깅 로그 확인 방법:" -ForegroundColor Cyan
Write-Host "   1. VS Code Output 패널 → 'Monkey C' 선택" -ForegroundColor White
Write-Host "   2. 시뮬레이터 → View → Log Viewer" -ForegroundColor White
Write-Host "   3. 워치에서 앱 실행 후 로그 확인" -ForegroundColor White
Write-Host ""

Write-Host "✅ 완료!" -ForegroundColor Green


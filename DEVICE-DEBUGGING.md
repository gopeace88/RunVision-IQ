# 실제 기기 디버깅 가이드

이 가이드는 Garmin 워치에 직접 연결하여 RunVision-IQ 앱을 디버깅하는 방법을 설명합니다.

## 📋 준비 사항

1. ✅ Windows Connect IQ SDK 설치 완료
2. ✅ Developer Key 생성 및 복사 완료
3. ✅ Garmin 워치 (Forerunner 165/265, Fenix 7 등)
4. ✅ USB 케이블 또는 Wi-Fi 연결

---

## 🔌 방법 1: USB 연결 (권장)

### USB 연결

**Garmin Express로 연결이 잘 되고 있다면 추가 설정은 필요 없습니다!**

USB 케이블로 워치를 PC에 연결하고 Garmin Express가 기기를 인식하면 됩니다.

### Step 1: 기기 연결 확인

```powershell
# 기기 연결 확인 스크립트 실행
.\scripts\check-device.ps1
```

또는 수동으로:
- USB 케이블로 워치를 PC에 연결
- Windows 탐색기에서 `GARMIN` 드라이브가 나타나는지 확인
- 경로: `GARMIN:\Garmin\Apps\`

### Step 2: 빌드 및 설치

```powershell
# 자동 빌드 및 설치
.\scripts\debug-device.ps1 -Device fr265

# 특정 기기 지정
.\scripts\debug-device.ps1 -Device fr165
.\scripts\debug-device.ps1 -Device fenix7
```

### Step 3: 워치에서 앱 실행

1. 워치에서 **Run** 앱 실행
2. **Settings** → **Data Screens** → **Add**
3. **RunVision IQ** 선택
4. 러닝 시작하여 데이터 확인

---

## 📡 방법 2: Wi-Fi 연결

### Step 1: Connect IQ Manager 설정

1. **Connect IQ Manager 실행**:
   ```
   C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin\connectiq.exe
   ```

2. **기기 등록**:
   - 워치에서 **Settings** → **System** → **Connect IQ**
   - **Developer Settings** 활성화
   - Wi-Fi 연결 정보 확인

3. **Manager에서 기기 추가**:
   - Connect IQ Manager → **Devices** → **Add Device**
   - 워치의 IP 주소 또는 기기명 입력

### Step 2: Wi-Fi로 설치

```powershell
# 빌드
.\scripts\debug-device.ps1 -Device fr265 -BuildOnly

# Wi-Fi로 설치 (monkeydo 사용)
$SDK = "C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0"
& "$SDK\bin\monkeydo.exe" bin\RunVisionIQ.prg fr265
```

---

## 🐛 VS Code에서 디버깅

### 방법 1: 디버그 설정 사용

1. **VS Code에서 F5** 누르기
2. **디버그 설정 선택**:
   - `Run on Forerunner 265 (Device)` ← 실제 기기
   - `Run on Forerunner 265 (Simulator)` ← 시뮬레이터

3. **브레이크포인트 설정**:
   - 소스 코드 줄 번호 왼쪽 클릭
   - 빨간 점 표시됨

4. **디버깅 기능**:
   - 변수 값 확인
   - Call Stack 확인
   - Step Over/Into/Out (F10/F11/Shift+F11)
   - Watch 표현식 추가

### 방법 2: 수동 빌드 후 디버깅

```powershell
# 1. 빌드
.\scripts\debug-device.ps1 -Device fr265 -BuildOnly

# 2. VS Code에서 F5 → 디버그 설정 선택
```

---

## 📊 로그 확인

### VS Code Output 패널

1. **View** → **Output** (Ctrl+Shift+U)
2. 드롭다운에서 **"Monkey C"** 선택
3. 앱 실행 시 로그 자동 표시

### 코드에서 로그 출력

```monkey-c
// source/RunVisionIQView.mc
(:debug)
function onUpdate(dc) {
    Sys.println("Debug: onUpdate called");
    Sys.println("Velocity: " + velocity);
    // ...
}
```

**주의**: `(:debug)` 어노테이션을 사용하면 디버그 빌드에서만 로그가 출력됩니다.

### 시뮬레이터 Log Viewer

1. 시뮬레이터 실행
2. **View** → **Log Viewer**
3. 실시간 로그 확인

---

## 🔧 문제 해결

### 문제 1: 스크립트에서 기기를 찾을 수 없음

**Garmin Express로 연결이 잘 되는데 스크립트에서 인식 못하는 경우:**

**해결책**:

1. **Windows 탐색기에서 확인**:
   - Windows 탐색기에서 `GARMIN` 드라이브가 보이는지 확인
   - 드라이브 문자 확인 (예: G:\)

2. **수동 설치**:
   - Windows 탐색기에서 `GARMIN:\Garmin\Apps\` 폴더로 이동
   - `bin\RunVisionIQ.prg` 파일을 복사

3. **Wi-Fi 설치 사용**:
   - `monkeydo`를 사용하여 Wi-Fi로 설치
   - 또는 Connect IQ Manager 사용

4. **USB 케이블 및 포트 확인**:
   - 다른 USB 케이블 시도
   - 다른 USB 포트 시도
   - USB 3.0 포트 사용 권장

### 문제 2: 빌드 실패

**해결책**:
```powershell
# SDK 경로 확인
$SDK = "C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0"
Test-Path $SDK

# Developer Key 확인
$Key = "C:\Users\jhkim\Garmin\ConnectIQ\developer_key.der"
Test-Path $Key
```

### 문제 3: 앱이 워치에 나타나지 않음

**해결책**:
1. 워치 재시작
2. `GARMIN:\Garmin\Apps\` 폴더에서 `.prg` 파일 확인
3. 워치에서 **Settings** → **Apps** → **RunVision IQ** 확인

### 문제 4: 디버깅이 작동하지 않음

**해결책**:
- `-w` 플래그로 빌드 (경고 포함)
- 디버그 빌드 확인: `bin\RunVisionIQ.prg.debug.xml` 파일 존재 여부
- VS Code Monkey C Extension 설치 확인

---

## 📝 빠른 참조

### 빌드 명령어

```powershell
# 기본 빌드 (fr265)
.\scripts\debug-device.ps1 -Device fr265

# 빌드만 (설치 안 함)
.\scripts\debug-device.ps1 -Device fr265 -BuildOnly

# 설치만 (이미 빌드된 파일 사용)
.\scripts\debug-device.ps1 -Device fr265 -InstallOnly
```

### 지원 기기

- `fr165`, `fr165s` - Forerunner 165
- `fr265`, `fr265s` - Forerunner 265
- `fr955`, `fr965` - Forerunner 955/965
- `fenix7`, `fenix7s`, `fenix7x` - Fenix 7 시리즈

### 디버그 설정 (launch.json)

```json
{
  "type": "monkeyc",
  "request": "launch",
  "name": "Run on Forerunner 265 (Device)",
  "device": "fr265",
  "runOnDevice": true,  // ← 실제 기기 사용
  "program": "${workspaceFolder}/bin/RunVisionIQ.prg"
}
```

---

## ✅ 체크리스트

디버깅 전 확인 사항:

- [ ] SDK 설치 완료
- [ ] Developer Key 복사 완료
- [ ] 기기 USB 또는 Wi-Fi 연결 확인
- [ ] 빌드 성공 확인
- [ ] 워치에 앱 설치 확인
- [ ] VS Code 디버그 설정 확인
- [ ] 브레이크포인트 설정 완료

---

## 🚀 다음 단계

1. **BLE 연결 테스트**: iLens 글래스와 BLE 연결 확인
2. **데이터 전송 테스트**: 러닝 중 메트릭 전송 확인
3. **성능 최적화**: 배터리 및 메모리 사용량 모니터링


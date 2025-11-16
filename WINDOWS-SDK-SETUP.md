# Windows Connect IQ SDK + WSL 연동 가이드

## ✅ 가능 여부

**네, Windows Connect IQ SDK로 WSL과 연결하여 디버깅이 가능합니다!**

### 장점
- ✅ GUI 문제 없음 (Windows 네이티브 실행)
- ✅ WSL 소스 코드 직접 사용 가능
- ✅ VS Code에서 통합 개발 환경 구성 가능
- ✅ 시뮬레이터 디버깅 지원
- ✅ 실제 기기 디버깅 지원

---

## 📋 설정 방법

### 1. Windows Connect IQ SDK 설치

1. **SDK 다운로드**:
   - https://developer.garmin.com/connect-iq/sdk/
   - Windows 버전 다운로드 (예: `connectiq-sdk-win-8.3.0-2025-09-22-5813687a0.exe`)

2. **SDK 설치**:
   - 기본 경로: `C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\`
   - 또는 원하는 경로에 설치

3. **Developer Key 복사**:
   ```powershell
   # WSL의 키를 Windows로 복사
   copy \\wsl$\Ubuntu-20.04\home\jhkim\Garmin\ConnectIQ\developer_key.der C:\Users\jhkim\Garmin\ConnectIQ\developer_key.der
   ```

### 2. VS Code 설정

#### 방법 A: Windows에서 WSL 파일 직접 접근 (권장)

1. **VS Code를 Windows에서 실행**
2. **프로젝트 열기**:
   ```
   D:\00.Projects\00.RunVision-IQ
   ```
   (WSL의 `/mnt/d/00.Projects/00.RunVision-IQ`는 Windows에서 `D:\00.Projects\00.RunVision-IQ`)

3. **Workspace 파일 사용**:
   - `runvision-iq-windows.code-workspace` 파일 열기
   - 또는 수동으로 설정:
     ```json
     {
       "monkeyC.sdkPath": "C:\\Garmin\\ConnectIQ\\Sdks\\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0",
       "monkeyC.developerKeyPath": "C:\\Users\\jhkim\\Garmin\\ConnectIQ\\developer_key.der",
       "monkeyC.outputPath": "${workspaceFolder}\\bin",
       "monkeyC.jungleFile": "${workspaceFolder}\\monkey.jungle",
       "monkeyC.defaultDevice": "fr265"
     }
     ```

#### 방법 B: WSL Remote Extension 사용

1. **VS Code에서 WSL 확장 설치**:
   - Extensions → "Remote - WSL" 설치

2. **WSL에서 VS Code 실행**:
   ```bash
   code /mnt/d/00.Projects/00.RunVision-IQ
   ```

3. **Windows SDK 경로 설정**:
   - WSL에서 Windows 경로 접근: `/mnt/c/Garmin/ConnectIQ/Sdks/...`
   - 또는 Windows에서 빌드, WSL에서 편집

### 3. 빌드 및 실행

#### Windows PowerShell에서:

```powershell
# 프로젝트 디렉토리로 이동
cd D:\00.Projects\00.RunVision-IQ

# 빌드
C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin\monkeyc.exe `
  -o bin\RunVisionIQ.prg `
  -f monkey.jungle `
  -y C:\Users\jhkim\Garmin\ConnectIQ\developer_key.der `
  -d fr265 `
  -w

# 시뮬레이터 실행
C:\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin\monkeydo.exe bin\RunVisionIQ.prg fr265
```

#### VS Code에서:

1. **F5 (디버그 시작)** 또는 **Ctrl+F5 (디버그 없이 실행)**
2. **터미널에서 빌드**: `Ctrl+Shift+P` → "Monkey C: Build"
3. **시뮬레이터 실행**: `Ctrl+Shift+P` → "Monkey C: Run in Simulator"

---

## 🐛 디버깅 방법

### 1. 시뮬레이터 디버깅

1. **VS Code에서 F5 누르기**
2. **시뮬레이터 창 열림**
3. **브레이크포인트 설정**:
   - 소스 코드에서 줄 번호 왼쪽 클릭
   - 빨간 점 표시됨

4. **디버깅 기능**:
   - 변수 값 확인
   - Call Stack 확인
   - Step Over/Into/Out
   - Watch 표현식 추가

### 2. 실제 기기 디버깅

1. **기기 연결**:
   - USB로 Garmin 워치 연결
   - 또는 Wi-Fi로 연결 (지원 기기)

2. **디버그 모드 빌드**:
   ```powershell
   monkeyc.exe -o bin\RunVisionIQ.prg -f monkey.jungle -y developer_key.der -d fr265 -w
   ```

3. **기기에 설치 및 실행**:
   - 시뮬레이터에서 "Send to Device" 또는
   - Garmin Express로 설치

4. **로그 확인**:
   - VS Code Output 패널에서 "Monkey C" 선택
   - 또는 시뮬레이터의 Log Viewer

### 3. 로그 출력

```monkey-c
// source/RunVisionIQView.mc
(:debug)
function onUpdate(dc) {
    Sys.println("Debug: onUpdate called");
    // ...
}
```

---

## 🔧 문제 해결

### 문제 1: SDK 경로를 찾을 수 없음

**해결**:
- `monkeyC.sdkPath`가 정확한지 확인
- Windows 경로는 백슬래시 이스케이프: `C:\\Garmin\\...`

### 문제 2: Developer Key 오류

**해결**:
```powershell
# WSL에서 Windows로 키 복사
copy \\wsl$\Ubuntu-20.04\home\jhkim\Garmin\ConnectIQ\developer_key.der C:\Users\jhkim\Garmin\ConnectIQ\
```

### 문제 3: 파일 경로 문제

**해결**:
- WSL 경로: `/mnt/d/00.Projects/00.RunVision-IQ`
- Windows 경로: `D:\00.Projects\00.RunVision-IQ`
- 둘 다 같은 파일 시스템을 가리킴

---

## 📝 권장 워크플로우

1. **코드 편집**: VS Code (Windows 또는 WSL Remote)
2. **빌드**: Windows SDK 사용 (`monkeyc.exe`)
3. **디버깅**: Windows 시뮬레이터 또는 실제 기기
4. **소스 관리**: WSL에서 Git 사용 가능

---

## ✅ 확인 사항

- [ ] Windows Connect IQ SDK 설치 완료
- [ ] Developer Key 복사 완료
- [ ] VS Code Monkey C Extension 설치
- [ ] Workspace 설정 완료
- [ ] 빌드 성공 확인
- [ ] 시뮬레이터 실행 확인


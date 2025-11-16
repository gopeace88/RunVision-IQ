# Garmin 기기 개발자 모드 설정 가이드

이 문서는 Garmin 워치에서 개발자 모드를 활성화하여 USB 디버깅을 가능하게 하는 방법을 설명합니다.

## 📱 워치에서 개발자 모드 활성화

### ⚠️ 중요: Connect IQ Store 앱 먼저 설치 필요

**대부분의 기기에서 Connect IQ Store 앱을 먼저 설치해야 개발자 설정이 나타납니다!**

1. **Connect IQ Store 앱 설치**:
   - 워치에서 **Apps** 메뉴 열기
   - **Connect IQ Store** 앱 찾기
   - 설치 (이미 설치되어 있다면 스킵)

2. **Connect IQ Store 앱 실행**:
   - Apps 메뉴에서 **Connect IQ Store** 실행
   - 최소 한 번은 실행하여 초기화

### 방법 1: Settings 메뉴에서 찾기

#### Forerunner 165/265 시리즈

**경로 A (일반적)**:
```
Settings (설정)
→ Apps (앱)
→ Connect IQ
→ Developer Settings (개발자 설정)
→ USB Debugging (USB 디버깅) ✅
```

**경로 B**:
```
Settings (설정)
→ System (시스템)
→ Connect IQ
→ Developer Settings
→ USB Debugging ✅
```

**경로 C (직접)**:
```
Settings (설정)
→ Connect IQ (직접 표시)
→ Developer Settings
→ USB Debugging ✅
```

#### Fenix 7 시리즈

```
MENU 버튼
→ Settings
→ Apps
→ Connect IQ
→ Developer Settings
→ USB Debugging ✅
```

### 방법 2: Apps 메뉴에서 찾기

일부 기기에서는 Apps 메뉴에서 직접 접근:

```
Apps (앱)
→ Connect IQ (또는 Connect IQ Store)
→ Settings (설정 아이콘 또는 메뉴)
→ Developer Settings
→ USB Debugging ✅
```

### 방법 3: Connect IQ Manager 사용 (대안)

워치에서 직접 찾을 수 없다면:

1. **PC에서 Connect IQ Manager 실행**:
   ```
   C:\Garmin\ConnectIQ\Sdks\...\bin\connectiq.exe
   ```

2. **Manager에서 기기 연결**:
   - USB로 워치 연결
   - Manager → Devices → 기기 선택
   - Manager가 자동으로 개발자 모드 활성화 안내

### USB 연결 모드 확인

USB 케이블 연결 시:
- 워치에 "USB 연결" 알림 표시
- **"파일 전송"** 또는 **"MTP"** 모드 선택
- **"충전 전용"** 모드가 아닌지 확인

### Fenix 7 시리즈

1. **설정 메뉴**:
   ```
   MENU 버튼
   → Settings
   → System
   → Connect IQ
   → Developer Settings
   → USB Debugging ✅
   ```

2. **USB 연결 모드**:
   - USB 연결 시 알림에서 **"File Transfer"** 선택

### Forerunner 955/965

1. **설정 경로**:
   ```
   Settings
   → System
   → Connect IQ
   → Developer Settings
   → USB Debugging ✅
   ```

---

## 🔌 USB 연결 확인

### Windows에서 확인

1. **Windows 탐색기 열기**
2. **드라이브 목록 확인**:
   - `GARMIN` 또는 `GARMIN (D:)` 드라이브가 나타나야 함
3. **Apps 폴더 확인**:
   - `GARMIN:\Garmin\Apps\` 폴더 접근 가능해야 함

### PowerShell로 확인

```powershell
# 기기 연결 확인 스크립트 실행
.\scripts\check-device.ps1

# 또는 수동 확인
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like "*GARMIN*" }
```

---

## ⚠️ 문제 해결

### 문제 1: "개발자 설정" 메뉴가 보이지 않음

**가장 흔한 원인**: Connect IQ Store 앱이 설치되지 않았거나 실행되지 않음

**해결책 (순서대로 시도)**:

1. **Connect IQ Store 앱 확인**:
   ```
   Apps 메뉴
   → Connect IQ Store 찾기
   → 없으면 설치
   → 최소 한 번 실행하여 초기화
   ```

2. **다양한 경로 시도**:
   - `Settings → Apps → Connect IQ`
   - `Settings → System → Connect IQ`
   - `Apps → Connect IQ → Settings`
   - `Settings → Connect IQ` (직접)

3. **Connect IQ Store에서 앱 설치**:
   - Connect IQ Store 앱 실행
   - 아무 앱이나 하나 설치
   - 개발자 설정이 나타날 수 있음

4. **워치 펌웨어 업데이트**:
   - Garmin Connect Mobile 앱에서 펌웨어 업데이트 확인
   - 최신 버전으로 업데이트

5. **워치 재시작**:
   - Connect IQ Store 설치/실행 후 워치 재시작

6. **Connect IQ Manager 사용** (대안):
   - PC에서 Connect IQ Manager 실행
   - USB로 기기 연결
   - Manager가 자동으로 개발자 모드 안내

### 문제 2: USB 연결 시 드라이브가 나타나지 않음

**해결책**:

1. **USB 케이블 확인**:
   - 데이터 전송 지원 케이블 사용 (충전 전용 케이블 X)
   - 원본 Garmin 케이블 사용 권장

2. **USB 포트 확인**:
   - USB 3.0 포트 사용 권장
   - 다른 USB 포트 시도
   - USB 허브 사용 시 직접 연결 시도

3. **Windows 드라이버 확인**:
   ```
   장치 관리자 열기
   → 휴대용 장치 또는 기타 장치
   → "GARMIN" 또는 "MTP" 장치 확인
   → 드라이버 업데이트 또는 재설치
   ```

4. **워치 재시작**:
   - 개발자 모드 활성화 후 워치 재시작

### 문제 3: "USB 디버깅" 옵션이 비활성화됨

**해결책**:
1. **Connect IQ 앱 업데이트 확인**
2. **워치 펌웨어 최신 버전 확인**
3. **개발자 모드 활성화 후 워치 재시작**

### 문제 4: USB 연결은 되지만 앱 설치가 안 됨

**해결책**:
1. **Apps 폴더 권한 확인**:
   - `GARMIN:\Garmin\Apps\` 폴더에 쓰기 권한 확인
   - 관리자 권한으로 실행 시도

2. **파일 시스템 확인**:
   - 워치가 FAT32 또는 exFAT로 포맷되어 있는지 확인
   - 일부 기기는 내부 저장소만 지원

---

## 📋 체크리스트

USB 디버깅 설정 전 확인 사항:

- [ ] 워치에서 **Settings → System → Connect IQ** 접근 가능
- [ ] **Developer Settings** 메뉴 표시됨
- [ ] **USB Debugging** 옵션 활성화됨
- [ ] USB 케이블 연결 시 워치에 알림 표시됨
- [ ] Windows에서 `GARMIN` 드라이브 인식됨
- [ ] `GARMIN:\Garmin\Apps\` 폴더 접근 가능
- [ ] PowerShell 스크립트로 기기 확인됨

---

## 🔄 워크플로우

1. **워치에서 개발자 모드 활성화**
2. **USB 케이블 연결**
3. **Windows에서 드라이브 확인**
4. **빌드 및 설치 스크립트 실행**
5. **워치에서 앱 실행 및 디버깅**

---

## 💡 추가 팁

### Wi-Fi 디버깅 (대안)

USB 연결이 안 될 경우 Wi-Fi 디버깅 사용:

1. **Connect IQ Manager 실행**:
   ```
   C:\Garmin\ConnectIQ\Sdks\...\bin\connectiq.exe
   ```

2. **워치에서 Wi-Fi 정보 확인**:
   ```
   Settings → System → Connect IQ → Developer Settings
   → Wi-Fi IP 주소 확인
   ```

3. **Manager에서 기기 추가**:
   - Connect IQ Manager → Devices → Add Device
   - IP 주소 입력

### USB vs Wi-Fi

| 항목 | USB | Wi-Fi |
|------|-----|-------|
| 속도 | 빠름 | 보통 |
| 안정성 | 높음 | 중간 |
| 설정 | 간단 | 복잡 |
| 권장 | ✅ | ⚠️ |

---

## 📞 추가 지원

문제가 계속되면:
1. Garmin Developer 포럼 확인
2. Connect IQ SDK 문서 참고
3. 기기별 펌웨어 업데이트 확인


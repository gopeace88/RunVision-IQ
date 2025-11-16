# RunVision-IQ Project - Development Context

**프로젝트**: RunVision-IQ - Garmin Connect IQ Activity App with iLens Integration
**회사**: RTK
**홈페이지**: www.rtk.ai
**이메일**: info@rtk.ai
**플랫폼**: Garmin Connect IQ (Monkey C)
**대상 기기**: Forerunner 265, 955, 965, Fenix 7 등 (BLE Central 지원 기기)
**개발 철학**: "Simple > Feature-rich" - 사용자 경험 우선

---

## 📋 프로젝트 개요

### 목적
Garmin 워치에서 직접 러닝 데이터를 수집하고 iLens AR 스마트 글래스에 실시간으로 전송하는 Connect IQ Activity 앱 개발.

### 핵심 기능
1. **GPS 수집**: Garmin Position API로 실시간 위치 추적
2. **센서 수집**: HRM (심박수), Cadence (케이던스) 실시간 수집
3. **Activity Recording**: Garmin 네이티브 Activity Recording으로 FIT 파일 생성
4. **Garmin Connect 자동 저장**: 세션 종료 시 자동으로 Garmin Connect에 업로드
5. **iLens BLE 연결**: BLE Central로 iLens에 연결하여 실시간 메트릭 전송

### 아키텍처 개선 (vs RunVision Flutter)
- ✅ **중간 브릿지 제거**: Flutter 앱 불필요, Garmin 워치만으로 완결
- ✅ **네이티브 GPS**: Garmin Position API 사용 (Phone GPS 불필요)
- ✅ **자동 저장**: Activity Recording으로 Garmin Connect 자동 동기화
- ✅ **배터리 최적화**: 단일 기기 동작으로 배터리 효율 향상
- ✅ **사용자 경험**: 워치만으로 모든 기능 완료, Phone 불필요

---

## 🏗️ 아키텍처

### System Overview

```
┌─────────────────────────────────────────────────────┐
│   Garmin 워치 (Connect IQ App)                       │
├─────────────────────────────────────────────────────┤
│ ✅ GPS 수집 (Position API)                           │
│ ✅ 센서 수집 (Sensor API - HRM, Cadence)            │
│ ✅ Activity Recording (FIT 파일 생성)                │
│ ✅ Garmin Connect 자동 저장                          │
│                                                     │
│ BLE Central 연결:                                   │
│  └─ iLens 스캔 ("iLens-sw")                         │
│  └─ Service: 4b329cf2-ace2-4a8a-9d49-38d7ab674867  │
│  └─ Char: c259c1bd-e5fa-4fab-aabe-015c9ab26cd3     │
│  └─ 실시간 데이터 전송 (1Hz)                         │
└─────────────────────────────────────────────────────┘
             ↓ BLE (WRITE, 1Hz)
┌─────────────────────────────────────────────────────┐
│      iLens AR 글래스 (Peripheral)                    │
├─────────────────────────────────────────────────────┤
│ ✅ 실시간 메트릭 표시                                 │
│  - 속도 (km/h)                                      │
│  - 거리 (km)                                        │
│  - 케이던스 (spm)                                   │
│  - 심박수 (bpm)                                     │
└─────────────────────────────────────────────────────┘
```

### Connect IQ App 구조

```
RunVisionIQApp/
├── source/
│   ├── RunVisionIQApp.mc        # Main Application
│   ├── RunVisionIQView.mc       # Main View (Activity UI)
│   ├── RunVisionIQDelegate.mc   # Input Handler
│   ├── ILensManager.mc          # BLE Central Manager
│   ├── DataCollector.mc         # GPS + Sensor Collection
│   └── ActivityRecorder.mc      # Activity Recording
├── resources/
│   ├── layouts/
│   │   └── layout.xml           # UI Layout
│   ├── drawables/
│   │   └── launcher_icon.png
│   ├── strings/
│   │   └── strings.xml          # 다국어 지원
│   └── settings/
│       └── settings.xml         # 앱 설정 (iLens 연결 옵션 등)
├── manifest.xml                 # App Manifest
├── Docs/                        # 프로젝트 문서
└── README.md
```

### 데이터 흐름 (1Hz)

```
[Position API] ─┐
                ├─> [DataCollector] ─> [ActivityRecorder] ─> FIT File
[Sensor API]  ─┘         ↓
                   [ILensManager]
                         ↓
                   [BLE Central]
                         ↓
                   iLens Peripheral
```

---

## 🔄 개발 워크플로우

### Phase 1: 개발 환경 설정 (Week 1)

**1. Connect IQ SDK 설치**
```bash
# Connect IQ SDK 다운로드
https://developer.garmin.com/connect-iq/sdk/

# Visual Studio Code Extension 설치
- "Monkey C" Extension by Garmin

# 또는 Eclipse 플러그인
https://developer.garmin.com/connect-iq/programmers-guide/getting-started/
```

**2. 프로젝트 생성**
```bash
# Connect IQ 프로젝트 생성 (GUI 또는 CLI)
monkeyc --create-project \
  --name "RunVisionIQ" \
  --type "activity" \
  --device "forerunner265"

# 또는 VS Code에서: Monkey C: New Project
```

**3. 필수 권한 설정 (manifest.xml)**
```xml
<iq:manifest>
  <iq:application entry="RunVisionIQApp" id="your-app-id">
    <iq:products>
      <iq:product id="forerunner265"/>
      <iq:product id="forerunner955"/>
      <iq:product id="forerunner965"/>
      <iq:product id="fenix7"/>
      <!-- BLE Central 지원 기기만 추가 -->
    </iq:products>

    <iq:permissions>
      <iq:uses-permission id="Positioning"/>
      <iq:uses-permission id="Sensor"/>
      <iq:uses-permission id="SensorHistory"/>
      <iq:uses-permission id="FitContributor"/>
      <iq:uses-permission id="PersistedContent"/>
      <iq:uses-permission id="BluetoothLowEnergy"/>
    </iq:permissions>

    <iq:languages>
      <iq:language>eng</iq:language>
      <iq:language>kor</iq:language>
    </iq:languages>
  </iq:application>
</iq:manifest>
```

### Phase 2: 핵심 모듈 개발 (Week 2~4)

**Week 2: Activity Recording + GPS/Sensor**
1. ✅ Activity Recording 기본 구조
2. ✅ Position API 통합 (GPS)
3. ✅ Sensor API 통합 (HRM, Cadence)
4. ✅ FIT 파일 생성 확인

**Week 3: BLE Central 통합**
1. ✅ BLE Central Manager 구현
2. ✅ iLens 스캔 및 연결
3. ✅ 실시간 데이터 전송 (1Hz)
4. ✅ 재연결 로직

**Week 4: UI 및 사용자 경험**
1. ✅ Activity View 구현
2. ✅ 실시간 메트릭 표시
3. ✅ 세션 시작/일시정지/종료 제어
4. ✅ 에러 핸들링 및 사용자 피드백

### Phase 3: 테스트 및 배포 (Week 5~6)

**Week 5: 시뮬레이터 테스트**
```bash
# 시뮬레이터 실행
monkeyc --build \
  --manifest manifest.xml \
  --output RunVisionIQ.prg

# 또는 VS Code: Monkey C: Run (Simulator)
```

**Week 6: 실제 기기 테스트 및 배포**
```bash
# 실제 기기에 배포
# 1. Garmin Express로 기기 연결
# 2. Developer Mode 활성화
# 3. VS Code: Monkey C: Run (Device)

# Connect IQ Store 제출
https://apps.garmin.com/developer
```

---

## 📚 핵심 API 및 클래스

### Position API (GPS)
```monkey-c
using Toybox.Position;

class DataCollector {
  var positionInfo;

  function initialize() {
    Position.enableLocationEvents(
      Position.LOCATION_CONTINUOUS,
      method(:onPosition)
    );
  }

  function onPosition(info) {
    positionInfo = info;
    // info.position (LatLng)
    // info.speed (m/s)
    // info.altitude (m)
  }
}
```

### Sensor API (HRM, Cadence)
```monkey-c
using Toybox.Sensor;

class DataCollector {
  var heartRate;
  var cadence;

  function initialize() {
    Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_BIKECADENCE]);
    Sensor.enableSensorEvents(method(:onSensor));
  }

  function onSensor(info) {
    heartRate = info.heartRate;
    cadence = info.cadence;
  }
}
```

### Activity Recording
```monkey-c
using Toybox.ActivityRecording;

class ActivityRecorder {
  var session;

  function start() {
    session = ActivityRecording.createSession({
      :name => "Running",
      :sport => ActivityRecording.SPORT_RUNNING,
      :subSport => ActivityRecording.SUB_SPORT_GENERIC
    });
    session.start();
  }

  function stop() {
    session.stop();
    session.save();  // Garmin Connect에 자동 업로드
  }
}
```

### BLE Central API
```monkey-c
using Toybox.BluetoothLowEnergy as Ble;

class ILensManager {
  const ILENS_SERVICE_UUID = Ble.stringToUuid("4b329cf2-ace2-4a8a-9d49-38d7ab674867");
  const ILENS_CHAR_UUID = Ble.stringToUuid("c259c1bd-e5fa-4fab-aabe-015c9ab26cd3");

  var profileManager;
  var device;
  var characteristic;

  function scanForILens() {
    profileManager = Ble.getProfileManager();
    profileManager.registerProfile({
      :uuid => ILENS_SERVICE_UUID,
      :callback => method(:onScanResult)
    });

    Ble.setScanState(Ble.SCAN_STATE_SCANNING);
  }

  function onScanResult(scanResult) {
    if (scanResult.getName().equals("iLens-sw")) {
      device = scanResult.getDevice();
      profileManager.connect(device);
    }
  }

  function sendData(speed, distance, cadence, heartRate) {
    // iLens 프로토콜에 맞춰 데이터 전송
    var payload = encodeILensPayload(speed, distance, cadence, heartRate);
    characteristic.write(payload, {});
  }
}
```

---

## 🧪 테스트 전략

### 시뮬레이터 테스트
- **Connect IQ Simulator** 사용
- GPS 경로 시뮬레이션 (GPX 파일)
- 센서 데이터 시뮬레이션

### 실제 기기 테스트
- **필수 기기**: Forerunner 265 (BLE Central 지원 확인)
- **테스트 항목**:
  1. GPS 정확도 (실외 러닝)
  2. 센서 안정성 (HRM, Cadence)
  3. iLens 연결 및 데이터 전송
  4. Activity Recording 및 Garmin Connect 동기화
  5. 배터리 소모 측정

### 배터리 최적화
- BLE 전송 주기: 1Hz (1초마다)
- GPS 모드: LOCATION_CONTINUOUS (Activity 앱 표준)
- 센서 활성화: HRM, Cadence만 활성화

---

## 📚 참조 문서

### 문서 구조 (프로젝트별 분리)

```
/mnt/d/00.Projects/00.RunVision/
├── runvision/              # Flutter 프로젝트 (기존)
│   ├── lib/
│   ├── Docs/               # Flutter 프로젝트 문서
│   └── .claude/
│       └── CLAUDE.md       # Flutter 컨텍스트
├── runvision-iq/           # Connect IQ 프로젝트 (신규)
│   ├── source/
│   ├── Docs/               # Connect IQ 프로젝트 문서
│   └── .claude/
│       └── CLAUDE.md       # Connect IQ 컨텍스트 (현재 문서)
└── .claude/
    └── CLAUDE.md           # 루트 레벨 통합 컨텍스트
```

### Tier 1: 요구사항 문서 (작성 예정)

**1. PRD-RunVision-IQ.md**
- **목적**: Connect IQ 앱 제품 요구사항 정의서
- **내용**:
  - 제품 개요 및 목표
  - 사용자 시나리오
  - 기능 명세 (GPS, Sensor, BLE, Activity Recording)
  - 성능 요구사항 (배터리, 정확도)
  - 호환성 (대상 기기 목록)

### Tier 2: 고수준 설계 문서 (작성 예정)

**2. System-Architecture.md**
- **목적**: Connect IQ 앱 아키텍처 설계
- **내용**:
  - 모듈 구조 (DataCollector, ILensManager, ActivityRecorder)
  - 데이터 흐름 (1Hz)
  - 상태 관리
  - 에러 처리

**3. Tech-Stack.md**
- **목적**: Connect IQ 기술 스택 결정
- **내용**:
  - Connect IQ SDK 버전
  - 필수 API (Position, Sensor, BLE, ActivityRecording)
  - 대상 기기 및 호환성

### Tier 3: 저수준 설계 문서 (작성 예정)

**4. Module-Design.md**
- **목적**: 각 모듈 상세 설계
- **내용**:
  - DataCollector 클래스 상세
  - ILensManager BLE 프로토콜
  - ActivityRecorder FIT 파일 생성

**5. Test-Specification.md**
- **목적**: 테스트 케이스 명세
- **내용**:
  - 시뮬레이터 테스트
  - 실제 기기 테스트
  - 배터리 테스트

### Supporting Documents

**6. iLens-BLE-Protocol.md**
- **위치**: `/mnt/d/00.Projects/00.RunVision/runvision/Docs/` (공유 문서)
- **목적**: iLens BLE 프로토콜 사양
- **재사용**: Flutter 프로젝트 문서 참조

### 외부 리소스
- [Connect IQ 공식 문서](https://developer.garmin.com/connect-iq/overview/)
- [Monkey C API Documentation](https://developer.garmin.com/connect-iq/api-docs/)
- [BLE Central Guide](https://developer.garmin.com/connect-iq/core-topics/bluetooth-low-energy/)
- [Activity Recording Guide](https://developer.garmin.com/connect-iq/core-topics/activity-recording/)
- [Position API Reference](https://developer.garmin.com/connect-iq/api-docs/Toybox/Position.html)

---

## 🎯 개발 가이드라인

### 코드 스타일

**Monkey C 스타일 가이드**:
- 들여쓰기: 4 spaces
- 클래스명: PascalCase
- 메서드명: camelCase
- 상수: UPPER_SNAKE_CASE

### Commit 메시지 규칙

**Conventional Commits** 형식 (Flutter 프로젝트와 동일):
```
<type>(<scope>): <subject>

<body>

<footer>
```

**예시**:
```
feat(ble): iLens BLE Central 연결 구현

- ILensManager 클래스 추가
- 스캔 및 연결 로직 구현
- 재연결 메커니즘 추가

Closes #5
```

---

## 🐛 디버깅 및 트러블슈팅

### Connect IQ 시뮬레이터

```bash
# 로그 확인
System.println("Debug message");

# 시뮬레이터 콘솔에서 확인 가능
```

### 실제 기기 디버깅

```bash
# USB 연결 후 로그 확인
# Garmin Express Developer Mode 활성화 필요
```

### BLE 연결 문제

**증상**: iLens 스캔 안 됨
- BLE 권한 확인 (manifest.xml)
- iLens 기기 활성화 확인
- UUID 정확성 확인

**증상**: 데이터 전송 실패
- Characteristic Write 권한 확인
- 페이로드 포맷 검증

---

## 📝 개발 진행 상황

### ✅ 완료
- [x] 프로젝트 구조 설계
- [x] 문서 폴더 분리 (runvision-iq/Docs/)

### 🔄 진행 중
- [ ] 요구사항 문서 작성 (PRD)

### 📅 예정
- [ ] Connect IQ 프로젝트 생성 (Week 1)
- [ ] Activity Recording 구현 (Week 2)
- [ ] BLE Central 통합 (Week 3)
- [ ] UI 개발 (Week 4)
- [ ] 테스트 및 배포 (Week 5~6)

---

**마지막 업데이트**: 2025-11-15
**다음 액션**: PRD 작성 및 Connect IQ 프로젝트 초기화

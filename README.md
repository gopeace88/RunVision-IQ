# RunVision-IQ

**Garmin Connect IQ DataField for iLens AR Smart Glasses**

RunVision-IQ는 Garmin 시계의 러닝 메트릭을 iLens AR 스마트 글래스로 실시간 전송하는 DataField 앱입니다.

## 📋 프로젝트 개요

- **플랫폼**: Garmin Connect IQ
- **SDK 버전**: 8.4.0
- **언어**: Monkey C
- **API Level**: 3.1.0+ (BLE Central 필수)
- **호환 디바이스** (28개, Garmin 검증 완료):
  - **Forerunner**: 265/265S, 570 (42mm/47mm), 955, 965, 970
  - **Fenix 7**: 7/7S/7X, 7 Pro/7S Pro/7X Pro
  - **Fenix 8**: 8 AMOLED (43mm/47mm/51mm), 8 Solar (47mm/51mm)
  - **Epix Pro**: 42mm/47mm/51mm
  - **Enduro**: 2, 3
  - **tactix**: 7, 7 AMOLED, 8 (47mm AMOLED/51mm Solar)
  - **D2**: Mach 1 Pro

> **Compatible Devices**
> Garmin devices supporting Connect IQ `Toybox.BluetoothLowEnergy` (BLE Central role).
> Actual compatibility depends on firmware and system limitations.
>
> 상세 정보: [BLE-Central-Device-Compatibility.md](../Docs/runvision-iq/BLE-Central-Device-Compatibility.md)

## 🎯 주요 기능

### 구현 완료 (Week 1-3)
- ✅ iLens BLE 자동 스캔 및 연결
- ✅ 실시간 러닝 메트릭 수집
  - 속도 (km/h)
  - 심박수 (bpm)
  - 케이던스 (spm)
  - 거리 (km) - Week 2
  - 운동 시간 (분:초) - Week 2
  - 페이스 (분/km) - Week 3 ⭐
- ✅ 통계 추적 - Week 3 ⭐
  - 평균 속도 (km/h)
  - 최대 심박수 (bpm)
- ✅ iLens로 메트릭 전송 (BLE WRITE)
- ✅ DataField UI 표시
  - 연결 상태
  - 현재 메트릭 값 (7개)
  - 통계 (2개)

## 📁 프로젝트 구조

```
runvision-iq/
├── source/
│   ├── RunVisionIQApp.mc         # Application entry point (23 lines)
│   ├── RunVisionIQView.mc        # DataField View (284 lines)
│   ├── ILens.mc                  # iLens BLE Central (296 lines)
│   └── ILensProtocol.mc          # iLens BLE Protocol (104 lines)
├── resources/
│   ├── drawables/
│   │   ├── drawables.xml         # Launcher icon definition
│   │   └── launcher_icon.png     # App icon
│   └── strings/
│       └── strings.xml           # Localization strings
├── bin/
│   └── RunVisionIQ.prg          # Compiled binary (106KB)
├── manifest.xml                  # App manifest
├── monkey.jungle                 # Build configuration
└── README.md                     # This file
```

**총 코드**: 707 lines

## 🔧 빌드 방법

### 환경 설정

1. **Garmin SDK 설치**:
```bash
# SDK 다운로드 및 설치
mkdir -p ~/.Garmin/ConnectIQ/Sdks
cd ~/.Garmin/ConnectIQ/Sdks
# SDK 8.4.0 설치
```

2. **환경 변수 설정** (`~/.garmin_env.sh`):
```bash
export GARMIN_SDK_HOME=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-8.4.0-2025-12-03-5122605dc
export PATH=$GARMIN_SDK_HOME/bin:$PATH
export GARMIN_DEV_KEY=~/Garmin/ConnectIQ/developer_key

alias ciq-build='monkeyc -o bin/RunVisionIQ.prg -f monkey.jungle -y $GARMIN_DEV_KEY'
alias ciq-version='monkeyc --version'
```

3. **디바이스 데이터베이스 다운로드**:
```bash
source ~/.garmin_env.sh
~/Garmin/ConnectIQ/Sdks/bin/connect-iq-sdk-manager login --username "your-email@example.com" --password "your-password"
~/Garmin/ConnectIQ/Sdks/bin/connect-iq-sdk-manager device download -m manifest.xml
```

### 빌드 실행

```bash
source ~/.garmin_env.sh
ciq-build
# 또는
monkeyc -o bin/RunVisionIQ.prg -f monkey.jungle -y $GARMIN_DEV_KEY --device fr265
```

**성공 시**: `BUILD SUCCESSFUL`, `bin/RunVisionIQ.prg` (110KB) 생성

## 📱 사용 방법

### 1. Garmin 시계에 설치
1. Garmin Express 또는 Connect IQ Store를 통해 설치
2. 러닝 Activity에서 DataField로 추가

### 2. iLens 연결
1. iLens AR 글래스 전원 켜기
2. RunVision-IQ DataField 실행
3. 자동으로 "iLens" 이름을 가진 기기 스캔 및 연결
4. 연결 상태 확인: "iLens: Connected" 표시

### 3. 러닝 시작
1. Garmin 시계에서 러닝 Activity 시작
2. RunVision-IQ가 실시간으로 메트릭 수집
3. iLens로 자동 전송:
   - 속도: 매 초마다 업데이트
   - 심박수: 매 초마다 업데이트
   - 케이던스: 매 초마다 업데이트

## 🔌 iLens BLE Protocol

### Service & Characteristic
- **Service UUID**: `4b329cf2-3816-498c-8453-ee8798502a08`
- **Characteristic UUID**: `c259c1bd-18d3-c348-b88d-5447aea1b615`
- **Permission**: WRITE only

### Packet Structure (5 bytes)
```
[Metric_ID (1 byte)] [Value (4 bytes, Little-Endian UINT32)]
```

### Supported Metrics
| Metric ID | Name | Unit | Description |
|-----------|------|------|-------------|
| 0x07 | Velocity | km/h | Current speed |
| 0x0B | Heart Rate | bpm | Current heart rate |
| 0x0E | Cadence | spm | Running cadence (steps per minute) |
| 0x06 | Distance | meters | Total distance ✅ |
| 0x03 | Exercise Time | seconds | Elapsed time ✅ |

### Example Packet
```
속도 15 km/h 전송:
[0x07, 0x0F, 0x00, 0x00, 0x00]
 │      └────────┬────────┘
 │               └─ 15 (0x0000000F, Little-Endian)
 └─ Velocity Metric ID
```

## 🏗️ 아키텍처

### 코드 구조

```
RunVisionIQApp
    └─> RunVisionIQView (DataField)
            ├─> ILens (BLE Central)
            │     └─> BLE Callbacks
            │           ├─> onILensConnected
            │           ├─> onILensDisconnected
            │           ├─> onILensError
            │           └─> onILensScanResult
            │
            └─> ILensProtocol (Packet Encoding)
                  ├─> createVelocityPacket
                  ├─> createHeartRatePacket
                  └─> createCadencePacket
```

### 데이터 흐름

```
Garmin Activity
    ↓ (compute() 매 초 호출)
RunVisionIQView.compute(info)
    ↓
info.currentSpeed → speedKmh
info.currentHeartRate → hr
info.currentCadence → cadence
    ↓
ILensProtocol.createXXXPacket(value)
    ↓ (5-byte packet)
ILens.writeMetric(packet)
    ↓ (BLE WRITE)
iLens AR Glasses
```

## 🔬 개발 히스토리

### Week 1 (Day 1-5)
- **Day 1**: 프로젝트 초기 설정, SDK 구성
- **Day 2-3**: ActiveLook 소스 분석 (참조용)
- **Day 4**: iLens BLE Protocol 구현 (ILensProtocol.mc)
- **Day 5**: iLens BLE Central 구현 (ILens.mc, callback 패턴)
- **Day 5**: RunVisionIQView 간소화 작성

**빌드 진행**:
1. 초기 빌드: 100KB (skeleton)
2. ActiveLook 통합: 182KB
3. ILensProtocol 추가: 184KB
4. ILens 추가: 189KB
5. **Week 1 최종 (ActiveLook 제거)**: 110KB ✅

### Week 2 (Day 6-7)
- **Distance 메트릭 추가**: elapsedDistance → km 변환 및 iLens 전송
- **Exercise Time 메트릭 추가**: timerTime → 분:초 형식 및 iLens 전송
- **UI 확장**: 5개 메트릭 표시 (Speed, HR, Cadence, Distance, Time)
- **연결 안정성 개선**:
  - 재연결 시도 횟수 제한 (최대 5회)
  - Write 실패 감지 및 자동 연결 해제 (연속 3회 실패 시)
  - 연결 성공 시 카운터 자동 리셋
  - canRetry() / resetRetryCount() 메서드 추가
- **Week 2 빌드**: 105KB (코드 660줄) ✅

### Week 3 (Day 8)
- **페이스 메트릭 추가**: 속도 → 분/km 변환 (러닝 페이스 표시)
- **통계 추적 기능**:
  - 평균 속도 계산 (누적 평균)
  - 최대 심박수 추적 (세션 중 최고값)
  - onTimerReset()에서 통계 자동 리셋
- **UI 재배치**: 7개 메트릭 + 2개 통계 표시
  - Row 1: Speed, Pace
  - Row 2: HR, Cadence
  - Row 3: Distance, Time
  - Row 4: Avg Speed, Max HR
- **Week 3 빌드**: 106KB (코드 707줄) ✅

### Week 4 (Day 9-10) - iLens Integration 완료
- **🎯 Current Time 전송 성공**:
  - Device Config Service Profile 등록 문제 해결
  - ILENS_CONFIG_PROFILE 추가 등록으로 getService() 성공
  - Current Time Characteristic 발견 및 전송 완료
- **⏱️ Exercise Time 전송 개선**:
  - Current Time Characteristic을 운동 경과 시간 전송에 활용
  - 날짜: 오늘 날짜 (year/month/day)
  - 시간: 운동 경과 시간 (hour/min/sec)
  - iLens RTC 자동 증가 활용 (매초 전송 불필요)
  - Exercise Time metric (0x03) 제거 (중복)
- **🔧 디버그 UI 모드**:
  - BLE 로그 8줄 표시 (FONT_SMALL)
  - TX 로그 8줄 표시 (FONT_SMALL)
  - 데이터 필드 숨김 (디버깅 용이)
  - 진단 로깅 강화 (Profile 등록, Service 발견, Characteristic 검색)
- **Week 4 빌드**: 135KB ✅

## 📝 기술 노트

### Monkey C Interface 이슈
- Monkey C는 custom interface methods를 제대로 지원하지 않음
- 해결책: `Lang.Method` callback 패턴 사용
- `setCallbacks()` 메서드로 callback 등록

### BLE registerProfile()
- ActiveLook과 달리 device 파라미터 불필요
- `BluetoothLowEnergy.registerProfile(profile)` 형태로 호출

### DataField compute()
- 매 초마다 자동 호출 (Activity 실행 중)
- `Activity.Info` 객체로 실시간 메트릭 접근
- 무거운 작업 피해야 함 (1초 내 완료)

### Connection Stability
- **재연결 제한**: 최대 5회 재시도 후 중단 (배터리 절약)
- **Write 실패 감지**: 연속 3회 실패 시 연결 해제 및 재연결
- **자동 복구**: 성공적인 연결 시 모든 카운터 리셋
- **canRetry()**: UI에서 재시도 가능 여부 확인
- **resetRetryCount()**: 수동 연결 시 카운터 초기화

## 🚀 향후 계획

### Week 2 (완료)
- [x] 거리(Distance) 메트릭 추가
- [x] 운동 시간(Exercise Time) 메트릭 추가
- [x] 연결 안정성 개선 (재시도 제한, Write 실패 감지)

### Week 3 (완료)
- [x] UI 개선 (페이스, 평균 속도, 최대 심박수)
- [x] 통계 추적 기능 (평균 속도, 최대 심박수)

### Week 4 (완료)
- [x] Device Config Service Profile 등록 문제 해결
- [x] Current Time 전송 성공 (iLens RTC 동기화)
- [x] Exercise Time을 Current Time으로 전송 (날짜: 오늘, 시간: 경과 시간)
- [x] 디버그 UI 모드 구현 (로그 8줄 표시)
- [ ] 실제 Garmin 기기에서 테스트 (하드웨어 필요)
- [ ] iLens AR 글래스 연동 테스트 (하드웨어 필요)

### Week 5 (계획)
- [ ] 일반 모드 UI 개선 (간단한 연결 상태 표시)
- [ ] 디버그 모드 / 일반 모드 전환 (settings.xml)
- [ ] 기기별 레이아웃 최적화 (아이콘 추가)
- [ ] 설정 화면 추가 (자동 연결, 재시도 횟수 등)
- [ ] 배터리 최적화 (Write 빈도 조절, 스마트 전송)
- [ ] 추가 통계 (평균 케이던스, 평균 심박수)

## 📝 Connect IQ Store 등록 정보

### App Description (English)
```
RunVision-IQ displays real-time running metrics on iLens/rLens AR smart glasses.

Features:
• Real-time speed, heart rate, cadence display
• Distance and elapsed time tracking
• Pace calculation (min/km)
• Average speed and max heart rate statistics
• Auto-connect to iLens/rLens glasses

Requirements:
• iLens or rLens AR Smart Glasses

Compatible Devices:
Garmin devices supporting Connect IQ Toybox.BluetoothLowEnergy (BLE Central role).
Actual compatibility depends on firmware and system limitations.
```

### App Description (한국어)
```
RunVision-IQ는 iLens/rLens AR 스마트 글래스에 실시간 러닝 데이터를 표시합니다.

기능:
• 실시간 속도, 심박수, 케이던스 표시
• 거리 및 운동 시간 추적
• 페이스 계산 (분/km)
• 평균 속도 및 최대 심박수 통계
• iLens/rLens 글래스 자동 연결

요구사항:
• iLens 또는 rLens AR 스마트 글래스

호환 기기:
Connect IQ Toybox.BluetoothLowEnergy (BLE Central)를 지원하는 Garmin 기기.
실제 호환성은 펌웨어 및 시스템 제한에 따라 다를 수 있습니다.
```

## 📄 라이선스

이 프로젝트는 RunVisionLabs (www.runvision.ai)의 프로젝트입니다.

## 👥 Contact

- **Company**: RunVisionLabs
- **Website**: www.runvision.ai
- **Email**: support@runvision.ai
- **Address**: 경기도 용인시 기흥구 동백중앙로 191, J831

---

**Last Updated**: 2026-01-06
**Version**: 1.0.0 (Connect IQ Store Release)

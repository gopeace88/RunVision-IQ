
# Changelog

All notable changes to RunVision-IQ will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.4.0] - 2025-11-16 (Week 4 Complete - iLens Integration)

### Added
- **Current Time Characteristic 전송 성공**
  - Device Config Service UUID: `58211c97-482a-2808-2d3e-228405f1e749`
  - Current Time Characteristic UUID: `54ac7f82-eb87-aa4e-0154-a71d80471e6e`
  - 10-byte packet: [year(2), month(1), day(1), hour(1), min(1), sec(1), dow(1), fraction256(1), reason(1)]
- **Exercise Time을 Current Time으로 전송**
  - 날짜: 오늘 날짜 (year/month/day)
  - 시간: 운동 경과 시간 (hour/min/sec from _elapsedSeconds)
  - iLens RTC 자동 증가 활용 (매초 전송 불필요)
- **디버그 UI 모드**
  - BLE 로그 8줄 표시 (FONT_SMALL)
  - TX 로그 8줄 표시 (FONT_SMALL)
  - 데이터 필드 숨김 (트러블슈팅 용이)
- **진단 로깅 강화**
  - Profile 등록 카운트 추적
  - Service 발견 상태 로깅 (cfg:try, cfg:NULL!, cfg:FOUND!)
  - Characteristic 검색 재시도 추적 (time:ex<seconds>)

### Fixed
- **Device Config Service Profile 등록 문제 해결**
  - ILENS_CONFIG_PROFILE 추가 등록
  - `BluetoothLowEnergy.registerProfile(ILENS_CONFIG_PROFILE)` 추가
  - getService(DEVICE_CONFIG_SERVICE_UUID) 성공

### Changed
- **ILensProtocol.createCurrentTimePacket()** 함수 개선
  - 선택적 매개변수 `elapsedSeconds` 추가
  - null이면 현재 시간 사용 (기존 동작)
  - null이 아니면 운동 경과 시간 사용 (hour/min/sec 계산)

### Removed
- **Exercise Time metric (0x03) 전송 제거**
  - Current Time Characteristic으로 운동 시간 전송하므로 중복
  - 매초 메트릭 전송 불필요 (iLens RTC 자동 증가)

### Technical Details
- **Build Size**: 135KB (106KB → 135KB, 디버그 로깅 증가)
- **App ID**: `a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d` (변경, 신규 설치 강제)
- **Version**: 1.0.1

---

## [1.3.0] - 2025-11-15 (Week 3 Complete - Pace + Statistics)

### Added
- **페이스 메트릭 추가**
  - 속도 → 분/km 변환 (러닝 페이스 표시)
  - Velocity 필드로 전송 (Garmin: 5:50 → 550, iLens: 550 ÷ 100 = 5.50)
- **통계 추적 기능**
  - 평균 속도 계산 (누적 평균)
  - 최대 심박수 추적 (세션 중 최고값)
  - onTimerReset()에서 통계 자동 리셋
- **UI 재배치**
  - 7개 메트릭 + 2개 통계 표시
  - Row 1: Speed, Pace
  - Row 2: HR, Cadence
  - Row 3: Distance, Time
  - Row 4: Avg Speed, Max HR

### Technical Details
- **Build Size**: 106KB
- **Code Lines**: 707줄

---

## [1.2.0] - 2025-11-14 (Week 2 Complete - Extended Metrics)

### Added
- **거리(Distance) 메트릭 추가**
  - elapsedDistance → km 변환 및 iLens 전송
  - Metric ID: 0x06
- **운동 시간(Exercise Time) 메트릭 추가**
  - timerTime → 분:초 형식 및 iLens 전송
  - Metric ID: 0x03
- **UI 확장**
  - 5개 메트릭 표시 (Speed, HR, Cadence, Distance, Time)

### Fixed
- **연결 안정성 개선**
  - 재연결 시도 횟수 제한 (최대 5회)
  - Write 실패 감지 및 자동 연결 해제 (연속 3회 실패 시)
  - 연결 성공 시 카운터 자동 리셋
  - canRetry() / resetRetryCount() 메서드 추가

### Technical Details
- **Build Size**: 105KB
- **Code Lines**: 660줄

---

## [1.1.0] - 2025-11-13 (Week 1 Complete - ActiveLook Removal)

### Added
- **iLens BLE Protocol 구현** (ILensProtocol.mc)
  - Exercise Service UUID: `4b329cf2-3816-498c-8453-ee8798502a08`
  - Characteristic UUID: `c259c1bd-18d3-c348-b88d-5447aea1b615`
  - 5-byte packet structure: [Metric_ID(1), Value(4, Little-Endian)]
- **iLens BLE Central 구현** (ILens.mc)
  - Callback 패턴 (onILensConnected, onILensDisconnected, onILensError, onILensScanResult)
  - 자동 스캔 및 연결
- **RunVisionIQView 간소화**
  - 3개 기본 메트릭 (속도, 심박수, 케이던스)
  - 실시간 데이터 수집 및 전송

### Removed
- **ActiveLook 의존성 제거**
  - ActiveLook Protocol 대신 iLens Protocol 사용
  - 코드 간소화 및 빌드 크기 감소

### Technical Details
- **Build Size**: 110KB (189KB → 110KB)
- **Code Lines**: ~600줄

---

## [1.0.0] - 2025-11-12 (Initial Release)

### Added
- **프로젝트 초기 설정**
  - Garmin Connect IQ SDK 8.3.0 환경 구축
  - DataField 타입 앱 구조
  - Forerunner 265/955/965, Fenix 7 지원
- **ActiveLook 소스 분석** (참조용)
  - BLE Central 패턴 학습
  - Protocol 구조 이해

### Technical Details
- **Build Size**: 100KB (skeleton)

---

## 향후 계획 (Week 5)

### Planned
- [ ] 일반 모드 UI 개선 (간단한 연결 상태 표시)
- [ ] 디버그 모드 / 일반 모드 전환 (settings.xml)
- [ ] 기기별 레이아웃 최적화 (선택적, 아이콘 추가)
- [ ] 배터리 최적화 및 성능 튜닝
- [ ] 실제 Garmin 기기에서 테스트
- [ ] iLens AR 글래스 연동 테스트

---

**Legend**:
- `Added`: 새로운 기능
- `Changed`: 기존 기능 변경
- `Deprecated`: 곧 제거될 기능
- `Removed`: 제거된 기능
- `Fixed`: 버그 수정
- `Security`: 보안 관련 수정

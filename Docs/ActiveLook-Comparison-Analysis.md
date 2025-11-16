# ActiveLook Garmin DataField 분석 및 RunVision-IQ 비교

**문서 버전**: v1.0
**작성일**: 2025-11-15
**작성자**: Claude (AI Assistant)
**상태**: Draft
**목적**: ActiveLook 샘플 코드 분석 및 RunVision-IQ 프로젝트와의 차이점 명확화

---

## 📋 목차

1. [ActiveLook 프로젝트 개요](#1-activelook-프로젝트-개요)
2. [핵심 아키텍처 분석](#2-핵심-아키텍처-분석)
3. [RunVision-IQ와의 차이점](#3-runvision-iq와의-차이점)
4. [적용 가능한 패턴](#4-적용-가능한-패턴)
5. [기술적 교훈](#5-기술적-교훈)
6. [RunVision-IQ 목표 재정의](#6-runvision-iq-목표-재정의)

---

## 1. ActiveLook 프로젝트 개요

### 1.1 프로젝트 정보

**저장소**: https://github.com/ActiveLook/Garmin-Datafield-sample-code
**앱 유형**: **DataField** (데이터 필드)
**목적**: 기존 Garmin 운동 앱에 추가되어 ActiveLook 스마트 안경에 메트릭 표시
**지원 기기**: 88개 Garmin 기기 (Fenix, Forerunner, Edge, Epix 등)
**최소 SDK**: 3.1.0

### 1.2 DataField vs Activity App

| 항목 | DataField (ActiveLook) | Activity App (RunVision-IQ) |
|------|------------------------|----------------------------|
| **실행 방식** | 기존 운동 앱에 플러그인 형태로 추가 | 독립 실행 앱 |
| **활동 기록** | 호스트 앱이 담당 (Garmin 네이티브) | 자체 ActivityRecording API 사용 |
| **데이터 수집** | `compute(info)` 자동 호출 (50ms 주기) | Timer 기반 명시적 수집 (1Hz) |
| **생명주기** | 호스트 앱에 의존 | 독립적 생명주기 관리 |
| **UI** | 데이터 필드 영역만 (제한적) | 전체 화면 제어 가능 |
| **FIT 파일** | 호스트 앱이 생성 | 자체 생성 및 관리 |

**핵심 차이**: ActiveLook은 **보조 도구**이고, RunVision-IQ는 **완전한 운동 앱**입니다.

---

## 2. 핵심 아키텍처 분석

### 2.1 BLE Central 구현 (ActiveLookBLE.mc)

#### 2.1.1 싱글톤 패턴

```monkey-c
module ActiveLook {
    var ble = null;  // 싱글톤 인스턴스

    function getBle() {
        if (ble == null) {
            ble = new ActiveLookBLE();
        }
        return ble;
    }
}
```

**교훈**: BLE 연결은 앱 전체에서 단일 인스턴스로 관리해야 합니다.

#### 2.1.2 프로필 순차 등록

```monkey-c
// ActiveLookBLE.mc - setUp() 메서드
function setUp() {
    if (_profilesRegistered) { return; }

    // 1. Primary Service 먼저 등록
    BluetoothLowEnergy.registerProfile(self, PRIMARY_SERVICE_UUID);

    // 2. onProfileRegister() 콜백에서 다음 프로필 등록
    // 3. 총 3개 프로필: Primary, DeviceInfo, Battery
}

function onProfileRegister(uuid, status) {
    if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
        if (uuid.equals(PRIMARY_SERVICE_UUID)) {
            BluetoothLowEnergy.registerProfile(self, DEVICE_INFO_UUID);
        } else if (uuid.equals(DEVICE_INFO_UUID)) {
            BluetoothLowEnergy.registerProfile(self, BATTERY_UUID);
        } else if (uuid.equals(BATTERY_UUID)) {
            _profilesRegistered = true;
        }
    }
}
```

**이유**: "registration can fail if too many profiles are registered" - 메모리 제약

**RunVision-IQ 적용**:
```monkey-c
// 우리는 iLens BLE 프로필 1개만 필요
BluetoothLowEnergy.registerProfile(self, ILENS_SERVICE_UUID);
```

#### 2.1.3 스캔 프로세스

```monkey-c
function requestScanning() {
    if (!_profilesRegistered) {
        setUp();  // 프로필 미등록 시 먼저 등록
        return;
    }

    BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
}

function onScanResults(scanResults) {
    for (var i = 0; i < scanResults.size(); i++) {
        var result = scanResults[i];

        // 제조사 데이터 필터링 (0x08F2 = Microoled)
        var manufacturerData = result.getManufacturerSpecificData(0x08F2);
        if (manufacturerData != null) {
            // ActiveLook 기기 발견
            _foundDevices.add(result);
        }
    }
}
```

**RunVision-IQ 적용**:
```monkey-c
// iLens 기기 필터링 (iLens 제조사 ID 필요)
var manufacturerData = result.getManufacturerSpecificData(ILENS_MANUFACTURER_ID);
```

#### 2.1.4 연결 흐름

```
1. requestScanning()
   ↓
2. onScanResults() → 기기 발견
   ↓
3. connect(deviceAddress)
   ↓
4. BluetoothLowEnergy.pairDevice()
   ↓
5. onConnectedStateChanged(device, state)
   ↓
6. 특성값 읽기/쓰기/알림 활성화
```

#### 2.1.5 특성값 읽기 (재시도 로직)

```monkey-c
function getBleCharacteristicActiveLookRx() {
    return tryGetServiceCharacteristic(
        PRIMARY_SERVICE_UUID,
        TX_CHARACTERISTIC_UUID,
        5  // 최대 5회 재시도
    );
}

function tryGetServiceCharacteristic(serviceUuid, charUuid, maxRetries) {
    for (var i = 0; i < maxRetries; i++) {
        var service = _device.getService(serviceUuid);
        if (service != null) {
            var characteristic = service.getCharacteristic(charUuid);
            if (characteristic != null) {
                return characteristic;
            }
        }
    }
    return null;
}
```

**교훈**: BLE 특성값 읽기는 실패할 수 있으므로 재시도 로직 필수

#### 2.1.6 알림 활성화

```monkey-c
// CCCD (Client Characteristic Configuration Descriptor) 쓰기
var txChar = getBleCharacteristicActiveLookRx();
var cccdDescriptor = txChar.getDescriptor(CCCD_UUID);

// 0x0001 = Notification 활성화
var cccdValue = [0x01, 0x00]b;
cccdDescriptor.requestWrite(cccdValue);
```

### 2.2 데이터 수집 (ActiveLookDataFieldView.mc)

#### 2.2.1 compute() 함수 (자동 호출)

```monkey-c
class ActiveLookDataFieldView extends WatchUi.DataField {

    // Garmin OS가 약 50ms마다 자동 호출
    function compute(info) {
        // 1. 센서 데이터 수집
        var currentSpeed = info.currentSpeed;        // m/s
        var currentHeartRate = info.currentHeartRate; // bpm
        var currentCadence = info.currentCadence;     // spm
        var elapsedDistance = info.elapsedDistance;   // m

        // 2. 데이터 처리 (누적, 계산)
        AugmentedActivityInfo.accumulate(info);
        AugmentedActivityInfo.compute(info);

        // 3. 랩 데이터 계산
        Laps.compute(info);

        // 4. 안경으로 데이터 전송
        updateFields();
    }
}
```

**RunVision-IQ 차이점**:
- DataField: `compute(info)` 자동 호출 (Garmin OS 관리)
- Activity App: `Timer.start(method(:onTimer), 1000, true)` 명시적 호출

#### 2.2.2 데이터 전송 (updateFields)

```monkey-c
function updateFields() {
    if (!sdk.isDeviceReady()) {
        return;  // 안경 미연결 시 무시
    }

    // 메트릭 ID 기반 데이터 전송
    var metricsToSend = getMetricsForCurrentLayout();

    for (var i = 0; i < metricsToSend.size(); i++) {
        var metricId = metricsToSend[i];
        var value = getMetricValue(metricId);
        var formattedText = formatMetric(metricId, value);

        // SDK 명령 버퍼에 추가
        sdk.commandBuffer().text(
            LINE_ID_MAP[i],     // 줄 번호 (0-3)
            formattedText,      // "5.2 km/h"
            FONT_MEDIUM,
            TEXT_ALIGN_CENTER
        );
    }

    // 버퍼 전송
    sdk.sendCommandBuffer();
}
```

**47개 메트릭 예시**:
- ID 1: Chrono (시간)
- ID 2: Distance (거리)
- ID 4: Heart Rate (심박수)
- ID 7: Power (파워)
- ID 13: Cadence (케이던스)

### 2.3 메모리 최적화

**ActiveLook 주석**:
> "Connect IQ devices are embedded systems with very limited memory. Every byte counts."

**최적화 기법**:
1. **전역 변수 최소화**: 모듈 레벨 변수 대신 싱글톤 패턴
2. **문자열 재사용**: 동일 문자열 반복 생성 금지
3. **배열 크기 고정**: 동적 할당 최소화
4. **릴리스 빌드 로깅 제거**: `(:debug)` 어노테이션 활용

```monkey-c
// 디버그 모드에서만 로깅
(:debug)
function log(message) {
    System.println(message);
}

(:release)
function log(message) {
    // 릴리스에서는 아무것도 하지 않음
}
```

---

## 3. RunVision-IQ와의 차이점

### 3.1 앱 유형 차이

| 요소 | ActiveLook (DataField) | RunVision-IQ (Activity) |
|------|------------------------|-------------------------|
| **진입점** | `ActiveLookDataFieldView extends WatchUi.DataField` | `RunVisionApp extends System.Application` |
| **메인 뷰** | DataField 영역만 | `WatchUi.View` 전체 화면 |
| **생명주기** | `initialize()`, `compute()`, `onUpdate()` | `onStart()`, `onStop()`, `getInitialView()` |

### 3.2 데이터 수집 차이

| 요소 | ActiveLook | RunVision-IQ |
|------|-----------|--------------|
| **수집 방식** | `compute(info)` 자동 호출 | `Timer` 기반 명시적 호출 |
| **수집 주기** | 약 50ms (Garmin OS 관리) | 1000ms (1Hz, 개발자 제어) |
| **데이터 소스** | `Activity.Info` 객체 | `Position.getInfo()`, `Sensor.getInfo()` |
| **GPS** | 호스트 앱이 관리 | `Position.enableLocationEvents()` 직접 관리 |

### 3.3 활동 기록 차이

| 요소 | ActiveLook | RunVision-IQ |
|------|-----------|--------------|
| **FIT 파일** | 호스트 앱이 생성 | `ActivityRecording.fit()` 직접 생성 |
| **세션 관리** | 호스트 앱이 관리 | `Session.start()`, `Session.save()` 직접 관리 |
| **Garmin Connect** | 호스트 앱이 업로드 | ActivityRecording 자동 업로드 |

### 3.4 BLE 구현 (공통점 ✅)

| 요소 | ActiveLook | RunVision-IQ |
|------|-----------|--------------|
| **BLE 역할** | Central | Central |
| **Base 클래스** | `BluetoothLowEnergy.BleDelegate` | `BluetoothLowEnergy.BleDelegate` |
| **프로필 등록** | 순차 등록 (3개) | 순차 등록 (1개) |
| **스캔 방식** | `setScanState(SCANNING)` | `setScanState(SCANNING)` |
| **연결 방식** | `pairDevice()` | `pairDevice()` |

**결론**: BLE 구현 패턴은 동일하게 적용 가능합니다.

---

## 4. 적용 가능한 패턴

### 4.1 BLE Manager 싱글톤 패턴 ✅

**ActiveLook 패턴**:
```monkey-c
module ActiveLook {
    var ble = null;
    function getBle() {
        if (ble == null) { ble = new ActiveLookBLE(); }
        return ble;
    }
}
```

**RunVision-IQ 적용**:
```monkey-c
module ILens {
    var bleManager = null;

    function getBleManager() {
        if (bleManager == null) {
            bleManager = new ILensBleManager();
        }
        return bleManager;
    }
}

// 사용
var ble = ILens.getBleManager();
ble.requestScanning();
```

### 4.2 프로필 순차 등록 ✅

**RunVision-IQ는 프로필 1개만 필요**:
```monkey-c
class ILensBleManager extends BluetoothLowEnergy.BleDelegate {

    const ILENS_SERVICE_UUID = BluetoothLowEnergy.stringToUuid(
        "4b329cf2-ace2-4a8a-9d49-38d7ab674867"
    );

    private var _profileRegistered = false;

    function setUp() {
        if (_profileRegistered) { return; }
        BluetoothLowEnergy.registerProfile(self, ILENS_SERVICE_UUID);
    }

    function onProfileRegister(uuid, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileRegistered = true;
        }
    }
}
```

### 4.3 스캔 필터링 ✅

**ActiveLook 패턴** (제조사 ID 필터):
```monkey-c
function onScanResults(scanResults) {
    for (var i = 0; i < scanResults.size(); i++) {
        var result = scanResults[i];
        var manufacturerData = result.getManufacturerSpecificData(0x08F2);
        if (manufacturerData != null) {
            _foundDevices.add(result);
        }
    }
}
```

**RunVision-IQ 적용** (Service UUID 필터):
```monkey-c
function onScanResults(scanResults) {
    for (var i = 0; i < scanResults.size(); i++) {
        var result = scanResults[i];
        var serviceUuids = result.getServiceUuids();

        // iLens Service UUID 포함 여부 확인
        if (serviceUuids != null && serviceUuids.indexOf(ILENS_SERVICE_UUID) != -1) {
            _foundDevices.add(result);
        }
    }
}
```

### 4.4 특성값 읽기 재시도 로직 ✅

```monkey-c
class ILensBleManager {

    function getILensCharacteristic() {
        return tryGetServiceCharacteristic(
            ILENS_SERVICE_UUID,
            ILENS_CHARACTERISTIC_UUID,
            5  // 최대 5회 재시도
        );
    }

    function tryGetServiceCharacteristic(serviceUuid, charUuid, maxRetries) {
        for (var i = 0; i < maxRetries; i++) {
            if (_device == null) { return null; }

            var service = _device.getService(serviceUuid);
            if (service != null) {
                var characteristic = service.getCharacteristic(charUuid);
                if (characteristic != null) {
                    return characteristic;
                }
            }
        }
        return null;
    }
}
```

### 4.5 메모리 최적화 ✅

**적용 사항**:
1. **디버그 로깅 분리**:
```monkey-c
(:debug)
function log(message) {
    System.println("[ILens] " + message);
}

(:release)
function log(message) {
    // 릴리스에서는 제거
}
```

2. **문자열 상수화**:
```monkey-c
module Constants {
    const SERVICE_UUID = "4b329cf2-ace2-4a8a-9d49-38d7ab674867";
    const CHAR_UUID = "c259c1bd-e5fa-4fab-aabe-015c9ab26cd3";
}
```

3. **배열 크기 고정**:
```monkey-c
// 나쁜 예: 동적 할당
var buffer = [];
buffer.add(value1);
buffer.add(value2);

// 좋은 예: 고정 크기
var buffer = new [16]b;  // 16 바이트 고정
buffer[0] = value1;
buffer[1] = value2;
```

---

## 5. 기술적 교훈

### 5.1 Connect IQ SDK 제약사항

1. **메모리 제약**:
   - fenix7: 가장 제한적 (정확한 수치 미공개)
   - 모든 바이트가 중요 - 효율적인 코드 필수
   - 동적 할당 최소화, 전역 변수 제한

2. **BLE 제약**:
   - 프로필 등록 수 제한 → 순차 등록 필요
   - 스캔 상태 관리 복잡 → `fixScanState()` 필요
   - 연결 안정성 → 재시도 로직 필수

3. **SDK 버전**:
   - 최소 SDK 3.1.0 (BLE Central 지원)
   - RunVision-IQ: 최소 SDK 4.0.0 권장 (최신 기능)

### 5.2 BLE Central 구현 Best Practices

1. **싱글톤 패턴**: BLE Manager는 앱 전체에서 단일 인스턴스
2. **프로필 순차 등록**: 메모리 제약으로 한 번에 하나씩
3. **스캔 필터링**: Service UUID 또는 제조사 ID로 필터
4. **재시도 로직**: 특성값 읽기는 실패 가능 (5회 재시도)
5. **상태 관리**: 연결 상태를 명확히 추적 (IDLE, SCANNING, CONNECTING, CONNECTED)
6. **에러 처리**: 모든 BLE 콜백에서 에러 처리 필수

### 5.3 DataField vs Activity App 선택 가이드

**DataField를 선택해야 하는 경우**:
- ✅ 기존 Garmin 운동 앱 보조 도구
- ✅ 활동 기록은 Garmin 네이티브에 맡김
- ✅ 간단한 메트릭 표시만 필요
- ✅ 개발 리소스 절약 (ActivityRecording 불필요)

**Activity App을 선택해야 하는 경우** (RunVision-IQ):
- ✅ 독립적인 운동 앱 필요
- ✅ 자체 FIT 파일 생성 및 관리
- ✅ 전체 화면 UI 제어
- ✅ 복잡한 세션 관리 로직
- ✅ 사용자 경험 완전 제어

**RunVision-IQ는 Activity App이 적합합니다.**

---

## 6. RunVision-IQ 목표 재정의

### 6.1 프로젝트 정체성

**기존 정의** (모호):
> "Garmin 워치에서 러닝 데이터를 수집하여 iLens로 전송하는 앱"

**재정의** (명확):
> **RunVision-IQ는 Garmin Connect IQ 기반 독립 러닝 앱으로, 워치의 GPS 및 센서 데이터를 수집하고, iLens AR 글래스에 실시간 디스플레이하며, ActivityRecording API를 통해 Garmin Connect에 자동 저장하는 완전한 Activity App입니다.**

### 6.2 핵심 차별점

| 항목 | ActiveLook (참조) | RunVision-IQ (우리) |
|------|-------------------|---------------------|
| **앱 유형** | DataField (플러그인) | **Activity App (독립 앱)** |
| **GPS 관리** | 호스트 앱 의존 | **Position API 직접 관리** |
| **FIT 파일** | 호스트 앱 생성 | **ActivityRecording 직접 생성** |
| **UI** | 데이터 필드 영역 | **전체 화면 제어** |
| **세션 관리** | 호스트 앱 | **자체 Timer + SessionManager** |
| **iLens 연결** | BLE Central | **BLE Central (동일 패턴)** |
| **Garmin Connect** | 호스트 앱 업로드 | **ActivityRecording 자동 업로드** |

### 6.3 기술 스택 확정

**1. BLE Central 구현**:
- ✅ `BluetoothLowEnergy.BleDelegate` 상속
- ✅ 싱글톤 패턴 (`ILens.getBleManager()`)
- ✅ 프로필 순차 등록 (1개만)
- ✅ 재시도 로직 (5회)

**2. 데이터 수집**:
- ✅ `Timer.start(method(:onTimer), 1000, true)` (1Hz)
- ✅ `Position.getInfo()` (GPS)
- ✅ `Sensor.getInfo()` (HRM, Cadence)

**3. 활동 기록**:
- ✅ `ActivityRecording.fit()` (FIT 생성)
- ✅ `Session.start()`, `Session.save()` (세션 관리)

**4. 메모리 최적화**:
- ✅ 디버그 로깅 분리 (`(:debug)`, `(:release)`)
- ✅ 문자열 상수화
- ✅ 배열 크기 고정

### 6.4 필수 권한 (manifest.xml)

**ActiveLook에서 확인된 필수 권한**:
```xml
<iq:permissions>
    <iq:uses-permission id="BluetoothLowEnergy"/>
    <iq:uses-permission id="UserProfile"/>
    <iq:uses-permission id="Positioning"/>  <!-- GPS -->
    <iq:uses-permission id="Sensor"/>       <!-- HRM, Cadence -->
    <iq:uses-permission id="FitContributor"/> <!-- FIT 파일 -->
</iq:permissions>
```

**최소 SDK 버전**:
```xml
<iq:application minSdkVersion="4.0.0">
```

### 6.5 지원 기기 우선순위

**Tier 1 (우선 지원)**:
- Forerunner 265, 265s (최신, BLE Central 지원)
- Forerunner 955, 965 (고급 러너용)

**Tier 2 (추가 지원)**:
- Fenix 7, 7s, 7x (아웃도어)
- Epix 2, 2 Pro (프리미엄)

**제외 기기**:
- Edge 시리즈 (사이클링 전용)
- Venu 시리즈 (피트니스, BLE Central 미지원 가능)

### 6.6 개발 우선순위

**Phase 1: 핵심 기능 (Week 1-4)**
1. ✅ BLE Manager 구현 (싱글톤, 프로필 등록)
2. ✅ 스캔 및 연결 (iLens 필터링)
3. ✅ GPS + Sensor 데이터 수집 (1Hz Timer)
4. ✅ iLens 데이터 전송 (16-byte payload)
5. ✅ 기본 UI (4-field 레이아웃)

**Phase 2: 활동 기록 (Week 5-6)**
1. ✅ ActivityRecording 통합
2. ✅ SessionManager (start/stop/pause)
3. ✅ FIT 파일 생성
4. ✅ Garmin Connect 업로드 테스트

**Phase 3: 최적화 (Week 7-8)**
1. ✅ 메모리 최적화 (디버그 로깅 제거)
2. ✅ 배터리 최적화
3. ✅ 에러 처리 강화
4. ✅ 실기기 테스트 (Forerunner 265)

### 6.7 성공 기준

**기능적 성공 기준**:
- ✅ iLens BLE 연결 성공률 ≥95%
- ✅ GPS 정확도 ≤50m (실외)
- ✅ 데이터 전송 지연 ≤100ms
- ✅ FIT 파일 Garmin Connect 호환성 100%

**비기능적 성공 기준**:
- ✅ 메모리 사용량 ≤70% (fenix7 기준)
- ✅ 배터리 소모 ≤10%/hour (GPS + BLE)
- ✅ 앱 실행 시간 ≤3초

---

## 7. 문서 보완 계획

### 7.1 System-Architecture.md 보완

**추가 섹션**:
- BLE Manager 싱글톤 패턴 다이어그램
- 프로필 순차 등록 시퀀스 다이어그램
- 메모리 최적화 전략

### 7.2 Module-Design.md 보완

**추가 섹션**:
- `ILensBleManager` 클래스 상세 (재시도 로직 포함)
- `tryGetServiceCharacteristic()` 메서드
- 디버그/릴리스 로깅 분기

### 7.3 새 문서 추가

**1. Technical-Decisions.md**:
- Activity App vs DataField 선택 근거
- BLE Central 구현 패턴 근거
- 메모리 최적화 전략

**2. Memory-Optimization-Guide.md**:
- Connect IQ 메모리 제약 상세
- 최적화 기법 (문자열, 배열, 로깅)
- 프로파일링 방법

**3. manifest.xml 템플릿**:
- 필수 권한 목록
- 지원 기기 목록
- 최소 SDK 버전

---

## 8. 결론

### 8.1 핵심 교훈

1. **ActiveLook은 DataField, RunVision-IQ는 Activity App**
   - DataField: 기존 앱 보조 도구
   - Activity App: 독립 실행 완전한 앱

2. **BLE Central 구현 패턴은 동일 적용 가능**
   - 싱글톤 패턴
   - 프로필 순차 등록
   - 재시도 로직

3. **메모리 최적화가 생존의 핵심**
   - fenix7이 가장 제한적
   - 디버그 로깅 분리 필수
   - 배열 크기 고정

### 8.2 다음 단계

1. ✅ System-Architecture.md 보완 (BLE Manager 싱글톤)
2. ✅ Module-Design.md 보완 (ILensBleManager 상세)
3. ✅ Technical-Decisions.md 작성
4. ✅ manifest.xml 템플릿 작성
5. ✅ Memory-Optimization-Guide.md 작성

---

**문서 작성**: 2025-11-15
**다음 업데이트**: System-Architecture.md, Module-Design.md 보완
**승인 상태**: 승인 대기 중

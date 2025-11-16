# ActiveLook 코드 상세 분석

**문서 버전**: v1.0
**작성일**: 2025-11-15
**작성자**: Claude (AI Assistant)
**참조**: https://github.com/ActiveLook/Garmin-Datafield-sample-code
**목적**: RunVision-IQ 개발을 위한 ActiveLook 코드 패턴 분석

---

## 📋 목차

1. [전체 아키텍처](#1-전체-아키텍처)
2. [BLE Manager 패턴](#2-ble-manager-패턴)
3. [DataField 생명주기](#3-datafield-생명주기)
4. [데이터 수집 및 처리](#4-데이터-수집-및-처리)
5. [RunVision-IQ 적용 방안](#5-runvision-iq-적용-방안)

---

## 1. 전체 아키텍처

### 1.1 파일 구조

```
source/
├── ActiveLookDataFieldView.mc    # DataField 메인 (compute, onUpdate)
├── ActiveLookBLE.mc               # BLE Manager (싱글톤)
├── ActiveLookSDK_next.mc          # ActiveLook 프로토콜 레이어
├── ActiveLookActivityInfo.mc      # Activity.Info 데이터 처리
├── Laps.mc                        # 랩 데이터 관리
└── Layouts/                       # UI 레이아웃

resources/
├── properties.xml                 # Settings 정의
└── drawables/                     # 이미지 리소스
```

### 1.2 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────┐
│         ActiveLookDataFieldView                      │
│  (WatchUi.DataField extends)                        │
├─────────────────────────────────────────────────────┤
│  - initialize()                                     │
│  - compute(info)           ← Garmin OS 자동 호출    │
│  - onUpdate(dc)                                     │
│  - onTimerStart/Pause/Resume/Stop/Lap               │
└──────────────┬──────────────────────────────────────┘
               │
               ├─→ ActiveLook.getBle() (싱글톤)
               │   └─→ ActiveLookBLE
               │       ├─ setUp() (프로필 등록)
               │       ├─ requestScanning()
               │       ├─ connect()
               │       └─ onConnectedStateChanged()
               │
               ├─→ AugmentedActivityInfo
               │   ├─ accumulate(info)  ← 시계열 데이터 누적
               │   └─ compute(info)      ← 통계 계산
               │
               └─→ ActiveLookSDK
                   ├─ commandBuffer()
                   ├─ text()             ← ActiveLook 프로토콜
                   └─ sendCommandBuffer()
```

---

## 2. BLE Manager 패턴

### 2.1 싱글톤 패턴

**ActiveLookBLE.mc**:
```monkey-c
module ActiveLook {
    var ble = null;

    function getBle() {
        if (ble == null) {
            ble = new ActiveLookBLE();
        }
        return ble;
    }
}

// 사용
var ble = ActiveLook.getBle();
ble.requestScanning();
```

**장점**:
- ✅ 앱 전체에서 단일 BLE 인스턴스
- ✅ 메모리 효율적
- ✅ 상태 일관성 유지

### 2.2 프로필 순차 등록

```monkey-c
class ActiveLookBLE extends BluetoothLowEnergy.BleDelegate {

    private var _profilesRegistered = false;
    private var _profileRegisterCount = 0;

    const PRIMARY_SERVICE_UUID = "...";
    const DEVICE_INFO_UUID = "180A";
    const BATTERY_UUID = "180F";

    function setUp() {
        if (_profilesRegistered) { return; }

        // 1번째: Primary Service
        BluetoothLowEnergy.registerProfile(self, PRIMARY_SERVICE_UUID);
    }

    function onProfileRegister(uuid, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileRegisterCount++;

            if (uuid.equals(PRIMARY_SERVICE_UUID)) {
                // 2번째: Device Info
                BluetoothLowEnergy.registerProfile(self, DEVICE_INFO_UUID);
            } else if (uuid.equals(DEVICE_INFO_UUID)) {
                // 3번째: Battery
                BluetoothLowEnergy.registerProfile(self, BATTERY_UUID);
            } else if (uuid.equals(BATTERY_UUID)) {
                _profilesRegistered = true;
            }
        }
    }
}
```

**이유**: "registration can fail if too many profiles are registered" → 메모리 제약

**RunVision-IQ 적용**:
```monkey-c
// 우리는 프로필 1개만 필요
function setUp() {
    if (_profileRegistered) { return; }
    BluetoothLowEnergy.registerProfile(self, ILENS_SERVICE_UUID);
}

function onProfileRegister(uuid, status) {
    if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
        _profileRegistered = true;
    }
}
```

### 2.3 스캔 및 연결

```monkey-c
class ActiveLookBLE {

    function requestScanning() {
        if (!_profilesRegistered) {
            setUp();
            return;
        }

        BluetoothLowEnergy.setScanState(
            BluetoothLowEnergy.SCAN_STATE_SCANNING
        );
    }

    function onScanResults(scanResults) {
        for (var i = 0; i < scanResults.size(); i++) {
            var result = scanResults[i];

            // 제조사 데이터 필터링 (0x08F2 = Microoled)
            var manufacturerData = result.getManufacturerSpecificData(0x08F2);
            if (manufacturerData != null) {
                _foundDevices.add(result);
            }
        }
    }

    function connect(device) {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);

        // 기존 연결 해제
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device);
        }

        // 새 기기 연결
        BluetoothLowEnergy.pairDevice(device);
    }

    function onConnectedStateChanged(device, state) {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _device = device;
        } else {
            _device = null;
        }
    }
}
```

### 2.4 Characteristic 읽기 (재시도 로직)

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
        if (_device == null) {
            return null;
        }

        var service = _device.getService(serviceUuid);
        if (service != null) {
            var characteristic = service.getCharacteristic(charUuid);
            if (characteristic != null) {
                return characteristic;
            }
        }

        // 짧은 대기 후 재시도
        System.println("Retry " + (i+1) + "/" + maxRetries);
    }

    return null;
}
```

**교훈**: BLE Characteristic 읽기는 실패할 수 있으므로 **재시도 로직 필수**

---

## 3. DataField 생명주기

### 3.1 DataField vs Activity App

| 항목 | DataField (ActiveLook) | Activity App |
|------|------------------------|--------------|
| **Base Class** | `WatchUi.DataField` | `WatchUi.View` |
| **실행 방식** | 호스트 앱에서 자동 호출 | 사용자가 앱 실행 |
| **데이터 수집** | `compute(info)` 자동 | `Timer` 명시적 |
| **생명주기** | initialize, compute, onUpdate | initialize, onStart, onStop |
| **Activity 기록** | 호스트 앱 담당 | `ActivityRecording` 직접 |

### 3.2 생명주기 메서드

```monkey-c
class ActiveLookDataFieldView extends WatchUi.DataField {

    // 1. 초기화 (앱 시작 시 1회)
    function initialize() {
        DataField.initialize();

        // Settings 읽기
        _ilensEnabled = Application.Properties.getValue("ilensEnabled");

        // BLE Manager 초기화
        var ble = ActiveLook.getBle();
        ble.setUp();
    }

    // 2. compute() - Garmin OS가 약 50ms마다 자동 호출
    function compute(info) {
        // 센서 데이터 누적 및 계산
        AugmentedActivityInfo.accumulate(info);
        AugmentedActivityInfo.compute(info);

        // 안경으로 데이터 전송
        if (ble.isDeviceReady()) {
            updateFields(info);
        }
    }

    // 3. onUpdate() - UI 업데이트 (약 1Hz)
    function onUpdate(dc) {
        // 화면 그리기
        dc.drawText(...);
    }

    // 4. 타이머 이벤트
    function onTimerStart() {
        sdk.sendRecordingStatus(0);  // Start
    }

    function onTimerPause() {
        sdk.sendRecordingStatus(1);  // Pause
    }

    function onTimerResume() {
        sdk.sendRecordingStatus(0);  // Resume
    }

    function onTimerStop() {
        sdk.sendRecordingStatus(2);  // Stop
    }

    function onTimerLap() {
        // 랩 데이터 전송
        Laps.onLap();
    }
}
```

### 3.3 compute() 호출 주기

**Garmin OS 관리**:
- 약 **50ms (20Hz)** 주기로 자동 호출
- 개발자가 제어할 수 없음
- GPS 활성화 시 더 자주 호출될 수 있음

**배터리 효율**:
- compute()는 빠르게 실행되어야 함 (< 10ms)
- 무거운 계산 금지
- BLE 전송 횟수 제한 필요 (1Hz 권장)

---

## 4. 데이터 수집 및 처리

### 4.1 Activity.Info 데이터 구조

**ActiveLookActivityInfo.mc 분석**:

```monkey-c
class AugmentedActivityInfo {

    private var __ai;   // Activity.Info 객체
    private var __rdd;  // RunningDynamicsData 객체

    // 누적 데이터
    private var _powerSamples;     // 최근 30개 전력값
    private var _altitudeSamples;  // 최대 20개 고도 샘플

    // 1. accumulate() - 시계열 데이터 누적
    function accumulate(info) {
        __ai = info;

        // 전력 데이터 누적 (최근 30개 유지)
        var power = info.currentPower;
        if (power != null) {
            _powerSamples.add(power);
            if (_powerSamples.size() > 30) {
                _powerSamples.remove(0);
            }

            // 6개 이상 수집 시 3초 평균전력 계산
            if (_powerSamples.size() >= 6) {
                _threesecondPower = calculate3sPower(_powerSamples);
            }

            // 정규화전력 계산 (4차 함수)
            _normalizedPower = calculateNormalizedPower(_powerSamples);
        }

        // 고도 데이터 누적 (최대 20개)
        var totalAscent = info.totalAscent;
        if (totalAscent != null) {
            _altitudeSamples.add(totalAscent);
            if (_altitudeSamples.size() > 20) {
                _altitudeSamples.remove(0);
            }

            // 평균 상승속도 계산
            _averageAscentRate = calculateAscentRate(_altitudeSamples);
        }
    }

    // 2. compute() - 통계 계산
    function compute(info) {
        // 시간 변환 (ms → [h, m, s, ms])
        _timerTimeArray = convertTime(info.timerTime);

        // 속도 → 페이스 역산
        if (info.currentSpeed != null && info.currentSpeed > 0) {
            _currentPace = 1.0 / info.currentSpeed;
        }

        if (info.maxSpeed != null && info.maxSpeed > 0) {
            _fastestPace = 1.0 / info.maxSpeed;
        }

        if (info.averageSpeed != null && info.averageSpeed > 0) {
            _averagePace = 1.0 / info.averageSpeed;
        }

        // 러닝 동역학 평균
        computeRunningDynamics();

        // 심박수 영역 판정
        computeHeartRateZone(info.currentHeartRate);
    }

    // 3. get() - 다층 접근
    function get(key) {
        // 1순위: 자체 계산 필드
        if (self has key) {
            return self[key];
        }

        // 2순위: Activity.Info 필드
        if (__ai != null && __ai has key) {
            return __ai[key];
        }

        // 3순위: RunningDynamicsData 필드
        if (__rdd != null && __rdd has key) {
            return __rdd[key];
        }

        return null;
    }
}
```

### 4.2 null 안전성

**모든 계산 전 null 체크 필수**:

```monkey-c
function compute(info) {
    // ✅ 올바른 방법
    var speed = info.currentSpeed;
    if (speed != null && speed > 0) {
        var pace = 1.0 / speed;
    }

    // ❌ 잘못된 방법
    var pace = 1.0 / info.currentSpeed;  // NullPointerException 위험!
}
```

**RunVision-IQ 적용**:
```monkey-c
function sendDataToILens(info) {
    // null 체크 + 기본값 제공
    var speed = (info.currentSpeed != null) ?
                (info.currentSpeed * 3.6).toNumber() : 0;

    var distance = (info.elapsedDistance != null) ?
                   info.elapsedDistance.toNumber() : 0;

    var heartRate = (info.currentHeartRate != null) ?
                    info.currentHeartRate.toNumber() : 0;

    var cadence = (info.currentCadence != null) ?
                  info.currentCadence.toNumber() : 0;

    ble.sendMetrics(speed, distance, heartRate, cadence);
}
```

### 4.3 단위 변환

**Activity.Info 기본 단위**:
- `currentSpeed`: m/s
- `elapsedDistance`: m
- `currentHeartRate`: bpm (이미 정수)
- `currentCadence`: spm (이미 정수)

**iLens 요구 단위**:
- 속도: km/h
- 거리: meters
- 심박수: bpm
- 케이던스: spm

**변환 코드**:
```monkey-c
// 속도: m/s → km/h
var speedKmh = currentSpeed * 3.6;

// 거리: m (변환 불필요)
var distanceMeters = elapsedDistance;

// 심박수: bpm (변환 불필요)
var heartRate = currentHeartRate;

// 케이던스: spm (변환 불필요)
var cadence = currentCadence;
```

---

## 5. RunVision-IQ 적용 방안

### 5.1 간소화된 구조

ActiveLook은 **복잡한 통계 계산** (3초 전력, 정규화 전력, 평균 상승속도 등)을 수행하지만,
RunVision-IQ는 **실시간 데이터만 전송**하므로 훨씬 간단합니다.

**불필요한 것**:
- ❌ accumulate() (시계열 데이터 누적)
- ❌ 복잡한 통계 계산 (3초 전력, 정규화 전력 등)
- ❌ 러닝 동역학 평균
- ❌ 심박수 영역 판정

**필요한 것**:
- ✅ compute(info) 메서드
- ✅ Activity.Info에서 데이터 추출
- ✅ null 체크 및 단위 변환
- ✅ iLens BLE 전송

### 5.2 RunVision-IQ DataField 구조

```monkey-c
class RunVisionIQView extends WatchUi.DataField {

    private var _ilensEnabled = false;
    private var _autoDisabled = false;
    private var _scanAttempts = 0;
    private var _lastSendTime = 0;

    const SEND_INTERVAL_MS = 1000; // 1Hz

    function initialize() {
        DataField.initialize();

        // Settings 읽기
        _ilensEnabled = Application.Properties.getValue("ilensEnabled");

        // BLE Manager 초기화
        var ble = ILens.getBleManager();
        ble.setUp();
    }

    function compute(info) {
        // 1. 기능 비활성화 시 스킵
        if (!_ilensEnabled || _autoDisabled) {
            return;
        }

        // 2. 전송 주기 제한 (1Hz)
        var now = System.getTimer();
        if (now - _lastSendTime < SEND_INTERVAL_MS) {
            return;
        }

        // 3. BLE Manager 얻기
        var ble = ILens.getBleManager();

        // 4. 연결되어 있으면 데이터 전송
        if (ble.isConnected()) {
            sendDataToILens(info);
            _lastSendTime = now;
        } else {
            // 5. 연결 안 되어 있으면 스캔 시도 (최대 3회)
            if (_scanAttempts < 3) {
                if (!ble.isScanning()) {
                    ble.requestScanning();
                    _scanAttempts++;
                }
            } else {
                _autoDisabled = true;
            }
        }
    }

    function sendDataToILens(info) {
        var ble = ILens.getBleManager();

        // null 체크 + 단위 변환
        var speed = (info.currentSpeed != null) ?
                    (info.currentSpeed * 3.6).toNumber() : 0;

        var distance = (info.elapsedDistance != null) ?
                       info.elapsedDistance.toNumber() : 0;

        var heartRate = (info.currentHeartRate != null) ?
                        info.currentHeartRate.toNumber() : 0;

        var cadence = (info.currentCadence != null) ?
                      info.currentCadence.toNumber() : 0;

        // iLens로 전송
        ble.sendMetrics(speed, distance, heartRate, cadence);
    }

    function onTimerStart() {
        var ble = ILens.getBleManager();
        ble.sendMetric(0x01, 0); // Record Status: Start
    }

    function onTimerPause() {
        var ble = ILens.getBleManager();
        ble.sendMetric(0x01, 1); // Record Status: Pause
    }

    function onTimerResume() {
        var ble = ILens.getBleManager();
        ble.sendMetric(0x01, 0); // Record Status: Resume
    }

    function onTimerStop() {
        var ble = ILens.getBleManager();
        ble.sendMetric(0x01, 2); // Record Status: Stop
    }

    function onUpdate(dc) {
        // 기본 UI 표시 (선택사항)
        View.onUpdate(dc);

        if (_ilensEnabled && !_autoDisabled) {
            dc.drawText(dc.getWidth()/2, dc.getHeight()/2,
                        Graphics.FONT_SMALL,
                        "iLens: " + (ble.isConnected() ? "Connected" : "Scanning"),
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
```

### 5.3 ActiveLook vs RunVision-IQ 비교

| 항목 | ActiveLook | RunVision-IQ |
|------|-----------|--------------|
| **데이터 누적** | ✅ accumulate() 30개 전력, 20개 고도 | ❌ 불필요 (실시간만) |
| **통계 계산** | ✅ 3초 전력, 정규화 전력, 평균 상승속도 | ❌ 불필요 |
| **러닝 동역학** | ✅ 평균 지면접촉시간, 수직진폭 | ❌ 불필요 |
| **심박수 영역** | ✅ 6단계 영역 판정 | ❌ 불필요 |
| **BLE 프로필** | ✅ 3개 (Primary, DeviceInfo, Battery) | ✅ 1개 (Exercise Data) |
| **BLE 프로토콜** | ✅ ActiveLook (메트릭 ID 기반) | ✅ iLens (UINT32 기반) |
| **전송 빈도** | ✅ 매 compute() (20Hz) | ✅ 1Hz (제한) |
| **코드 복잡도** | ⭐⭐⭐⭐⭐ 매우 복잡 | ⭐⭐ 간단 |

---

## 6. Settings 구조

### 6.1 Properties 정의

**properties.xml** (예상 구조):
```xml
<properties>
    <property id="ilensEnabled" type="boolean">
        <default>false</default>
    </property>

    <property id="glassesName" type="string">
        <default></default>
    </property>

    <property id="autoConnect" type="boolean">
        <default>true</default>
    </property>

    <property id="transmitRate" type="number">
        <default>1</default> <!-- 1Hz -->
    </property>
</properties>
```

### 6.2 Settings 읽기

```monkey-c
function initialize() {
    DataField.initialize();

    // Settings 읽기
    _ilensEnabled = Application.Properties.getValue("ilensEnabled");
    _glassesName = Application.Properties.getValue("glassesName");
    _autoConnect = Application.Properties.getValue("autoConnect");
    _transmitRate = Application.Properties.getValue("transmitRate");
}
```

### 6.3 Settings 쓰기

```monkey-c
function setILensEnabled(enabled) {
    _ilensEnabled = enabled;
    Application.Properties.setValue("ilensEnabled", enabled);
}
```

---

## 7. 메모리 최적화

### 7.1 디버그 로깅 분리

```monkey-c
(:debug)
function log(message) {
    System.println("[RunVisionIQ] " + message);
}

(:release)
function log(message) {
    // 릴리스 빌드에서는 제거
}
```

### 7.2 문자열 상수화

```monkey-c
module Constants {
    const SERVICE_UUID_STRING = "4b329cf2-3816-498c-8453-ee8798502a08";
    const CHAR_UUID_STRING = "c259c1bd-18d3-c348-b88d-5447aea1b615";
}

// 사용
var serviceUuid = BluetoothLowEnergy.stringToUuid(
    Constants.SERVICE_UUID_STRING
);
```

### 7.3 배열 크기 고정

```monkey-c
// ❌ 나쁜 예: 동적 할당
var buffer = [];
buffer.add(value1);
buffer.add(value2);

// ✅ 좋은 예: 고정 크기
var buffer = new [5]b;  // 5 bytes 고정
buffer[0] = metricId;
buffer[1] = (value & 0xFF);
buffer[2] = ((value >> 8) & 0xFF);
buffer[3] = ((value >> 16) & 0xFF);
buffer[4] = ((value >> 24) & 0xFF);
```

---

## 8. 정리

### 8.1 ActiveLook에서 배운 핵심 패턴

1. **BLE Manager 싱글톤**: 앱 전체에서 단일 인스턴스
2. **프로필 순차 등록**: 메모리 제약 대응 (우리는 1개만)
3. **재시도 로직**: Characteristic 읽기 5회 재시도
4. **compute() 자동 호출**: 약 50ms 주기, 빠르게 실행 필수
5. **null 안전성**: 모든 Activity.Info 접근 시 null 체크
6. **단위 변환**: m/s → km/h, m → meters
7. **전송 주기 제한**: 배터리 효율을 위해 1Hz 권장
8. **자동 연결 관리**: 3회 실패 시 자동 비활성화
9. **Settings 통합**: Garmin Connect Mobile 앱에서 제어
10. **메모리 최적화**: 디버그 로깅 분리, 문자열 상수화, 배열 고정

### 8.2 RunVision-IQ에 적용

**재사용 (90%)**:
- ✅ BLE Manager 구조 (싱글톤, 프로필 등록)
- ✅ 스캔 및 연결 로직
- ✅ Characteristic 재시도 로직
- ✅ compute() 메서드 구조
- ✅ onTimer* 이벤트 핸들러
- ✅ Settings 구조

**교체 (10%)**:
- 🔄 ActiveLook 프로토콜 → iLens 프로토콜
- 🔄 복잡한 통계 계산 → 간단한 실시간 전송
- 🔄 3개 프로필 → 1개 프로필

---

**문서 작성**: 2025-11-15
**다음 단계**: DataField 아키텍처 설계, ILensBLE 클래스 상세 설계
**승인 상태**: 승인 대기 중

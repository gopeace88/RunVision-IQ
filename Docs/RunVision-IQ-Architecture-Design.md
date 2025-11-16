# RunVision-IQ 아키텍처 상세 설계

**문서 버전**: v1.0
**작성일**: 2025-11-15
**작성자**: Claude (AI Assistant)
**프로젝트**: RunVision-IQ (Garmin Connect IQ DataField)
**목적**: 구현 가능한 수준의 완전한 아키텍처 명세

---

## 📋 목차

1. [전체 아키텍처 개요](#1-전체-아키텍처-개요)
2. [모듈 구조 및 책임](#2-모듈-구조-및-책임)
3. [ILensBLE 클래스 상세 설계](#3-ilensble-클래스-상세-설계)
4. [RunVisionIQView 클래스 상세 설계](#4-runvisioniqview-클래스-상세-설계)
5. [compute() 메서드 상세](#5-compute-메서드-상세)
6. [자동연결관리 로직](#6-자동연결관리-로직)
7. [Settings 구조](#7-settings-구조)
8. [시퀀스 다이어그램](#8-시퀀스-다이어그램)
9. [상태 머신](#9-상태-머신)
10. [에러 처리](#10-에러-처리)
11. [메모리 최적화](#11-메모리-최적화)
12. [성능 고려사항](#12-성능-고려사항)

---

## 1. 전체 아키텍처 개요

### 1.1 시스템 컨텍스트

```
┌────────────────────────────────────────────────────┐
│              Garmin Watch                          │
│  ┌──────────────────────────────────────────────┐ │
│  │   Garmin Native Run App (Host)               │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │   RunVision-IQ DataField               │  │ │
│  │  │  ┌──────────────────────────────────┐  │  │ │
│  │  │  │  RunVisionIQView                 │  │  │ │
│  │  │  │  - compute(info) [50ms 주기]    │  │  │ │
│  │  │  │  - onTimer* events               │  │  │ │
│  │  │  └─────────┬────────────────────────┘  │  │ │
│  │  │            │                            │  │ │
│  │  │            ├→ ILens.getBleManager()    │  │ │
│  │  │            │  └→ ILensBLE (싱글톤)    │  │ │
│  │  │            │     - BLE Central          │  │ │
│  │  │            │     - Protocol Encoding    │  │ │
│  │  │            │                            │  │ │
│  │  │            └→ Settings                  │  │ │
│  │  │               - ilensEnabled            │  │ │
│  │  │               - autoConnect             │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────┘ │
│                                                    │
│         Position API      Sensor API              │
│         (GPS)             (HRM, Cadence)          │
└────────────┬──────────────────────┬────────────────┘
             │                      │
             ↓                      ↓
      Activity.Info 객체 (Garmin OS가 제공)
             ↓
      RunVisionIQView.compute(info)
             ↓
      데이터 추출 + 단위 변환
             ↓
      ILensBLE.sendMetrics()
             ↓ BLE
    ┌────────────────┐
    │  iLens 안경    │
    └────────────────┘
```

### 1.2 핵심 설계 원칙

1. **간결함 (Simplicity)**
   - ActiveLook의 복잡한 통계 계산 제거
   - 실시간 데이터 전송만 구현
   - 코드 라인 수 최소화

2. **효율성 (Efficiency)**
   - BLE 전송 1Hz로 제한 (배터리 절약)
   - 자동 스캔 3회로 제한
   - 메모리 사용 최소화

3. **견고성 (Robustness)**
   - null 안전성 (모든 Activity.Info 접근)
   - BLE 재시도 로직 (5회)
   - 자동 비활성화 (연결 실패 시)

4. **사용성 (Usability)**
   - Garmin Connect Mobile 앱에서 ON/OFF
   - 자동 연결 관리
   - 명확한 연결 상태 표시

---

## 2. 모듈 구조 및 책임

### 2.1 모듈 다이어그램

```
RunVision-IQ
├── RunVisionIQApp.mc              # Application Entry Point
│   └─ getInitialView()            # DataField View 생성
│
├── RunVisionIQView.mc             # DataField View (Main)
│   ├─ initialize()                # 초기화 (Settings, BLE)
│   ├─ compute(info)               # 데이터 수집 및 전송 (50ms)
│   ├─ onUpdate(dc)                # UI 업데이트 (1Hz)
│   ├─ onTimerStart/Pause/Resume/Stop/Lap
│   └─ sendDataToILens(info)       # iLens 데이터 전송
│
├── ILens.mc                       # BLE Manager Module (싱글톤)
│   ├─ getBleManager()             # 싱글톤 인스턴스 반환
│   └─ ILensBLE                    # BLE Manager 클래스
│       ├─ setUp()                 # 프로필 등록
│       ├─ requestScanning()       # BLE 스캔 시작
│       ├─ connect(device)         # BLE 연결
│       ├─ sendMetrics(...)        # 4개 메트릭 전송
│       ├─ sendMetric(id, value)   # 개별 메트릭 전송
│       └─ encodeUInt32LE(value)   # Little-Endian 인코딩
│
├── Constants.mc                   # 상수 정의
│   ├─ SERVICE_UUID                # iLens Service UUID
│   ├─ CHARACTERISTIC_UUID         # Exercise Data Char UUID
│   └─ METRIC_IDS                  # 메트릭 ID (0x06, 0x07, ...)
│
└── properties.xml                 # Settings 정의
    ├─ ilensEnabled (boolean)
    ├─ autoConnect (boolean)
    └─ transmitRate (number)
```

### 2.2 책임 분담

| 모듈 | 책임 | 주요 메서드 |
|------|------|------------|
| **RunVisionIQApp** | 앱 진입점, DataField View 생성 | getInitialView() |
| **RunVisionIQView** | 데이터 수집, UI 업데이트, BLE 전송 제어 | compute(), onUpdate(), sendDataToILens() |
| **ILensBLE** | BLE 연결, 스캔, 데이터 전송, 프로토콜 인코딩 | setUp(), sendMetrics(), encodeUInt32LE() |
| **Constants** | UUID, 메트릭 ID 등 상수 관리 | (static values) |
| **properties.xml** | 사용자 설정 정의 | (XML) |

---

## 3. ILensBLE 클래스 상세 설계

### 3.1 클래스 다이어그램

```monkey-c
module ILens {
    var bleManager = null;

    function getBleManager() {
        if (bleManager == null) {
            bleManager = new ILensBLE();
        }
        return bleManager;
    }
}

class ILensBLE extends BluetoothLowEnergy.BleDelegate {

    // ──────────────────────────────────────────────────
    // Constants
    // ──────────────────────────────────────────────────
    const SERVICE_UUID_STRING = "4b329cf2-3816-498c-8453-ee8798502a08";
    const EXERCISE_CHAR_UUID_STRING = "c259c1bd-18d3-c348-b88d-5447aea1b615";

    // 메트릭 ID
    const METRIC_ID_DISTANCE = 0x06;
    const METRIC_ID_VELOCITY = 0x07;
    const METRIC_ID_HEART_RATE = 0x0B;
    const METRIC_ID_CADENCE = 0x0E;
    const METRIC_ID_RECORD_STATUS = 0x01;

    // ──────────────────────────────────────────────────
    // Private Fields
    // ──────────────────────────────────────────────────
    private var _serviceUuid = null;
    private var _exerciseCharUuid = null;

    private var _profileRegistered = false;
    private var _device = null;
    private var _exerciseCharacteristic = null;
    private var _scanState = SCAN_STATE_IDLE;
    private var _connectionState = CONNECTION_STATE_DISCONNECTED;

    // ──────────────────────────────────────────────────
    // Public Methods
    // ──────────────────────────────────────────────────

    function initialize() {
        BleDelegate.initialize();

        // UUID 변환
        _serviceUuid = BluetoothLowEnergy.stringToUuid(SERVICE_UUID_STRING);
        _exerciseCharUuid = BluetoothLowEnergy.stringToUuid(EXERCISE_CHAR_UUID_STRING);
    }

    function setUp() {
        if (_profileRegistered) { return; }

        log("Registering BLE profile...");
        BluetoothLowEnergy.registerProfile(self, _serviceUuid);
    }

    function requestScanning() {
        if (!_profileRegistered) {
            log("Profile not registered, calling setUp()");
            setUp();
            return;
        }

        if (_scanState == SCAN_STATE_SCANNING) {
            log("Already scanning");
            return;
        }

        log("Starting BLE scan...");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        _scanState = SCAN_STATE_SCANNING;
    }

    function stopScanning() {
        if (_scanState != SCAN_STATE_SCANNING) {
            return;
        }

        log("Stopping BLE scan");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        _scanState = SCAN_STATE_IDLE;
    }

    function connect(device) {
        log("Connecting to device: " + device.getName());

        // 스캔 중지
        stopScanning();

        // 기존 연결 해제
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device);
        }

        // 새 기기 연결
        BluetoothLowEnergy.pairDevice(device);
    }

    function disconnect() {
        if (_device != null) {
            log("Disconnecting from device");
            BluetoothLowEnergy.unpairDevice(_device);
            _device = null;
            _exerciseCharacteristic = null;
            _connectionState = CONNECTION_STATE_DISCONNECTED;
        }
    }

    function sendMetrics(speed, distance, heartRate, cadence) {
        if (!isConnected()) {
            log("Not connected, skip sending");
            return false;
        }

        // 각 메트릭 개별 전송
        sendMetric(METRIC_ID_VELOCITY, speed);
        sendMetric(METRIC_ID_DISTANCE, distance);
        sendMetric(METRIC_ID_HEART_RATE, heartRate);
        sendMetric(METRIC_ID_CADENCE, cadence);

        return true;
    }

    function sendMetric(metricId, value) {
        if (_exerciseCharacteristic == null) {
            log("Exercise characteristic not found");
            return false;
        }

        // 페이로드 생성: [id(1)] + [UINT32(4, Little-Endian)]
        var payload = new [5]b;
        payload[0] = metricId;

        // UINT32 Little-Endian 인코딩
        var valueInt = value.toNumber();
        payload[1] = (valueInt & 0xFF);
        payload[2] = ((valueInt >> 8) & 0xFF);
        payload[3] = ((valueInt >> 16) & 0xFF);
        payload[4] = ((valueInt >> 24) & 0xFF);

        // BLE 전송
        try {
            _exerciseCharacteristic.requestWrite(payload, {
                :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
            });
            return true;
        } catch (e) {
            log("BLE write failed: " + e.getErrorMessage());
            return false;
        }
    }

    function isConnected() {
        return (_connectionState == CONNECTION_STATE_CONNECTED) &&
               (_device != null) &&
               (_exerciseCharacteristic != null);
    }

    function isScanning() {
        return (_scanState == SCAN_STATE_SCANNING);
    }

    // ──────────────────────────────────────────────────
    // BleDelegate Callbacks
    // ──────────────────────────────────────────────────

    function onProfileRegister(uuid, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            log("Profile registered successfully");
            _profileRegistered = true;
        } else {
            log("Profile registration failed: " + status);
        }
    }

    function onScanResults(scanResults) {
        log("Scan results: " + scanResults.size() + " devices");

        for (var i = 0; i < scanResults.size(); i++) {
            var result = scanResults[i];
            var deviceName = result.getDeviceName();

            // Device Name으로 필터링
            if (deviceName != null && deviceName.find("iLens") != null) {
                log("Found iLens device: " + deviceName);

                // 자동 연결
                connect(result);
                return;
            }
        }
    }

    function onConnectedStateChanged(device, state) {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            log("Device connected: " + device.getName());
            _device = device;
            _connectionState = CONNECTION_STATE_CONNECTED;

            // Characteristic 얻기 (재시도 로직)
            _exerciseCharacteristic = getExerciseCharacteristic();

            if (_exerciseCharacteristic == null) {
                log("Failed to get exercise characteristic");
            } else {
                log("Exercise characteristic obtained");
            }
        } else {
            log("Device disconnected");
            _device = null;
            _exerciseCharacteristic = null;
            _connectionState = CONNECTION_STATE_DISCONNECTED;
        }
    }

    // ──────────────────────────────────────────────────
    // Private Methods
    // ──────────────────────────────────────────────────

    private function getExerciseCharacteristic() {
        return tryGetCharacteristic(_serviceUuid, _exerciseCharUuid, 5);
    }

    private function tryGetCharacteristic(serviceUuid, charUuid, maxRetries) {
        for (var i = 0; i < maxRetries; i++) {
            if (_device == null) {
                return null;
            }

            var service = _device.getService(serviceUuid);
            if (service != null) {
                var characteristic = service.getCharacteristic(charUuid);
                if (characteristic != null) {
                    log("Characteristic found on retry " + (i+1));
                    return characteristic;
                }
            }

            log("Retry " + (i+1) + "/" + maxRetries);
        }

        log("Failed to get characteristic after " + maxRetries + " retries");
        return null;
    }

    private function log(message) {
        (:debug)
        System.println("[ILensBLE] " + message);
    }

    // ──────────────────────────────────────────────────
    // Constants (Scan & Connection State)
    // ──────────────────────────────────────────────────
    enum {
        SCAN_STATE_IDLE,
        SCAN_STATE_SCANNING
    }

    enum {
        CONNECTION_STATE_DISCONNECTED,
        CONNECTION_STATE_CONNECTED
    }
}
```

### 3.2 메서드 명세

#### 3.2.1 Public Methods

| 메서드 | 파라미터 | 반환 타입 | 설명 |
|--------|---------|----------|------|
| `initialize()` | - | void | UUID 변환, 초기화 |
| `setUp()` | - | void | BLE 프로필 등록 |
| `requestScanning()` | - | void | BLE 스캔 시작 (자동 setUp) |
| `stopScanning()` | - | void | BLE 스캔 중지 |
| `connect(device)` | ScanResult | void | 기기 연결 |
| `disconnect()` | - | void | 기기 연결 해제 |
| `sendMetrics(speed, distance, hr, cad)` | Float×4 | Boolean | 4개 메트릭 전송 |
| `sendMetric(id, value)` | Number, Float | Boolean | 개별 메트릭 전송 |
| `isConnected()` | - | Boolean | 연결 상태 확인 |
| `isScanning()` | - | Boolean | 스캔 상태 확인 |

#### 3.2.2 BleDelegate Callbacks

| 콜백 | 파라미터 | 설명 |
|------|---------|------|
| `onProfileRegister(uuid, status)` | Uuid, Status | 프로필 등록 결과 |
| `onScanResults(scanResults)` | Array<ScanResult> | 스캔 결과 (자동 연결) |
| `onConnectedStateChanged(device, state)` | Device, State | 연결 상태 변화 |

#### 3.2.3 Private Methods

| 메서드 | 파라미터 | 반환 타입 | 설명 |
|--------|---------|----------|------|
| `getExerciseCharacteristic()` | - | Characteristic | Exercise Char 얻기 (5회 재시도) |
| `tryGetCharacteristic(svc, char, retry)` | Uuid×2, Number | Characteristic | 재시도 로직 |
| `log(message)` | String | void | 디버그 로깅 (릴리스에서 제거) |

---

## 4. RunVisionIQView 클래스 상세 설계

### 4.1 클래스 다이어그램

```monkey-c
class RunVisionIQView extends WatchUi.DataField {

    // ──────────────────────────────────────────────────
    // Private Fields
    // ──────────────────────────────────────────────────

    // Settings
    private var _ilensEnabled = false;
    private var _autoConnect = true;
    private var _transmitRate = 1; // Hz

    // Auto-connection management
    private var _scanAttempts = 0;
    private var _maxScanAttempts = 3;
    private var _autoDisabled = false;

    // Transmission throttling
    private var _lastSendTime = 0;
    private var _sendIntervalMs = 1000; // 1Hz

    // ──────────────────────────────────────────────────
    // DataField Lifecycle
    // ──────────────────────────────────────────────────

    function initialize() {
        DataField.initialize();

        // Settings 읽기
        _ilensEnabled = Application.Properties.getValue("ilensEnabled");
        _autoConnect = Application.Properties.getValue("autoConnect");
        _transmitRate = Application.Properties.getValue("transmitRate");

        // 전송 주기 계산
        _sendIntervalMs = (1000.0 / _transmitRate).toNumber();

        // BLE Manager 초기화
        var ble = ILens.getBleManager();
        ble.initialize();
        ble.setUp();

        log("Initialized - iLens: " + _ilensEnabled + ", Auto: " + _autoConnect);
    }

    // Garmin OS가 약 50ms마다 자동 호출
    function compute(info) {
        // 1. 기능 비활성화 상태면 스킵
        if (!_ilensEnabled || _autoDisabled) {
            return;
        }

        // 2. 전송 주기 제한 (1Hz)
        var now = System.getTimer();
        if (now - _lastSendTime < _sendIntervalMs) {
            return;
        }

        // 3. BLE Manager 얻기
        var ble = ILens.getBleManager();

        // 4. 연결되어 있으면 데이터 전송
        if (ble.isConnected()) {
            sendDataToILens(info);
            _lastSendTime = now;
            _scanAttempts = 0; // 성공 시 리셋
        } else {
            // 5. 연결 안 되어 있으면 자동 연결 시도
            if (_autoConnect && _scanAttempts < _maxScanAttempts) {
                if (!ble.isScanning()) {
                    log("Auto-scan attempt " + (_scanAttempts + 1));
                    ble.requestScanning();
                    _scanAttempts++;
                }
            } else if (_scanAttempts >= _maxScanAttempts) {
                // 6. 최대 시도 횟수 초과 → 자동 비활성화
                log("Max scan attempts reached, auto-disabled");
                _autoDisabled = true;
            }
        }
    }

    function onUpdate(dc) {
        // 부모 클래스 호출 (기본 UI)
        View.onUpdate(dc);

        // iLens 상태 표시 (선택사항)
        if (_ilensEnabled && !_autoDisabled) {
            var ble = ILens.getBleManager();
            var statusText = ble.isConnected() ? "iLens: Connected" :
                            ble.isScanning() ? "iLens: Scanning..." :
                            "iLens: Disconnected";

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() - 30,
                Graphics.FONT_TINY,
                statusText,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    // ──────────────────────────────────────────────────
    // Timer Events
    // ──────────────────────────────────────────────────

    function onTimerStart() {
        log("Timer started");

        // 세션 시작 시 자동 비활성화 해제
        _autoDisabled = false;
        _scanAttempts = 0;

        // iLens에 Record Status 전송 (Start = 0)
        var ble = ILens.getBleManager();
        if (ble.isConnected()) {
            ble.sendMetric(ble.METRIC_ID_RECORD_STATUS, 0);
        }
    }

    function onTimerPause() {
        log("Timer paused");

        // iLens에 Record Status 전송 (Pause = 1)
        var ble = ILens.getBleManager();
        if (ble.isConnected()) {
            ble.sendMetric(ble.METRIC_ID_RECORD_STATUS, 1);
        }
    }

    function onTimerResume() {
        log("Timer resumed");

        // iLens에 Record Status 전송 (Resume = 0)
        var ble = ILens.getBleManager();
        if (ble.isConnected()) {
            ble.sendMetric(ble.METRIC_ID_RECORD_STATUS, 0);
        }
    }

    function onTimerStop() {
        log("Timer stopped");

        // iLens에 Record Status 전송 (Stop = 2)
        var ble = ILens.getBleManager();
        if (ble.isConnected()) {
            ble.sendMetric(ble.METRIC_ID_RECORD_STATUS, 2);
        }

        // BLE 연결 해제 (선택사항)
        // ble.disconnect();
    }

    function onTimerLap() {
        log("Lap recorded");
        // iLens에 랩 이벤트 전송 (선택사항)
    }

    function onTimerReset() {
        log("Timer reset");

        // 자동 비활성화 해제
        _autoDisabled = false;
        _scanAttempts = 0;
    }

    // ──────────────────────────────────────────────────
    // Private Methods
    // ──────────────────────────────────────────────────

    private function sendDataToILens(info) {
        var ble = ILens.getBleManager();

        // Activity.Info에서 데이터 추출 (null 체크)
        var speed = extractSpeed(info);       // km/h
        var distance = extractDistance(info); // meters
        var heartRate = extractHeartRate(info); // bpm
        var cadence = extractCadence(info);     // spm

        // iLens로 전송
        var success = ble.sendMetrics(speed, distance, heartRate, cadence);

        if (!success) {
            log("Failed to send metrics");
        }
    }

    private function extractSpeed(info) {
        // m/s → km/h
        if (info.currentSpeed != null && info.currentSpeed > 0) {
            return (info.currentSpeed * 3.6).toNumber();
        }
        return 0;
    }

    private function extractDistance(info) {
        // meters (변환 불필요)
        if (info.elapsedDistance != null) {
            return info.elapsedDistance.toNumber();
        }
        return 0;
    }

    private function extractHeartRate(info) {
        // bpm (변환 불필요)
        if (info.currentHeartRate != null) {
            return info.currentHeartRate.toNumber();
        }
        return 0;
    }

    private function extractCadence(info) {
        // spm (변환 불필요)
        if (info.currentCadence != null) {
            return info.currentCadence.toNumber();
        }
        return 0;
    }

    private function log(message) {
        (:debug)
        System.println("[RunVisionIQView] " + message);
    }
}
```

### 4.2 메서드 명세

#### 4.2.1 Lifecycle Methods

| 메서드 | 호출 시점 | 호출 주기 | 설명 |
|--------|----------|----------|------|
| `initialize()` | DataField 생성 시 | 1회 | Settings 읽기, BLE 초기화 |
| `compute(info)` | 활동 중 | ~50ms (20Hz) | 데이터 수집 및 전송 |
| `onUpdate(dc)` | UI 업데이트 | ~1Hz | 화면 그리기 |

#### 4.2.2 Timer Event Handlers

| 메서드 | 이벤트 | 설명 |
|--------|-------|------|
| `onTimerStart()` | 타이머 시작 | Record Status = 0, 자동 비활성화 해제 |
| `onTimerPause()` | 타이머 일시정지 | Record Status = 1 |
| `onTimerResume()` | 타이머 재개 | Record Status = 0 |
| `onTimerStop()` | 타이머 종료 | Record Status = 2, (선택) 연결 해제 |
| `onTimerLap()` | 랩 기록 | (선택) 랩 이벤트 전송 |
| `onTimerReset()` | 타이머 리셋 | 자동 비활성화 해제 |

#### 4.2.3 Private Methods

| 메서드 | 파라미터 | 반환 타입 | 설명 |
|--------|---------|----------|------|
| `sendDataToILens(info)` | Activity.Info | void | iLens로 4개 메트릭 전송 |
| `extractSpeed(info)` | Activity.Info | Number | 속도 추출 (m/s → km/h) |
| `extractDistance(info)` | Activity.Info | Number | 거리 추출 (meters) |
| `extractHeartRate(info)` | Activity.Info | Number | 심박수 추출 (bpm) |
| `extractCadence(info)` | Activity.Info | Number | 케이던스 추출 (spm) |

---

## 5. compute() 메서드 상세

### 5.1 실행 흐름

```
compute(info) 호출 (Garmin OS, ~50ms 주기)
    ↓
[1] 기능 활성화 체크
    - _ilensEnabled == false? → 종료
    - _autoDisabled == true? → 종료
    ↓
[2] 전송 주기 제한 (1Hz)
    - now - _lastSendTime < 1000ms? → 종료
    ↓
[3] BLE Manager 얻기
    - ble = ILens.getBleManager()
    ↓
[4] 연결 상태 확인
    ├─ ble.isConnected() == true?
    │   ├─ sendDataToILens(info)
    │   ├─ _lastSendTime = now
    │   └─ _scanAttempts = 0
    │
    └─ ble.isConnected() == false?
        ├─ _autoConnect && _scanAttempts < 3?
        │   ├─ !ble.isScanning()?
        │   │   ├─ ble.requestScanning()
        │   │   └─ _scanAttempts++
        │   └─ (else) 대기
        │
        └─ _scanAttempts >= 3?
            └─ _autoDisabled = true
```

### 5.2 코드 예시 (주석 포함)

```monkey-c
function compute(info) {
    // ──────────────────────────────────────────────────
    // [1] 기능 활성화 체크
    // ──────────────────────────────────────────────────
    // Settings에서 iLens 기능이 OFF이거나,
    // 자동 비활성화 상태면 즉시 종료 (BLE 동작 안 함)
    if (!_ilensEnabled || _autoDisabled) {
        return;
    }

    // ──────────────────────────────────────────────────
    // [2] 전송 주기 제한 (배터리 절약)
    // ──────────────────────────────────────────────────
    // compute()는 50ms마다 호출되지만, iLens로는 1Hz만 전송
    // 마지막 전송 시간과 비교하여 1초 미만이면 스킵
    var now = System.getTimer(); // 현재 시각 (ms)
    if (now - _lastSendTime < _sendIntervalMs) {
        return; // 아직 1초 안 지남
    }

    // ──────────────────────────────────────────────────
    // [3] BLE Manager 얻기 (싱글톤)
    // ──────────────────────────────────────────────────
    var ble = ILens.getBleManager();

    // ──────────────────────────────────────────────────
    // [4] 연결 상태 확인 및 동작 분기
    // ──────────────────────────────────────────────────
    if (ble.isConnected()) {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // [4-A] 연결되어 있음 → 데이터 전송
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        sendDataToILens(info);
        _lastSendTime = now;
        _scanAttempts = 0; // 성공 시 스캔 시도 카운터 리셋
    } else {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // [4-B] 연결 안 되어 있음 → 자동 연결 관리
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // 자동 연결 ON && 최대 시도 횟수 미도달
        if (_autoConnect && _scanAttempts < _maxScanAttempts) {

            // 스캔 중이 아니면 스캔 시작
            if (!ble.isScanning()) {
                log("Auto-scan attempt " + (_scanAttempts + 1) + "/" + _maxScanAttempts);
                ble.requestScanning();
                _scanAttempts++;
            }
            // (else) 이미 스캔 중이면 대기

        } else if (_scanAttempts >= _maxScanAttempts) {
            // 최대 시도 횟수 초과 → 자동 비활성화
            log("Max scan attempts reached, auto-disabled for this session");
            _autoDisabled = true;
        }
    }
}
```

### 5.3 성능 최적화

**compute() 호출 주기**: ~50ms (20Hz)
**iLens 전송 주기**: 1000ms (1Hz)

**비율**: 20:1 → compute() 20번 호출 중 1번만 iLens 전송

**배터리 절약**:
- ✅ BLE 전송 횟수 95% 감소 (20Hz → 1Hz)
- ✅ 스캔 시도 3회로 제한
- ✅ 연결 실패 시 자동 비활성화

---

## 6. 자동연결관리 로직

### 6.1 상태 다이어그램

```
[초기 상태]
    ↓
┌──────────────────────┐
│  Settings Check      │
│  - ilensEnabled?     │
└──────┬───────────────┘
       │
       ├─ NO → [Inactive]
       │
       └─ YES
          ↓
┌──────────────────────┐
│  Auto Connect?       │
└──────┬───────────────┘
       │
       ├─ NO → [Manual Mode]
       │
       └─ YES
          ↓
┌──────────────────────┐
│  Scan Attempt 1      │
│  - requestScanning() │
└──────┬───────────────┘
       │
       ├─ Found iLens → [Connected]
       │
       └─ Not Found (5s timeout)
          ↓
┌──────────────────────┐
│  Scan Attempt 2      │
└──────┬───────────────┘
       │
       ├─ Found iLens → [Connected]
       │
       └─ Not Found
          ↓
┌──────────────────────┐
│  Scan Attempt 3      │
└──────┬───────────────┘
       │
       ├─ Found iLens → [Connected]
       │
       └─ Not Found
          ↓
┌──────────────────────┐
│  Auto-Disabled       │
│  (이번 세션만)       │
└──────────────────────┘

[Timer Reset/Start]
    ↓
  Reset _scanAttempts = 0
  Reset _autoDisabled = false
    ↓
  [다시 Scan Attempt 1부터]
```

### 6.2 자동 연결 로직 코드

```monkey-c
// 자동 연결 관리 상태
private var _scanAttempts = 0;
private var _maxScanAttempts = 3;
private var _autoDisabled = false;

// compute() 내부
if (!ble.isConnected()) {
    if (_autoConnect && _scanAttempts < _maxScanAttempts) {
        // 스캔 중이 아니면 스캔 시작
        if (!ble.isScanning()) {
            ble.requestScanning();
            _scanAttempts++;
        }
    } else if (_scanAttempts >= _maxScanAttempts) {
        // 최대 시도 횟수 초과
        _autoDisabled = true;
    }
}

// onTimerStart() 또는 onTimerReset() 시 리셋
function onTimerStart() {
    _autoDisabled = false;
    _scanAttempts = 0;
}
```

### 6.3 수동 연결 모드

Settings에서 `autoConnect = false`로 설정 시:

```monkey-c
// compute() 내부
if (!ble.isConnected()) {
    if (_autoConnect) {
        // 자동 연결 로직
    } else {
        // 수동 모드: 아무것도 안 함
        // 사용자가 Garmin Connect Mobile 앱에서 수동으로 연결
    }
}
```

---

## 7. Settings 구조

### 7.1 properties.xml

```xml
<properties>
    <!-- iLens 기능 활성화 -->
    <property id="ilensEnabled" type="boolean">
        <default>false</default>
    </property>

    <!-- 자동 연결 -->
    <property id="autoConnect" type="boolean">
        <default>true</default>
    </property>

    <!-- 전송 주기 (Hz) -->
    <property id="transmitRate" type="number">
        <default>1</default> <!-- 1Hz -->
    </property>

    <!-- (선택) 저장된 기기 이름 -->
    <property id="savedDeviceName" type="string">
        <default></default>
    </property>
</properties>
```

### 7.2 Settings UI (Garmin Connect Mobile)

**Garmin Connect Mobile 앱 → 기기 → RunVision-IQ → 설정**

```
┌─────────────────────────────────────┐
│  RunVision-IQ 설정                  │
├─────────────────────────────────────┤
│                                     │
│  [✓] iLens 사용                     │
│      iLens AR 글래스로 메트릭 전송  │
│                                     │
│  [✓] 자동 연결                      │
│      러닝 시작 시 자동으로 연결     │
│                                     │
│  전송 주기: [1] Hz                  │
│      (1-5 Hz, 기본값: 1Hz)          │
│                                     │
│  저장된 기기: iLens-5883            │
│      [기기 삭제]                     │
│                                     │
└─────────────────────────────────────┘
```

### 7.3 Settings 읽기/쓰기

```monkey-c
// 읽기 (initialize)
function initialize() {
    _ilensEnabled = Application.Properties.getValue("ilensEnabled");
    _autoConnect = Application.Properties.getValue("autoConnect");
    _transmitRate = Application.Properties.getValue("transmitRate");
}

// 쓰기 (필요 시)
function saveDeviceName(deviceName) {
    Application.Properties.setValue("savedDeviceName", deviceName);
}
```

---

## 8. 시퀀스 다이어그램

### 8.1 초기화 시퀀스

```
User            Garmin OS         RunVisionIQView      ILensBLE
  │                 │                    │                 │
  │   Run App       │                    │                 │
  │────────────────>│                    │                 │
  │                 │  initialize()      │                 │
  │                 │───────────────────>│                 │
  │                 │                    │  getBleManager()│
  │                 │                    │────────────────>│
  │                 │                    │  <new instance> │
  │                 │                    │<────────────────│
  │                 │                    │  setUp()        │
  │                 │                    │────────────────>│
  │                 │                    │  registerProfile│
  │                 │                    │<────────────────│
  │                 │  <initialized>     │                 │
  │                 │<───────────────────│                 │
```

### 8.2 자동 연결 시퀀스 (성공 케이스)

```
Garmin OS    RunVisionIQView      ILensBLE          iLens Device
    │               │                 │                    │
    │  compute()    │                 │                    │
    │──────────────>│                 │                    │
    │               │  isConnected()  │                    │
    │               │────────────────>│                    │
    │               │  false          │                    │
    │               │<────────────────│                    │
    │               │  requestScanning()                   │
    │               │────────────────>│                    │
    │               │                 │  setScanState()    │
    │               │                 │  (SCANNING)        │
    │               │                 │───────────────────>│
    │               │                 │  <scanning...>     │
    │               │                 │                    │
    │               │                 │  onScanResults()   │
    │               │                 │<───────────────────│
    │               │                 │  "iLens-5883" found│
    │               │                 │  connect()         │
    │               │                 │───────────────────>│
    │               │                 │  pairDevice()      │
    │               │                 │                    │
    │               │                 │  onConnectedStateChanged()
    │               │                 │<───────────────────│
    │               │                 │  CONNECTED         │
    │               │                 │  getCharacteristic()
    │               │                 │  (retry 5회)        │
    │               │  <connected>    │                    │
    │               │<────────────────│                    │
    │               │                 │                    │
    │  compute()    │                 │                    │
    │──────────────>│                 │                    │
    │               │  sendDataToILens()                   │
    │               │────────────────>│                    │
    │               │                 │  sendMetrics()     │
    │               │                 │───────────────────>│
    │               │                 │  [4 BLE writes]    │
```

### 8.3 데이터 전송 시퀀스

```
Garmin OS  RunVisionIQView  ILensBLE    iLens Device
    │           │              │              │
    │ compute() │              │              │
    │  (Activity.Info)         │              │
    │──────────>│              │              │
    │           │ extractSpeed()              │
    │           │ extractDistance()           │
    │           │ extractHeartRate()          │
    │           │ extractCadence()            │
    │           │              │              │
    │           │ sendMetrics(s,d,hr,cad)     │
    │           │─────────────>│              │
    │           │              │ sendMetric(0x07, speed)
    │           │              │─────────────>│
    │           │              │ [0x07][val]  │
    │           │              │              │
    │           │              │ sendMetric(0x06, distance)
    │           │              │─────────────>│
    │           │              │ [0x06][val]  │
    │           │              │              │
    │           │              │ sendMetric(0x0B, hr)
    │           │              │─────────────>│
    │           │              │ [0x0B][val]  │
    │           │              │              │
    │           │              │ sendMetric(0x0E, cadence)
    │           │              │─────────────>│
    │           │              │ [0x0E][val]  │
    │           │              │              │
    │           │ <success>    │              │
    │           │<─────────────│              │
```

---

## 9. 상태 머신

### 9.1 BLE 연결 상태

```
┌─────────────┐
│  IDLE       │ (프로필 미등록)
└──────┬──────┘
       │ setUp()
       ↓
┌─────────────┐
│ REGISTERED  │ (프로필 등록 완료)
└──────┬──────┘
       │ requestScanning()
       ↓
┌─────────────┐
│  SCANNING   │ (스캔 중)
└──────┬──────┘
       │ onScanResults()
       ↓
┌─────────────┐
│ CONNECTING  │ (연결 중)
└──────┬──────┘
       │ onConnectedStateChanged()
       ↓
┌─────────────┐
│  CONNECTED  │ (연결 완료, 데이터 전송 가능)
└──────┬──────┘
       │ disconnect() or 자동 끊김
       ↓
┌─────────────┐
│DISCONNECTED │
└──────┬──────┘
       │ 재연결
       └────> SCANNING
```

### 9.2 자동 연결 관리 상태

```
┌──────────────┐
│  ENABLED     │ (ilensEnabled = true)
└──────┬───────┘
       │
       ├─ autoConnect = true
       │  ↓
       │  ┌──────────────┐
       │  │AUTO_SCAN_1   │ (1차 스캔)
       │  └──────┬───────┘
       │         │ 성공 → CONNECTED
       │         │ 실패 ↓
       │  ┌──────────────┐
       │  │AUTO_SCAN_2   │ (2차 스캔)
       │  └──────┬───────┘
       │         │ 성공 → CONNECTED
       │         │ 실패 ↓
       │  ┌──────────────┐
       │  │AUTO_SCAN_3   │ (3차 스캔)
       │  └──────┬───────┘
       │         │ 성공 → CONNECTED
       │         │ 실패 ↓
       │  ┌──────────────┐
       │  │AUTO_DISABLED │ (이번 세션만)
       │  └──────────────┘
       │
       └─ autoConnect = false
          ↓
          ┌──────────────┐
          │ MANUAL_MODE  │ (수동 연결)
          └──────────────┘
```

---

## 10. 에러 처리

### 10.1 null 안전성

**문제**: Activity.Info 필드는 null일 수 있음

**해결**:
```monkey-c
private function extractSpeed(info) {
    if (info.currentSpeed != null && info.currentSpeed > 0) {
        return (info.currentSpeed * 3.6).toNumber();
    }
    return 0; // 기본값
}
```

### 10.2 BLE 전송 실패

**문제**: BLE write가 실패할 수 있음

**해결**:
```monkey-c
function sendMetric(metricId, value) {
    try {
        _exerciseCharacteristic.requestWrite(payload, {...});
        return true;
    } catch (e) {
        log("BLE write failed: " + e.getErrorMessage());
        return false;
    }
}
```

### 10.3 Characteristic 미발견

**문제**: getCharacteristic()이 null 반환 가능

**해결**: 5회 재시도 로직
```monkey-c
private function tryGetCharacteristic(serviceUuid, charUuid, maxRetries) {
    for (var i = 0; i < maxRetries; i++) {
        // ... 시도
    }
    return null; // 실패
}
```

### 10.4 연결 끊김

**문제**: 러닝 중 BLE 연결이 끊어질 수 있음

**해결**: 자동 재연결 (최대 3회)
```monkey-c
// compute()에서 자동 감지
if (!ble.isConnected()) {
    if (_scanAttempts < 3) {
        ble.requestScanning();
        _scanAttempts++;
    }
}
```

---

## 11. 메모리 최적화

### 11.1 디버그 로깅 제거

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

**효과**: 릴리스 빌드에서 로깅 코드 완전 제거

### 11.2 문자열 상수화

```monkey-c
// ❌ 나쁜 예
var uuid = BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08");

// ✅ 좋은 예
const SERVICE_UUID_STRING = "4b329cf2-3816-498c-8453-ee8798502a08";
var uuid = BluetoothLowEnergy.stringToUuid(SERVICE_UUID_STRING);
```

### 11.3 배열 크기 고정

```monkey-c
// ✅ 고정 크기 (메모리 효율적)
var payload = new [5]b;
payload[0] = metricId;
payload[1] = (valueInt & 0xFF);
// ...
```

### 11.4 불필요한 객체 생성 방지

```monkey-c
// ❌ 나쁜 예 (매번 새 객체 생성)
function compute(info) {
    var ble = new ILensBLE(); // 매번 생성!
}

// ✅ 좋은 예 (싱글톤)
function compute(info) {
    var ble = ILens.getBleManager(); // 재사용
}
```

---

## 12. 성능 고려사항

### 12.1 compute() 실행 시간

**목표**: < 10ms (50ms 주기의 20% 이내)

**측정**:
```monkey-c
function compute(info) {
    var startTime = System.getTimer();

    // ... 실행

    var elapsed = System.getTimer() - startTime;
    log("compute() took " + elapsed + "ms");
}
```

**최적화**:
- ✅ 무거운 계산 제거 (통계 계산 없음)
- ✅ BLE 전송 1Hz로 제한
- ✅ 조건문으로 조기 종료

### 12.2 배터리 소모

**주요 요인**:
1. BLE 스캔 (높음)
2. BLE 연결 유지 (중간)
3. BLE 데이터 전송 (낮음)

**최적화**:
- ✅ 스캔 시도 3회로 제한
- ✅ 데이터 전송 1Hz
- ✅ Settings OFF 시 BLE 완전 비활성화

**예상 배터리 소모**:
- BLE 연결 유지: ~2-3% / hour
- 데이터 전송 (1Hz): ~0.5% / hour
- **총**: ~2.5-3.5% / hour (GPS 제외)

### 12.3 메모리 사용량

**예상 메모리**:
- RunVisionIQView: ~1KB (필드 변수)
- ILensBLE: ~0.5KB (필드 변수)
- UUID, Characteristic 참조: ~0.5KB
- **총**: ~2KB

**fenix7 기준**: 메모리 사용량 <5% (안전)

---

## 13. 정리

### 13.1 핵심 설계 결정

1. **DataField 기반**: Activity App 대신 DataField (개발 기간 75% 단축)
2. **싱글톤 BLE Manager**: 메모리 효율적, 상태 일관성
3. **자동 연결 관리**: 3회 시도 후 자동 비활성화
4. **전송 주기 제한**: 1Hz (배터리 절약)
5. **null 안전성**: 모든 Activity.Info 접근 시 null 체크
6. **재시도 로직**: Characteristic 읽기 5회 재시도
7. **Settings 통합**: Garmin Connect Mobile 앱에서 제어

### 13.2 구현 체크리스트

**ILensBLE 클래스**:
- [ ] 싱글톤 패턴 (`ILens.getBleManager()`)
- [ ] UUID 상수 정의
- [ ] 프로필 등록 (1개)
- [ ] 스캔 및 연결 로직
- [ ] Characteristic 재시도 로직 (5회)
- [ ] UINT32 Little-Endian 인코딩
- [ ] 4개 메트릭 전송 메서드
- [ ] 디버그 로깅 분리

**RunVisionIQView 클래스**:
- [ ] initialize() - Settings 읽기, BLE 초기화
- [ ] compute() - 데이터 수집 및 전송 (1Hz 제한)
- [ ] onUpdate() - UI 표시 (연결 상태)
- [ ] onTimer* - 타이머 이벤트 핸들러 (6개)
- [ ] extract* - 데이터 추출 메서드 (4개, null 안전)
- [ ] 자동 연결 관리 로직
- [ ] 디버그 로깅 분리

**Settings**:
- [ ] properties.xml 작성
- [ ] ilensEnabled, autoConnect, transmitRate

**Manifest**:
- [ ] 권한 정의 (BluetoothLowEnergy, Positioning, Sensor)
- [ ] 지원 기기 목록 (Forerunner 265, 955, 965, Fenix 7)
- [ ] 최소 SDK 버전 (4.0.0)

---

**문서 작성**: 2025-11-15
**다음 단계**: PRD, System-Architecture, Module-Design 재작성
**승인 상태**: 승인 대기 중

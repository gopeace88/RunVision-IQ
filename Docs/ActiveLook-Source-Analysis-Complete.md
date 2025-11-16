# ActiveLook 소스 전체 구조 분석 (RunVision-IQ 포팅용)

**문서 버전**: v2.0
**작성일**: 2025-11-15
**작성자**: Claude (AI Assistant)
**참조**: https://github.com/dliedke/ActiveLook-Garmin-DataField
**목적**: ActiveLook 전체 복사 + iLens BLE 교체 전략

---

## 📋 목차

1. [개발 전략 변경](#1-개발-전략-변경)
2. [ActiveLook 파일 구조](#2-activelook-파일-구조)
3. [모듈별 상세 분석](#3-모듈별-상세-분석)
4. [BLE 프로토콜 매핑 전략](#4-ble-프로토콜-매핑-전략)
5. [파워 메트릭 활용](#5-파워-메트릭-활용)
6. [구현 로드맵](#6-구현-로드맵)

---

## 1. 개발 전략 변경

### 1.1 이전 접근 (❌ 잘못됨)

**착각한 내용**:
- ActiveLook이 GPS 데이터로부터 속도/거리를 직접 계산한다고 생각
- RunVision-IQ는 "간소화된 버전"으로 통계 계산 없이 단순 전송만
- 복잡도: ActiveLook ⭐⭐⭐⭐⭐ vs RunVision-IQ ⭐⭐

**실제**:
- Garmin OS가 `Activity.getActivityInfo()`로 모든 기본 메트릭 제공
- ActiveLook의 통계 계산은 **추가 기능** (3초 파워, 정규화 파워 등)
- 이 통계들은 Garmin 워치 화면 표시용이지만, **iLens로 전송 가능**

### 1.2 올바른 접근 (✅ 수정됨)

**개발 전략**:
```
ActiveLook 소스 100% 복사
        ↓
BLE 레이어만 교체 (ActiveLook → iLens)
        ↓
모든 통계 계산 유지
        ↓
ActiveLook이 계산한 파워를 iLens로 전송
```

**장점**:
- ✅ ActiveLook의 검증된 로직 재사용
- ✅ 파워 메트릭 활용 (3초 파워, 정규화 파워, 평균 파워)
- ✅ 개발 시간 단축 (BLE 레이어만 교체)
- ✅ 안정성 향상 (실전 검증된 코드)

**복잡도 재평가**:
```
ActiveLook: ⭐⭐⭐⭐⭐ (모든 기능 포함)
RunVision-IQ: ⭐⭐⭐⭐⭐ (ActiveLook 복사) + ⭐⭐ (BLE 교체)
개발 노력: ⭐⭐ (BLE 레이어만 수정)
```

---

## 2. ActiveLook 파일 구조

### 2.1 전체 파일 목록

```
source/
├── ActiveLook.mc                    # ⭐ BLE Manager (싱글톤) - 교체 필요
├── ActiveLookActivityInfo.mc        # ✅ Activity.Info 처리 + 통계 계산 - 유지
├── ActiveLookDataFieldApp.mc        # ✅ App 진입점 - 유지 (이름만 변경)
├── ActiveLookDataFieldView.mc       # ✅ DataField 메인 로직 - 유지 (BLE 호출 수정)
├── ActiveLookSDK_next.mc            # ⭐ ActiveLook 프로토콜 - 교체 필요
└── Laps.mc                          # ✅ 랩 데이터 관리 - 유지

resources/
├── properties.xml                   # ✅ Settings 정의 - 수정 (iLens 관련)
└── drawables/                       # ✅ 이미지 리소스 - 유지
```

**교체 필요 (2개)**:
- `ActiveLook.mc` → `ILens.mc`
- `ActiveLookSDK_next.mc` → `ILensProtocol.mc`

**유지 (4개 + 리소스)**:
- `ActiveLookActivityInfo.mc` → `RunVisionActivityInfo.mc` (이름만)
- `ActiveLookDataFieldApp.mc` → `RunVisionIQApp.mc` (이름만)
- `ActiveLookDataFieldView.mc` → `RunVisionIQView.mc` (BLE 호출 수정)
- `Laps.mc` (그대로 유지)

---

## 3. 모듈별 상세 분석

### 3.1 ActiveLook.mc (BLE Manager) - ⭐ 교체 대상

#### 3.1.1 현재 구조

```monkey-c
module ActiveLook {
    private static var _activeLook = null;

    function getBle() {
        if (_activeLook == null) {
            _activeLook = new ActiveLook();
        }
        return _activeLook;
    }
}

class ActiveLook extends BluetoothLowEnergy.BleDelegate {

    // 3개 프로필 순차 등록
    const PRIMARY_SERVICE_UUID = "0783B03E-8535-B5A0-7140-A304D2495CB7";
    const DEVICE_INFO_UUID = "0000180A-0000-1000-8000-00805F9B34FB";
    const BATTERY_UUID = "0000180F-0000-1000-8000-00805F9B34FB";

    private var _profileRegisterCount = 0;
    private var _profilesRegistered = false;
    private var _device = null;

    function setUp() {
        if (_profilesRegistered) { return; }
        BluetoothLowEnergy.registerProfile(self, PRIMARY_SERVICE_UUID);
    }

    function onProfileRegister(uuid, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileRegisterCount++;

            if (uuid.equals(PRIMARY_SERVICE_UUID)) {
                BluetoothLowEnergy.registerProfile(self, DEVICE_INFO_UUID);
            } else if (uuid.equals(DEVICE_INFO_UUID)) {
                BluetoothLowEnergy.registerProfile(self, BATTERY_UUID);
            } else if (uuid.equals(BATTERY_UUID)) {
                _profilesRegistered = true;
            }
        }
    }

    function requestScanning() {
        if (!_profilesRegistered) { setUp(); return; }
        BluetoothLowEnergy.setScanState(SCAN_STATE_SCANNING);
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
        BluetoothLowEnergy.setScanState(SCAN_STATE_OFF);
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device);
        }
        BluetoothLowEnergy.pairDevice(device);
    }

    function onConnectedStateChanged(device, state) {
        if (state == CONNECTION_STATE_CONNECTED) {
            _device = device;
        } else {
            _device = null;
        }
    }

    // 5회 재시도 로직
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

#### 3.1.2 iLens 교체 버전

```monkey-c
module ILens {
    private static var _ilens = null;

    function getBle() {
        if (_ilens == null) {
            _ilens = new ILensBleManager();
        }
        return _ilens;
    }
}

class ILensBleManager extends BluetoothLowEnergy.BleDelegate {

    // 1개 프로필만 등록 (iLens Exercise Data Service)
    const SERVICE_UUID = BluetoothLowEnergy.stringToUuid(
        "4b329cf2-3816-498c-8453-ee8798502a08"
    );

    const EXERCISE_DATA_CHAR_UUID = BluetoothLowEnergy.stringToUuid(
        "c259c1bd-18d3-c348-b88d-5447aea1b615"
    );

    private var _profileRegistered = false;
    private var _device = null;
    private var _exerciseCharacteristic = null;

    function setUp() {
        if (_profileRegistered) { return; }
        BluetoothLowEnergy.registerProfile(self, SERVICE_UUID);
    }

    function onProfileRegister(uuid, status) {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileRegistered = true;
        }
    }

    function requestScanning() {
        if (!_profileRegistered) { setUp(); return; }
        BluetoothLowEnergy.setScanState(SCAN_STATE_SCANNING);
    }

    function onScanResults(scanResults) {
        for (var i = 0; i < scanResults.size(); i++) {
            var result = scanResults[i];

            // Method 1: Manufacturer Specific Data 확인 ("iLens-sw")
            var manufacturerData = result.getManufacturerSpecificDataIterator();
            while (manufacturerData.hasNext()) {
                var data = manufacturerData.next();
                if (containsILensMarker(data)) {
                    _foundDevices.add(result);
                    break;
                }
            }

            // Method 2: Device Name 확인 (백업)
            var deviceName = result.getDeviceName();
            if (deviceName != null && deviceName.find("iLens") != null) {
                _foundDevices.add(result);
            }
        }
    }

    function containsILensMarker(data) {
        // "iLens-sw" = [0x69, 0x4C, 0x65, 0x6E, 0x73, 0x2D, 0x73, 0x77]
        var marker = [0x69, 0x4C, 0x65, 0x6E, 0x73, 0x2D, 0x73, 0x77];
        // 패턴 매칭 로직
        return findPattern(data, marker);
    }

    function connect(device) {
        BluetoothLowEnergy.setScanState(SCAN_STATE_OFF);
        if (_device != null) {
            BluetoothLowEnergy.unpairDevice(_device);
        }
        BluetoothLowEnergy.pairDevice(device);
    }

    function onConnectedStateChanged(device, state) {
        if (state == CONNECTION_STATE_CONNECTED) {
            _device = device;
            _exerciseCharacteristic = tryGetServiceCharacteristic(
                SERVICE_UUID,
                EXERCISE_DATA_CHAR_UUID,
                5
            );
        } else {
            _device = null;
            _exerciseCharacteristic = null;
        }
    }

    // ActiveLook과 동일한 재시도 로직 유지
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

    function isConnected() {
        return _device != null && _exerciseCharacteristic != null;
    }
}
```

**핵심 변경사항**:
- ✅ 3개 프로필 → 1개 프로필 (단순화)
- ✅ Microoled 필터 → iLens 필터
- ✅ ActiveLook UUID → iLens UUID
- ✅ 재시도 로직 유지 (5회)
- ✅ 싱글톤 패턴 유지

---

### 3.2 ActiveLookSDK_next.mc (프로토콜) - ⭐ 교체 대상

#### 3.2.1 ActiveLook 프로토콜 (Text/Layout 기반)

**특징**:
- Text 및 Layout 명령어 전송
- 명령어 포맷: `[0xFF, command_ID, length, text_data..., 0xAA]`
- 화면 레이아웃 관리 중심

**예시**:
```monkey-c
function text(x, y, text) {
    var command = [0xFF, 0x35, ...]; // Text Display Command
    sendCommand(command);
}

function sendRecordingStatus(status) {
    // 0: Start, 1: Pause, 2: Stop
    var command = [0xFF, 0x40, 0x01, status, 0xAA];
    sendCommand(command);
}
```

#### 3.2.2 iLens 프로토콜 (Binary Metric 기반)

**특징**:
- Binary 메트릭 전송
- 데이터 포맷: `[Metric_ID(1 byte), UINT32(4 bytes, Little-Endian)]`
- 개별 메트릭 전송 (배치 없음)

**구현**:
```monkey-c
module ILensProtocol {

    // UINT32 Little-Endian 인코딩
    function encodeUInt32(value) {
        var bytes = new [4]b;
        bytes[0] = (value & 0xFF);
        bytes[1] = ((value >> 8) & 0xFF);
        bytes[2] = ((value >> 16) & 0xFF);
        bytes[3] = ((value >> 24) & 0xFF);
        return bytes;
    }

    // 단일 메트릭 전송
    function sendMetric(characteristic, metricId, value) {
        if (characteristic == null) { return; }

        var payload = new [5]b;
        payload[0] = metricId;

        var valueBytes = encodeUInt32(value);
        payload[1] = valueBytes[0];
        payload[2] = valueBytes[1];
        payload[3] = valueBytes[2];
        payload[4] = valueBytes[3];

        characteristic.requestWrite(payload, {:writeType => WRITE_TYPE_DEFAULT});
    }

    // 복수 메트릭 전송 (순차)
    function sendMetrics(characteristic, metrics) {
        // metrics = { metricId => value }
        var keys = metrics.keys();
        for (var i = 0; i < keys.size(); i++) {
            var metricId = keys[i];
            var value = metrics[metricId];
            sendMetric(characteristic, metricId, value);
        }
    }

    // 편의 함수들
    function sendSpeed(characteristic, speedKmh) {
        sendMetric(characteristic, 0x07, speedKmh);
    }

    function sendDistance(characteristic, distanceMeters) {
        sendMetric(characteristic, 0x06, distanceMeters);
    }

    function sendHeartRate(characteristic, bpm) {
        sendMetric(characteristic, 0x0B, bpm);
    }

    function sendCadence(characteristic, spm) {
        sendMetric(characteristic, 0x0E, spm);
    }

    function sendCurrentPower(characteristic, watts) {
        sendMetric(characteristic, 0x11, watts);
    }

    function sendMaxPower(characteristic, watts) {
        sendMetric(characteristic, 0x12, watts);
    }

    function sendAveragePower(characteristic, watts) {
        sendMetric(characteristic, 0x13, watts);
    }

    function sendRecordStatus(characteristic, status) {
        // 0: Start, 1: Pause, 2: End
        sendMetric(characteristic, 0x01, status);
    }
}
```

**핵심 변경사항**:
- ✅ Text 명령 → Binary 메트릭
- ✅ ActiveLook 포맷 → iLens 포맷
- ✅ 배치 전송 → 개별 전송
- ✅ 파워 메트릭 추가 (0x11, 0x12, 0x13)

---

### 3.3 ActiveLookActivityInfo.mc - ✅ 유지 (파워 계산 활용)

#### 3.3.1 핵심 기능

```monkey-c
class AugmentedActivityInfo {

    private var __ai;   // Activity.Info 객체
    private var _powerSamples;     // 최근 30개 전력값
    private var _altitudeSamples;  // 최대 20개 고도 샘플

    // 통계 필드 (계산된 값)
    private var _threesecondPower;   // 3초 평균 전력
    private var _normalizedPower;    // 정규화 전력
    private var _averageAscentRate;  // 평균 상승속도

    // 1. 시계열 데이터 누적 (매 compute() 호출 시)
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
            // (50ms * 6 = 300ms ≈ 0.3s, 실제로는 ~3s 데이터)
            if (_powerSamples.size() >= 6) {
                _threesecondPower = calculate3sPower(_powerSamples);
            }

            // 정규화전력 계산 (4차 함수)
            _normalizedPower = calculateNormalizedPower(_powerSamples);
        }

        // 고도 데이터 누적
        var totalAscent = info.totalAscent;
        if (totalAscent != null) {
            _altitudeSamples.add(totalAscent);
            if (_altitudeSamples.size() > 20) {
                _altitudeSamples.remove(0);
            }
            _averageAscentRate = calculateAscentRate(_altitudeSamples);
        }
    }

    // 2. 통계 계산 (페이스, 심박수 영역 등)
    function compute(info) {
        // 속도 → 페이스 역산
        if (info.currentSpeed != null && info.currentSpeed > 0) {
            _currentPace = 1.0 / info.currentSpeed;
        }

        // 러닝 동역학 평균
        computeRunningDynamics();

        // 심박수 영역 판정
        computeHeartRateZone(info.currentHeartRate);
    }

    // 3. 3초 평균 전력 계산
    function calculate3sPower(samples) {
        if (samples.size() < 6) { return null; }

        var sum = 0;
        var count = 0;

        // 최근 6개 샘플 (약 3초)
        var startIdx = samples.size() - 6;
        for (var i = startIdx; i < samples.size(); i++) {
            sum += samples[i];
            count++;
        }

        return (count > 0) ? (sum / count).toNumber() : null;
    }

    // 4. 정규화 전력 (Normalized Power)
    function calculateNormalizedPower(samples) {
        if (samples.size() < 6) { return null; }

        var sum4th = 0;
        var count = 0;

        for (var i = 0; i < samples.size(); i++) {
            var power = samples[i];
            sum4th += Math.pow(power, 4);
            count++;
        }

        if (count == 0) { return null; }

        var avg4th = sum4th / count;
        return Math.pow(avg4th, 0.25).toNumber(); // 4th root
    }

    // 5. 평균 상승속도
    function calculateAscentRate(altitudeSamples) {
        if (altitudeSamples.size() < 2) { return null; }

        var first = altitudeSamples[0];
        var last = altitudeSamples[altitudeSamples.size() - 1];
        var delta = last - first;
        var time = altitudeSamples.size() * 0.05; // 50ms per sample

        return (time > 0) ? (delta / time) : 0;
    }

    // 6. 다층 접근 (자체 계산 필드 > Activity.Info 필드)
    function get(key) {
        if (self has key) {
            return self[key];
        }
        if (__ai != null && __ai has key) {
            return __ai[key];
        }
        return null;
    }
}
```

#### 3.3.2 RunVision-IQ 활용 전략

**이름 변경만**:
```
ActiveLookActivityInfo.mc → RunVisionActivityInfo.mc
AugmentedActivityInfo → RunVisionActivityInfo
```

**활용**:
- ✅ 모든 통계 계산 로직 유지
- ✅ `_threesecondPower` → iLens 0x11 (Current Power)
- ✅ `_normalizedPower` → iLens 0x13 (Average Power)
- ✅ `info.maxPower` → iLens 0x12 (Maximum Power)
- ✅ 파워 미터 없으면 null, iLens에 0 전송

---

### 3.4 ActiveLookDataFieldView.mc - ✅ 유지 (BLE 호출 수정)

#### 3.4.1 현재 구조

```monkey-c
class ActiveLookDataFieldView extends WatchUi.DataField {

    private var _sdk;    // ActiveLookSDK
    private var _ble;    // ActiveLook BLE Manager

    function initialize() {
        DataField.initialize();

        // BLE Manager 초기화
        _ble = ActiveLook.getBle();
        _ble.setUp();

        // SDK 초기화
        _sdk = new ActiveLookSDK();
    }

    function compute(info) {
        // 1. 데이터 누적 및 계산
        AugmentedActivityInfo.accumulate(info);
        AugmentedActivityInfo.compute(info);

        // 2. ActiveLook 글래스로 전송
        if (_ble.isConnected()) {
            updateFields(info);
        }
    }

    function updateFields(info) {
        // Text/Layout 명령어 전송
        _sdk.text(10, 10, formatSpeed(info.currentSpeed));
        _sdk.text(10, 30, formatDistance(info.elapsedDistance));
        _sdk.sendCommandBuffer();
    }

    function onTimerStart() {
        _sdk.sendRecordingStatus(0);
    }

    function onTimerPause() {
        _sdk.sendRecordingStatus(1);
    }

    function onTimerStop() {
        _sdk.sendRecordingStatus(2);
    }
}
```

#### 3.4.2 iLens 수정 버전

```monkey-c
class RunVisionIQView extends WatchUi.DataField {

    private var _protocol;   // ILensProtocol
    private var _ble;        // ILens BLE Manager
    private var _activityInfo;  // RunVisionActivityInfo

    private var _lastSendTime = 0;
    const SEND_INTERVAL_MS = 1000; // 1Hz

    function initialize() {
        DataField.initialize();

        // BLE Manager 초기화
        _ble = ILens.getBle();
        _ble.setUp();

        // Protocol 초기화
        _protocol = new ILensProtocol();

        // ActivityInfo 초기화
        _activityInfo = new RunVisionActivityInfo();
    }

    function compute(info) {
        // 1. 데이터 누적 및 계산 (ActiveLook과 동일)
        _activityInfo.accumulate(info);
        _activityInfo.compute(info);

        // 2. 전송 주기 제한 (1Hz)
        var now = System.getTimer();
        if (now - _lastSendTime < SEND_INTERVAL_MS) {
            return;
        }

        // 3. iLens로 전송
        if (_ble.isConnected()) {
            sendMetricsToILens(info);
            _lastSendTime = now;
        }
    }

    function sendMetricsToILens(info) {
        var characteristic = _ble.getExerciseCharacteristic();
        if (characteristic == null) { return; }

        // 기본 메트릭 (4개)
        var speedKmh = (info.currentSpeed != null) ?
                       (info.currentSpeed * 3.6).toNumber() : 0;
        var distance = (info.elapsedDistance != null) ?
                       info.elapsedDistance.toNumber() : 0;
        var heartRate = (info.currentHeartRate != null) ?
                        info.currentHeartRate.toNumber() : 0;
        var cadence = (info.currentCadence != null) ?
                      info.currentCadence.toNumber() : 0;

        _protocol.sendSpeed(characteristic, speedKmh);
        _protocol.sendDistance(characteristic, distance);
        _protocol.sendHeartRate(characteristic, heartRate);
        _protocol.sendCadence(characteristic, cadence);

        // 파워 메트릭 (파워 미터 연결 시)
        var currentPower = _activityInfo.get("threesecondPower");
        if (currentPower != null) {
            _protocol.sendCurrentPower(characteristic, currentPower);
        }

        var maxPower = info.maxPower;
        if (maxPower != null) {
            _protocol.sendMaxPower(characteristic, maxPower.toNumber());
        }

        var avgPower = _activityInfo.get("normalizedPower");
        if (avgPower != null) {
            _protocol.sendAveragePower(characteristic, avgPower);
        }
    }

    function onTimerStart() {
        var characteristic = _ble.getExerciseCharacteristic();
        _protocol.sendRecordStatus(characteristic, 0); // Start
    }

    function onTimerPause() {
        var characteristic = _ble.getExerciseCharacteristic();
        _protocol.sendRecordStatus(characteristic, 1); // Pause
    }

    function onTimerResume() {
        var characteristic = _ble.getExerciseCharacteristic();
        _protocol.sendRecordStatus(characteristic, 0); // Resume
    }

    function onTimerStop() {
        var characteristic = _ble.getExerciseCharacteristic();
        _protocol.sendRecordStatus(characteristic, 2); // Stop
    }
}
```

**핵심 변경사항**:
- ✅ `ActiveLookSDK` → `ILensProtocol`
- ✅ Text 명령 → Binary 메트릭
- ✅ 전송 주기 제한 (1Hz)
- ✅ 파워 메트릭 추가 (3개)
- ✅ null 체크 유지

---

### 3.5 Laps.mc - ✅ 그대로 유지

**기능**:
- 랩 데이터 관리 (Current Lap + New Lap)
- `isFrozen` 플래그 (일시정지 상태)
- 평균 계산 (Linear Moving Average)

**유지 이유**:
- BLE 전송과 무관
- 내부 로직만 사용
- ActiveLook에서 검증됨

**사용**:
```monkey-c
function onTimerLap() {
    Laps.onLap();
    // 랩 데이터를 iLens로 전송할 수도 있음 (선택사항)
}
```

---

### 3.6 ActiveLookDataFieldApp.mc - ✅ 이름만 변경

**현재**:
```monkey-c
class ActiveLookDataFieldApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new ActiveLookDataFieldView()];
    }
}
```

**변경 후**:
```monkey-c
class RunVisionIQApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new RunVisionIQView()];
    }
}
```

---

## 4. BLE 프로토콜 매핑 전략

### 4.1 ActiveLook vs iLens 프로토콜 비교

| 항목 | ActiveLook | iLens |
|------|-----------|-------|
| **프로토콜 타입** | Text/Layout 기반 | Binary Metric 기반 |
| **명령어 포맷** | `[0xFF, cmd, len, data..., 0xAA]` | `[Metric_ID, UINT32(4 bytes)]` |
| **데이터 타입** | Text (UTF-8) | UINT32 (Little-Endian) |
| **배치 전송** | Command Buffer | 개별 메트릭 |
| **속도** | "12.5 km/h" (문자열) | 125 (정수, 10배 스케일) |
| **거리** | "5.43 km" (문자열) | 5430 (meters) |
| **파워** | ❌ 미지원 | ✅ 0x11, 0x12, 0x13 |

### 4.2 메트릭 매핑 테이블

| Activity.Info | RunVisionActivityInfo | iLens Metric ID | 변환 |
|---------------|----------------------|-----------------|------|
| `currentSpeed` (m/s) | - | 0x07 (Velocity) | `* 3.6 → km/h` |
| `elapsedDistance` (m) | - | 0x06 (Distance) | meters (그대로) |
| `currentHeartRate` (bpm) | - | 0x0B (Heart Rate) | bpm (그대로) |
| `currentCadence` (spm) | - | 0x0E (Cadence) | spm (그대로) |
| `currentPower` (watts) | `threesecondPower` | 0x11 (Current Power) | watts (3초 평균) |
| `maxPower` (watts) | - | 0x12 (Max Power) | watts (그대로) |
| - | `normalizedPower` | 0x13 (Avg Power) | watts (정규화) |

### 4.3 단위 변환 함수

```monkey-c
module UnitConverter {

    // m/s → km/h (정수)
    function speedToKmh(speedMs) {
        if (speedMs == null || speedMs <= 0) { return 0; }
        return (speedMs * 3.6).toNumber();
    }

    // meters (그대로, 정수화)
    function distanceToMeters(distanceM) {
        if (distanceM == null) { return 0; }
        return distanceM.toNumber();
    }

    // bpm (그대로, 정수화)
    function heartRateToBpm(hr) {
        if (hr == null) { return 0; }
        return hr.toNumber();
    }

    // spm (그대로, 정수화)
    function cadenceToSpm(cadence) {
        if (cadence == null) { return 0; }
        return cadence.toNumber();
    }

    // watts (그대로, 정수화)
    function powerToWatts(power) {
        if (power == null) { return 0; }
        return power.toNumber();
    }
}
```

---

## 5. 파워 메트릭 활용

### 5.1 ActiveLook의 파워 계산 로직

**3초 평균 전력 (3-Second Power)**:
- 최근 30개 샘플 버퍼 유지
- 최근 6개 샘플 평균 (50ms * 6 ≈ 0.3s, 실제로는 더 긴 간격)
- **용도**: 순간 파워 변동 완화

**정규화 전력 (Normalized Power)**:
- 전체 샘플에 대해 4차 함수 평균
- `NP = (avg(power^4))^(1/4)`
- **용도**: 운동 강도 평가 (변동성 고려)

**최대 전력 (Max Power)**:
- `Activity.Info.maxPower` 사용
- Garmin OS가 자동 추적

### 5.2 iLens 전송 전략

**파워 미터 연결 시**:
```monkey-c
// 3초 평균 전력 → Current Power (0x11)
var currentPower = _activityInfo.get("threesecondPower");
if (currentPower != null) {
    _protocol.sendCurrentPower(characteristic, currentPower);
}

// 최대 전력 → Max Power (0x12)
var maxPower = info.maxPower;
if (maxPower != null) {
    _protocol.sendMaxPower(characteristic, maxPower.toNumber());
}

// 정규화 전력 → Average Power (0x13)
var avgPower = _activityInfo.get("normalizedPower");
if (avgPower != null) {
    _protocol.sendAveragePower(characteristic, avgPower);
}
```

**파워 미터 없을 때**:
- `info.currentPower == null`
- 파워 메트릭 전송 생략 (0 전송 또는 스킵)
- iLens 화면에 파워 미표시

### 5.3 ActiveLook vs RunVision-IQ 파워 활용 비교

| 항목 | ActiveLook | RunVision-IQ |
|------|-----------|--------------|
| **파워 계산** | ✅ 3초 평균, 정규화 전력 | ✅ 동일 (유지) |
| **파워 표시** | ✅ Garmin 워치 화면 | ✅ Garmin 워치 화면 |
| **글래스 전송** | ❌ ActiveLook 미지원 | ✅ iLens 지원 (0x11, 0x12, 0x13) |
| **활용 가치** | 워치에서만 확인 | 워치 + 글래스 동시 확인 |

**장점**:
- ✅ ActiveLook의 검증된 파워 계산 로직 재사용
- ✅ iLens의 파워 표시 기능 활용
- ✅ 추가 구현 없이 파워 메트릭 지원

---

## 6. 구현 로드맵

### 6.1 Phase 1: 파일 복사 및 이름 변경

**작업**:
```bash
# ActiveLook 소스 복사
cp ActiveLookActivityInfo.mc RunVisionActivityInfo.mc
cp ActiveLookDataFieldApp.mc RunVisionIQApp.mc
cp ActiveLookDataFieldView.mc RunVisionIQView.mc
cp Laps.mc Laps.mc  # 그대로 유지

# 새 파일 생성
touch ILens.mc
touch ILensProtocol.mc
```

**코드 내 이름 변경**:
- `ActiveLookActivityInfo` → `RunVisionActivityInfo`
- `AugmentedActivityInfo` → `RunVisionActivityInfo`
- `ActiveLookDataFieldApp` → `RunVisionIQApp`
- `ActiveLookDataFieldView` → `RunVisionIQView`

### 6.2 Phase 2: ILens.mc 구현 (BLE Manager)

**작업**:
1. ✅ 싱글톤 패턴 구현
2. ✅ Service UUID 변경 (iLens)
3. ✅ Characteristic UUID 변경 (Exercise Data)
4. ✅ 스캔 필터 변경 (Microoled → iLens-sw)
5. ✅ 프로필 등록 단순화 (3개 → 1개)
6. ✅ 재시도 로직 유지 (5회)

**참조**: [3.1.2 iLens 교체 버전](#312-ilens-교체-버전)

### 6.3 Phase 3: ILensProtocol.mc 구현

**작업**:
1. ✅ UINT32 Little-Endian 인코딩 함수
2. ✅ 개별 메트릭 전송 함수 (sendMetric)
3. ✅ 편의 함수들 (sendSpeed, sendDistance, etc.)
4. ✅ 파워 메트릭 함수 (sendCurrentPower, sendMaxPower, sendAveragePower)
5. ✅ Record Status 함수 (sendRecordStatus)

**참조**: [3.2.2 iLens 프로토콜](#322-ilens-프로토콜-binary-metric-기반)

### 6.4 Phase 4: RunVisionIQView.mc 수정

**작업**:
1. ✅ BLE Manager 교체 (`ActiveLook.getBle()` → `ILens.getBle()`)
2. ✅ Protocol 교체 (`ActiveLookSDK` → `ILensProtocol`)
3. ✅ `sendMetricsToILens()` 함수 구현
4. ✅ 전송 주기 제한 (1Hz)
5. ✅ 파워 메트릭 전송 추가
6. ✅ `onTimer*` 이벤트 핸들러 수정

**참조**: [3.4.2 iLens 수정 버전](#342-ilens-수정-버전)

### 6.5 Phase 5: 테스트

**단위 테스트**:
- ✅ `encodeUInt32()` 함수 검증
- ✅ `sendMetric()` 함수 검증
- ✅ 단위 변환 함수 검증

**통합 테스트**:
- ✅ iLens 스캔 및 연결
- ✅ 메트릭 전송 확인 (4개 기본 + 3개 파워)
- ✅ Record Status 전송 확인
- ✅ 1Hz 주기 검증

**실제 기기 테스트**:
- ✅ Forerunner 265/955/965
- ✅ iLens 글래스
- ✅ 파워 미터 (선택사항)

### 6.6 Phase 6: Settings 및 리소스

**properties.xml 수정**:
```xml
<properties>
    <property id="ilensEnabled" type="boolean">
        <default>true</default>
    </property>

    <property id="autoConnect" type="boolean">
        <default>true</default>
    </property>

    <property id="transmitRate" type="number">
        <default>1</default> <!-- 1Hz -->
    </property>

    <property id="sendPowerMetrics" type="boolean">
        <default>true</default>
    </property>
</properties>
```

**manifest.xml 수정**:
- App Name: "RunVision-IQ"
- Version: 1.0.0
- Permissions: `ble`, `positioning`, `sensor`

---

## 7. 정리

### 7.1 핵심 요약

**개발 전략**:
```
✅ ActiveLook 100% 복사
✅ BLE 레이어만 교체 (ActiveLook.mc, ActiveLookSDK_next.mc)
✅ 모든 통계 계산 유지
✅ 파워 메트릭 활용 (3개 추가)
```

**교체 파일 (2개)**:
- `ActiveLook.mc` → `ILens.mc`
- `ActiveLookSDK_next.mc` → `ILensProtocol.mc`

**유지 파일 (4개)**:
- `ActiveLookActivityInfo.mc` → `RunVisionActivityInfo.mc` (이름만)
- `ActiveLookDataFieldView.mc` → `RunVisionIQView.mc` (BLE 호출 수정)
- `ActiveLookDataFieldApp.mc` → `RunVisionIQApp.mc` (이름만)
- `Laps.mc` (그대로)

**파워 메트릭 활용**:
- ✅ 3초 평균 전력 → iLens 0x11 (Current Power)
- ✅ 정규화 전력 → iLens 0x13 (Average Power)
- ✅ 최대 전력 → iLens 0x12 (Maximum Power)

### 7.2 개발 노력 평가

**재사용 비율**: 90%
- ✅ 데이터 수집 로직 (100%)
- ✅ 통계 계산 로직 (100%)
- ✅ 랩 관리 로직 (100%)
- ✅ BLE Manager 패턴 (80%)

**신규 구현 비율**: 10%
- 🔄 iLens BLE 프로토콜 (Binary Metric)
- 🔄 iLens 스캔 필터 ("iLens-sw")
- 🔄 UINT32 인코딩 함수

**예상 개발 시간**:
- Phase 1: 파일 복사 및 이름 변경 - 1일
- Phase 2: ILens.mc 구현 - 2일
- Phase 3: ILensProtocol.mc 구현 - 2일
- Phase 4: RunVisionIQView.mc 수정 - 2일
- Phase 5: 테스트 - 3일
- Phase 6: Settings 및 리소스 - 1일
- **총 예상 시간**: 11일

---

**문서 작성**: 2025-11-15
**다음 단계**: PRD v3.0 재작성 (ActiveLook 기반 + iLens BLE)
**승인 상태**: 승인 대기 중

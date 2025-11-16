# iLens BLE 프로토콜 정밀 분석

**문서 버전**: v1.0
**작성일**: 2025-11-15
**작성자**: Claude (AI Assistant)
**참조**: iLens BLE V1.0.10.pdf
**목적**: RunVision-IQ 개발을 위한 정확한 iLens BLE 프로토콜 명세

---

## 📋 목차

1. [BLE 스캔 및 필터링](#1-ble-스캔-및-필터링)
2. [Service 및 Characteristic UUID](#2-service-및-characteristic-uuid)
3. [운동 데이터 프로토콜](#3-운동-데이터-프로토콜)
4. [데이터 인코딩 방식](#4-데이터-인코딩-방식)
5. [RunVision-IQ 구현 명세](#5-runvision-iq-구현-명세)

---

## 1. BLE 스캔 및 필터링

### 1.1 Broadcast Service Data

iLens 기기는 다음과 같은 브로드캐스트 데이터를 전송합니다:

```
0x020102020A0009FF694C656E732D73770B09694C656E732D35383833
```

#### Part I: Flags
```
02 01 02
- Length: 0x02 (2 bytes)
- Type: 0x01 (Flags)
- Data: 0x02 (General Discoverable Mode, BR/EDR 미지원)
```

#### Part II: Tx Power Level
```
02 0A 00
- Length: 0x02
- Type: 0x0A (Tx Power Level)
- Data: 0x00 (0 dBm)
```

#### Part III: Manufacturer Specific Data ⭐
```
09 FF 69 4C 65 6E 73 2D 7377
- Length: 0x09 (9 bytes)
- Type: 0xFF (Manufacturer Specific Data)
- Data: 69 4C 65 6E 73 2D 7377
- ASCII: "iLens-sw" (필터링 키워드)
```

#### Part IV: Complete Local Name
```
0B 09 69 4C 65 6E 73 2D 35 38 38 33
- Length: 0x0B (11 bytes)
- Type: 0x09 (Complete Local Name)
- Data: 69 4C 65 6E 73 2D 35 38 38 33
- ASCII: "iLens-5883" (기기 이름)
```

### 1.2 스캔 필터링 전략

**Connect IQ 구현**:
```monkey-c
function onScanResults(scanResults) {
    for (var i = 0; i < scanResults.size(); i++) {
        var result = scanResults[i];

        // Method 1: Manufacturer Specific Data 확인
        var manufacturerData = result.getManufacturerSpecificDataIterator();
        while (manufacturerData.hasNext()) {
            var data = manufacturerData.next();
            // "iLens-sw" 문자열 포함 여부 확인
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
    // 데이터에서 marker 패턴 찾기
    return findPattern(data, marker);
}
```

---

## 2. Service 및 Characteristic UUID

### 2.1 Device Information Service

**Service UUID**: `0x180A` (표준 BLE Service)

| Characteristic | UUID | 설명 | 권한 |
|---------------|------|------|------|
| Serial Number String | 0x2A25 | SN 번호 | READ |
| Firmware Revision | 0x2A26 | 펌웨어 버전 | READ |
| Hardware Revision | 0x2A27 | 하드웨어 번호 | READ |
| Software Revision | 0x2A28 | 소프트웨어 버전 | READ |
| Manufacturer Name | 0x2A29 | 제조사 이름 | READ |

### 2.2 Device Configuration Service

**Service UUID**: `58211C97-482A-2808-2D3E-228405F1E749`

| Characteristic | UUID | 설명 |
|---------------|------|------|
| Device Name | 43446626-85f8-432a-871e-ac8c0a57004c | 기기 이름 설정 |
| Battery Level | 33BD4A32-F763-0391-2820-55610F999AEF | 배터리 레벨 0~100 |
| Battery Level Status | B189323F-4BAB-D09C-4E24-DCC5FE65BEF1 | 충전 상태 (0: 기본, 1: 충전 중) |
| Current Time | 54AC7F82-EB87-AA4E-0154-A71D80471E6E | 현재 시간 설정 |
| Brightness | 462b6a99-3378-4364-9156-48aa972afd98 | 밝기 0~100 |

### 2.3 Custom Service (운동 데이터) ⭐⭐⭐

**Service UUID**: `4b329cf2-3816-498c-8453-ee8798502a08`

| Characteristic | UUID | 설명 | 권한 |
|---------------|------|------|------|
| **Exercise Data** | `c259c1bd-18d3-c348-b88d-5447aea1b615` | **운동 메트릭 전송** | **WRITE** |
| Information Tips | 0eb521eb-127d-4a9f-b4a2-37241250542d | 알림 메시지 | WRITE |
| Navigation Tips | 0d240db6-0e0c-43fe-a250-8244b3989faa | 네비게이션 | WRITE |

**중요**: RunVision-IQ는 **Exercise Data Characteristic만 사용**합니다.

---

## 3. 운동 데이터 프로토콜

### 3.1 Characteristic UUID

```
Service UUID: 4b329cf2-3816-498c-8453-ee8798502a08
Characteristic UUID: c259c1bd-18d3-c348-b88d-5447aea1b615
```

### 3.2 데이터 구조

각 메트릭은 **개별적으로** 전송됩니다:

```
[id(1 byte)] [data(4 bytes for UINT32 or variable)]
```

### 3.3 메트릭 ID 목록

| ID | 메트릭 | 데이터 타입 | 단위 | 설명 |
|----|--------|------------|------|------|
| 0x00 | UI Sorting | data(20) | - | 화면 배치 순서 (10개 항목) |
| 0x01 | Record Status | UINT32 | - | 0: Start, 1: Pause, 2: End |
| 0x02 | Heat Dissipation | UINT32 | kcal | 칼로리 소모 |
| 0x03 | Exercise Time | UINT32 | seconds | 운동 시간 |
| 0x04 | Total Time | UINT32 | seconds | 전체 시간 |
| 0x05 | Pause Time | UINT32 | seconds | 일시정지 시간 |
| **0x06** | **Movement Distance** | **UINT32** | **meters** | **이동 거리** ⭐ |
| **0x07** | **Velocity** | **UINT32** | **km/h** | **현재 속도** ⭐ |
| 0x08 | Average Movement Speed | UINT32 | km/h | 평균 이동 속도 |
| 0x09 | Average Speed | UINT32 | km/h | 평균 속도 |
| 0x0A | Maximum Speed | UINT32 | km/h | 최대 속도 |
| **0x0B** | **Real-time Heart Rate** | **UINT32** | **bpm** | **실시간 심박수** ⭐ |
| 0x0C | Average Heart Rate | UINT32 | bpm | 평균 심박수 |
| 0x0D | Maximum Heart Rate | UINT32 | bpm | 최대 심박수 |
| **0x0E** | **Current Cadence** | **UINT32** | **spm** | **현재 케이던스** ⭐ |
| 0x0F | Maximum Cadence | UINT32 | spm | 최대 케이던스 |
| 0x10 | Average Cadence | UINT32 | spm | 평균 케이던스 |
| 0x11 | Current Power Rate | UINT32 | watts | 현재 파워 |
| 0x12 | Maximum Power Rate | UINT32 | watts | 최대 파워 |
| 0x13 | Average Power Rate | UINT32 | watts | 평균 파워 |
| 0x14 | Current Orientation | UINT8 | - | 방향 (0-3: 동남서북, 4-7: 북동남서북서) |
| 0x15 | Current Road Name | data(n) | UTF-8 | 현재 도로 이름 |

**RunVision-IQ 핵심 메트릭** (4개):
- ✅ 0x07: Velocity (속도)
- ✅ 0x06: Distance (거리)
- ✅ 0x0B: Heart Rate (심박수)
- ✅ 0x0E: Cadence (케이던스)

---

## 4. 데이터 인코딩 방식

### 4.1 UINT32 인코딩 (Little-Endian)

**UINT32는 4 bytes, Little-Endian 순서**:

```
예: 속도 = 12.5 km/h (정수로 변환 필요)

iLens는 정수만 받으므로:
- 방법 1: 12 km/h (소수점 버림)
- 방법 2: 125 (10배 스케일) - 권장

UINT32 = 125
Little-Endian: [0x7D, 0x00, 0x00, 0x00]

전체 페이로드:
[0x07] [0x7D] [0x00] [0x00] [0x00]
```

### 4.2 Connect IQ 인코딩 함수

```monkey-c
function encodeUInt32LittleEndian(value) {
    var bytes = new [4]b;
    bytes[0] = (value & 0xFF);
    bytes[1] = ((value >> 8) & 0xFF);
    bytes[2] = ((value >> 16) & 0xFF);
    bytes[3] = ((value >> 24) & 0xFF);
    return bytes;
}

// 사용 예
var speed = 125; // 12.5 km/h * 10
var speedBytes = encodeUInt32LittleEndian(speed);
// speedBytes = [0x7D, 0x00, 0x00, 0x00]
```

### 4.3 Float to UINT32 변환 전략

iLens는 **UINT32만 지원**하므로, Float 값을 정수로 변환해야 합니다:

**Option 1: 스케일 팩터 사용 (권장)**
```monkey-c
// 속도: 12.5 km/h → 125 (10배)
var speedInt = (speed * 10).toNumber();

// 거리: 5.432 km → 5432 (1000배, meters로 변환)
var distanceMeters = (distance * 1000).toNumber();

// 심박수: 145 bpm (이미 정수)
var heartRate = heartRate.toNumber();

// 케이던스: 176 spm (이미 정수)
var cadence = cadence.toNumber();
```

**Option 2: 단위 변환**
```monkey-c
// 거리는 meters로 전송 (UINT32)
var distanceMeters = (elapsedDistance).toNumber(); // Activity.Info는 이미 meters

// 속도는 km/h로 전송 (정수 부분만)
var speedKmh = (currentSpeed * 3.6).toNumber(); // m/s → km/h
```

---

## 5. RunVision-IQ 구현 명세

### 5.1 BLE Manager 구조

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

class ILensBleManager extends BluetoothLowEnergy.BleDelegate {

    // Service & Characteristic UUIDs
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
}
```

### 5.2 스캔 및 연결

```monkey-c
class ILensBleManager {

    function requestScanning() {
        if (!_profileRegistered) {
            setUp();
            return;
        }
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function onScanResults(scanResults) {
        for (var i = 0; i < scanResults.size(); i++) {
            var result = scanResults[i];

            // Device Name으로 필터링 (간단한 방법)
            var deviceName = result.getDeviceName();
            if (deviceName != null && deviceName.find("iLens") != null) {
                _foundDevices.add(result);
            }
        }
    }

    function connect(device) {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        BluetoothLowEnergy.pairDevice(device);
    }

    function onConnectedStateChanged(device, state) {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _device = device;

            // Characteristic 얻기 (재시도 로직)
            _exerciseCharacteristic = getExerciseCharacteristic();
        } else {
            _device = null;
            _exerciseCharacteristic = null;
        }
    }

    function getExerciseCharacteristic() {
        return tryGetCharacteristic(SERVICE_UUID, EXERCISE_DATA_CHAR_UUID, 5);
    }

    function tryGetCharacteristic(serviceUuid, charUuid, maxRetries) {
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

### 5.3 데이터 전송

```monkey-c
class ILensBleManager {

    function sendMetrics(speed, distance, heartRate, cadence) {
        if (_exerciseCharacteristic == null) {
            return false;
        }

        // 각 메트릭 개별 전송
        sendMetric(0x07, speed);       // Velocity (km/h)
        sendMetric(0x06, distance);    // Distance (meters)
        sendMetric(0x0B, heartRate);   // Heart Rate (bpm)
        sendMetric(0x0E, cadence);     // Cadence (spm)

        return true;
    }

    function sendMetric(metricId, value) {
        if (_exerciseCharacteristic == null) {
            return;
        }

        // 페이로드 생성: [id(1)] + [value(4, Little-Endian)]
        var payload = new [5]b;
        payload[0] = metricId;

        // UINT32 Little-Endian 인코딩
        var valueInt = value.toNumber();
        payload[1] = (valueInt & 0xFF);
        payload[2] = ((valueInt >> 8) & 0xFF);
        payload[3] = ((valueInt >> 16) & 0xFF);
        payload[4] = ((valueInt >> 24) & 0xFF);

        // 전송
        _exerciseCharacteristic.requestWrite(payload, {
            :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
        });
    }
}
```

### 5.4 DataField compute() 통합

```monkey-c
class RunVisionIQView extends WatchUi.DataField {

    function compute(info) {
        // 1. iLens 기능 비활성화 시 스킵
        if (!_ilensEnabled || _autoDisabled) {
            return;
        }

        // 2. BLE Manager 얻기
        var ble = ILens.getBleManager();

        // 3. 연결되어 있으면 데이터 전송
        if (ble.isConnected()) {
            sendDataToILens(info);
        } else {
            // 4. 연결 안 되어 있으면 스캔 시도
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

        // Activity.Info에서 데이터 추출
        var speed = info.currentSpeed;         // m/s
        var distance = info.elapsedDistance;   // m
        var heartRate = info.currentHeartRate; // bpm (null 가능)
        var cadence = info.currentCadence;     // spm (null 가능)

        // 단위 변환
        var speedKmh = (speed != null) ? (speed * 3.6).toNumber() : 0;
        var distanceMeters = (distance != null) ? distance.toNumber() : 0;
        var hr = (heartRate != null) ? heartRate.toNumber() : 0;
        var cad = (cadence != null) ? cadence.toNumber() : 0;

        // iLens로 전송
        ble.sendMetrics(speedKmh, distanceMeters, hr, cad);
    }
}
```

### 5.5 세션 상태 관리

```monkey-c
class RunVisionIQView extends WatchUi.DataField {

    function onTimerStart() {
        var ble = ILens.getBleManager();
        // 세션 시작 (Record Status = 0)
        ble.sendMetric(0x01, 0);
    }

    function onTimerPause() {
        var ble = ILens.getBleManager();
        // 세션 일시정지 (Record Status = 1)
        ble.sendMetric(0x01, 1);
    }

    function onTimerResume() {
        var ble = ILens.getBleManager();
        // 세션 재개 (Record Status = 0)
        ble.sendMetric(0x01, 0);
    }

    function onTimerStop() {
        var ble = ILens.getBleManager();
        // 세션 종료 (Record Status = 2)
        ble.sendMetric(0x01, 2);
    }
}
```

---

## 6. 데이터 포맷 예시

### 6.1 속도 전송 (12.5 km/h)

```
메트릭 ID: 0x07 (Velocity)
값: 12.5 km/h → 12 (정수)

페이로드:
[0x07] [0x0C] [0x00] [0x00] [0x00]
  ↑     ↑---- UINT32 = 12 (Little-Endian)
  ↑
  메트릭 ID
```

### 6.2 거리 전송 (5432 meters)

```
메트릭 ID: 0x06 (Distance)
값: 5432 meters

UINT32 = 5432 = 0x00001538
Little-Endian: [0x38, 0x15, 0x00, 0x00]

페이로드:
[0x06] [0x38] [0x15] [0x00] [0x00]
```

### 6.3 심박수 전송 (145 bpm)

```
메트릭 ID: 0x0B (Heart Rate)
값: 145 bpm

UINT32 = 145 = 0x00000091
Little-Endian: [0x91, 0x00, 0x00, 0x00]

페이로드:
[0x0B] [0x91] [0x00] [0x00] [0x00]
```

### 6.4 케이던스 전송 (176 spm)

```
메트릭 ID: 0x0E (Cadence)
값: 176 spm

UINT32 = 176 = 0x000000B0
Little-Endian: [0xB0, 0x00, 0x00, 0x00]

페이로드:
[0x0E] [0xB0] [0x00] [0x00] [0x00]
```

---

## 7. 에러 처리

### 7.1 Null 값 처리

```monkey-c
function sendDataToILens(info) {
    var ble = ILens.getBleManager();

    // Activity.Info 값은 null일 수 있음
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

### 7.2 BLE 전송 실패 처리

```monkey-c
function sendMetric(metricId, value) {
    if (_exerciseCharacteristic == null) {
        return false;
    }

    try {
        var payload = new [5]b;
        payload[0] = metricId;

        var valueInt = value.toNumber();
        payload[1] = (valueInt & 0xFF);
        payload[2] = ((valueInt >> 8) & 0xFF);
        payload[3] = ((valueInt >> 16) & 0xFF);
        payload[4] = ((valueInt >> 24) & 0xFF);

        _exerciseCharacteristic.requestWrite(payload, {
            :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
        });

        return true;
    } catch (e) {
        System.println("BLE write failed: " + e.getErrorMessage());
        return false;
    }
}
```

---

## 8. 성능 고려사항

### 8.1 전송 빈도

**DataField compute() 호출 주기**: 약 50ms (20Hz)

**iLens 전송 전략**:
- **Option 1**: 매 compute()마다 전송 (20Hz) - 배터리 소모 높음
- **Option 2**: 1Hz로 제한 (권장) - 배터리 효율적

```monkey-c
class RunVisionIQView extends WatchUi.DataField {

    private var _lastSendTime = 0;
    private const SEND_INTERVAL_MS = 1000; // 1Hz

    function compute(info) {
        var now = System.getTimer();

        // 1초마다만 전송
        if (now - _lastSendTime < SEND_INTERVAL_MS) {
            return;
        }

        if (ble.isConnected()) {
            sendDataToILens(info);
            _lastSendTime = now;
        }
    }
}
```

### 8.2 배터리 최적화

**배터리 소모 요인**:
1. BLE 스캔 (높음)
2. BLE 연결 유지 (중간)
3. BLE 데이터 전송 (낮음)

**최적화 전략**:
- ✅ 스캔 시도 3회로 제한
- ✅ 연결 실패 시 자동 비활성화
- ✅ 데이터 전송 1Hz로 제한
- ✅ Settings OFF 시 BLE 완전 비활성화

---

## 9. 정리

### 9.1 핵심 사항

1. **Service UUID**: `4b329cf2-3816-498c-8453-ee8798502a08`
2. **Characteristic UUID**: `c259c1bd-18d3-c348-b88d-5447aea1b615`
3. **데이터 포맷**: `[id(1)] + [UINT32(4, Little-Endian)]`
4. **핵심 메트릭**: 속도(0x07), 거리(0x06), 심박수(0x0B), 케이던스(0x0E)
5. **전송 주기**: 1Hz (1초마다)

### 9.2 구현 체크리스트

- [ ] BLE Manager 싱글톤 패턴
- [ ] 프로필 등록 (1개)
- [ ] 스캔 필터링 (Device Name)
- [ ] 연결 재시도 로직 (5회)
- [ ] UINT32 Little-Endian 인코딩
- [ ] 4개 메트릭 전송 (속도, 거리, 심박수, 케이던스)
- [ ] 1Hz 전송 제한
- [ ] Null 값 처리
- [ ] 자동 연결 관리 (3회 시도 후 자동 비활성화)
- [ ] Settings ON/OFF

---

**문서 작성**: 2025-11-15
**다음 단계**: ActiveLook 코드 상세 분석
**승인 상태**: 승인 대기 중

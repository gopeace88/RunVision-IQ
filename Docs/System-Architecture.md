# RunVision-IQ - System Architecture (v3.0)

**버전**: 3.0
**작성일**: 2025-11-15
**최종 수정일**: 2025-11-15
**작성자**: Development Team
**상태**: Ready for Implementation
**기반**: ActiveLook 100% Copy + BLE Layer Replacement

---

## 📋 문서 개요

본 문서는 RunVision-IQ의 시스템 아키텍처를 정의합니다.

**핵심 전략**:
- ✅ **ActiveLook 100% 복사**: 검증된 DataField 아키텍처 완전 재사용
- ✅ **BLE 레이어만 교체**: 2개 모듈 (`ActiveLook.mc` → `ILens.mc`, `ActiveLookSDK_next.mc` → `ILensProtocol.mc`)
- ✅ **나머지 5개 모듈 재사용**: DataFieldView, ActivityInfo, Properties, Strings, Settings
- ✅ **파워 계산 유지**: 3-Second Power, Normalized Power (ActiveLook 로직)
- ✅ **Auto-Pairing 유지**: properties.xml 기반 자동 기기 저장

**참조 문서**:
- `PRD-RunVision-IQ.md` v3.0 - 제품 요구사항
- `ActiveLook-Source-Analysis-Complete.md` - ActiveLook 완전 분석
- `iLens-BLE-Protocol-Analysis.md` - iLens 프로토콜 분석

---

## 1. 시스템 개요

### 1.1 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────┐
│                   Garmin Run/Bike App                       │
│                (Host Activity Application)                   │
└────────────┬────────────────────────────────────────────────┘
             │ compute(info) 50ms
             │ onTimerStart/Pause/Stop
             ↓
┌─────────────────────────────────────────────────────────────┐
│          RunVisionIQView (DataField)                        │
│          ← ActiveLookDataFieldView.mc (100% 복사)           │
├─────────────────────────────────────────────────────────────┤
│  - initialize()                                             │
│  - compute(info)         → 1Hz Throttling                   │
│  - onUpdate(dc)          → UI (선택)                        │
│  - onTimerStart/Pause/Stop → Record Status                  │
└────────────┬────────────────────────────────────────────────┘
             │
             ├─────────────┐
             │             │
             ↓             ↓
┌──────────────────┐  ┌──────────────────────────┐
│  ActivityInfo    │  │   ILens Singleton        │
│  ← ActiveLook    │  │   ← ActiveLook.mc        │
│     100% 복사    │  │   (BLE 레이어 교체)      │
├──────────────────┤  ├──────────────────────────┤
│ - accumulate()   │  │ - setUp()                │
│ - getThreeSec    │  │ - requestScanning()      │
│ - getNormalized  │  │ - onScanResult()         │
│                  │  │   * Auto-Pairing 로직    │
│ Power 계산       │  │ - pairDevice()           │
│ (30-sample)      │  │ - sendMetric()           │
└──────────────────┘  └────────────┬─────────────┘
                                   │
                                   ↓
                      ┌────────────────────────────┐
                      │  ILensProtocol             │
                      │  ← ActiveLookSDK_next.mc   │
                      │  (프로토콜 레이어 교체)     │
                      ├────────────────────────────┤
                      │ - sendMetric(id, value)    │
                      │   * iLens 바이너리 포맷    │
                      │   * [ID, UINT32 LE]        │
                      │                            │
                      │ 제거:                      │
                      │ - commandBuffer()          │
                      │   (ActiveLook 텍스트)      │
                      └────────────┬───────────────┘
                                   │ BLE Write
                                   ↓
                      ┌────────────────────────────┐
                      │      iLens AR 글래스        │
                      │  (BLE Peripheral)          │
                      ├────────────────────────────┤
                      │ Service UUID:              │
                      │  4b329cf2-3816-...         │
                      │ Exercise Char UUID:        │
                      │  c259c1bd-18d3-...         │
                      │                            │
                      │ 수신 메트릭 (7개):         │
                      │ - Velocity (0x07)          │
                      │ - Distance (0x06)          │
                      │ - Heart Rate (0x0B)        │
                      │ - Cadence (0x0E)           │
                      │ - 3-Sec Power (0x11)       │
                      │ - Normalized Power (0x12)  │
                      │ - Instant Power (0x13)     │
                      └────────────────────────────┘
```

### 1.2 아키텍처 원칙

**Principle 1: Proven Architecture Reuse**
- ActiveLook의 검증된 DataField 아키텍처 100% 복사
- 3년간 실전 검증된 안정성 (크래시율 <0.1%)
- Monkey C 언어 Best Practice 준수

**Principle 2: Minimal Modification**
- 오직 BLE 레이어만 교체 (2개 모듈)
- 나머지 5개 모듈 변경 없음
- 테스트 및 디버깅 범위 최소화

**Principle 3: Separation of Concerns**
- DataFieldView: UI 및 라이프사이클 관리
- ActivityInfo: 메트릭 계산 (파워 포함)
- ILens/ILensProtocol: BLE 연결 및 전송
- Properties/Strings/Settings: 설정 및 다국어

**Principle 4: Single Responsibility**
- 각 모듈은 하나의 책임만 담당
- BLE 연결: ILens.mc
- BLE 프로토콜: ILensProtocol.mc
- 파워 계산: ActivityInfo.mc

---

## 2. 모듈 구성

### 2.1 모듈 개요

| 모듈 | 소스 파일 | ActiveLook 대응 | 교체 여부 | 라인 수 | 역할 |
|------|----------|----------------|----------|---------|------|
| **DataFieldView** | `RunVisionIQView.mc` | `ActiveLookDataFieldView.mc` | ❌ **복사** | ~600 | 메인 DataField, 라이프사이클 |
| **ActivityInfo** | `RunVisionIQActivityInfo.mc` | `ActiveLookActivityInfo.mc` | ❌ **복사** | ~900 | 메트릭 계산, 파워 통계 |
| **ILens** | `ILens.mc` | `ActiveLook.mc` | ✅ **교체** | ~500 | BLE 연결, Auto-Pairing |
| **ILensProtocol** | `ILensProtocol.mc` | `ActiveLookSDK_next.mc` | ✅ **교체** | ~300 | iLens BLE 프로토콜 |
| **Properties** | `properties.xml` | `properties.xml` | ❌ **복사** | ~10 | 설정 (ilens_name 등) |
| **Strings** | `strings.xml` | `strings.xml` | ❌ **복사** | ~50 | 다국어 (한/영) |
| **Settings** | `settings.xml` | `settings.xml` | ❌ **복사** | ~30 | Settings UI |

**총 라인 수**: ~2,390 lines
**교체 비율**: 800 lines / 2,390 lines = **33%**
**재사용 비율**: 1,590 lines / 2,390 lines = **67%**

### 2.2 모듈별 상세 설명

#### 2.2.1 DataFieldView (메인 모듈, ActiveLook 100% 복사)

**파일**: `source/RunVisionIQView.mc` ← `ActiveLookDataFieldView.mc`

**책임**:
- DataField 라이프사이클 관리 (initialize, compute, onUpdate)
- Timer Event 처리 (onTimerStart/Pause/Stop)
- Activity.Info 데이터 추출
- 1Hz Throttling
- UI 렌더링 (선택)

**주요 메서드**:
```monkey-c
class RunVisionIQView extends WatchUi.DataField {
    // ActiveLook과 동일
    function initialize() {
        DataField.initialize();
        $.ilensName = Application.Properties.getValue("ilens_name");
        $.ilensEnabled = Application.Properties.getValue("ilens_enabled");

        if ($.ilensEnabled) {
            ILens.getInstance().setUp();
        }

        _activityInfo = new RunVisionIQActivityInfo();
    }

    // ActiveLook과 동일
    function compute(info) {
        if (info == null) { return; }

        // 파워 계산 (ActiveLook 로직)
        _activityInfo.accumulate(info);

        // Throttling (1Hz)
        var now = System.getTimer();
        if (now - _lastSendTime < _sendIntervalMs) { return; }
        _lastSendTime = now;

        // Activity.Info 추출
        var speed = extractSpeed(info);
        var distance = extractDistance(info);
        var heartRate = extractHeartRate(info);
        var cadence = extractCadence(info);

        // 파워 메트릭
        var threeSecPower = _activityInfo.getThreeSecPower();
        var normalizedPower = _activityInfo.getNormalizedPower();
        var power = extractPower(info);

        // iLens 전송
        var ilens = ILens.getInstance();
        if (ilens.isConnected()) {
            ilens.sendMetric(0x07, speed);
            ilens.sendMetric(0x06, distance);
            ilens.sendMetric(0x0B, heartRate);
            ilens.sendMetric(0x0E, cadence);

            if (threeSecPower != null) { ilens.sendMetric(0x11, threeSecPower); }
            if (normalizedPower != null) { ilens.sendMetric(0x12, normalizedPower); }
            if (power != null) { ilens.sendMetric(0x13, power); }
        }
    }

    // ActiveLook과 동일
    function onTimerStart() {
        DataField.onTimerStart();
        ILens.getInstance().sendMetric(0x01, 0);  // Start
    }

    function onTimerPause() {
        DataField.onTimerPause();
        ILens.getInstance().sendMetric(0x01, 1);  // Pause
    }

    function onTimerStop() {
        DataField.onTimerStop();
        ILens.getInstance().sendMetric(0x01, 2);  // Stop
    }

    // ActiveLook과 동일 (선택)
    function onUpdate(dc) {
        // 최소 구현: 호스트 앱이 메트릭 표시
        // 또는 iLens 연결 상태 표시
    }
}
```

**변경 사항**: ❌ **없음** (ActiveLook 100% 재사용)

#### 2.2.2 ActivityInfo (파워 계산, ActiveLook 100% 복사)

**파일**: `source/RunVisionIQActivityInfo.mc` ← `ActiveLookActivityInfo.mc`

**책임**:
- Activity.Info에서 파워 데이터 수집
- 30-sample buffer 관리
- 3-Second Power 계산 (최근 6 샘플 평균)
- Normalized Power 계산 (`(avg(power^4))^(1/4)`)

**주요 메서드**:
```monkey-c
class RunVisionIQActivityInfo {
    // ActiveLook과 동일
    private var __pSamples = new [30];   // 30-sample buffer
    private var __pAccu = 0.0;           // Sum of (avg30)^4
    private var __pAccuNb = 0;           // Accumulated count

    // ActiveLook과 동일
    function accumulate(info) {
        if (info == null || info.currentPower == null) { return; }

        var power = info.currentPower;
        __pSamples.add(power);

        if (__pSamples.size() >= 30) {
            __pSamples = __pSamples.slice(-30, null);

            var tmp = 0;
            for(var i = 0; i < 30; i++) {
                tmp += __pSamples[i];
            }
            var avg30 = tmp / 30.0;

            __pAccu += Math.pow(avg30, 4);
            __pAccuNb++;
        }
    }

    // ActiveLook과 동일
    function getThreeSecPower() {
        if (__pSamples.size() >= 6) {
            var tmp = __pSamples.slice(-6, null);
            return (tmp[0] + tmp[1] + tmp[2] + tmp[3] + tmp[4] + tmp[5]) / 6.0;
        }
        return null;
    }

    // ActiveLook과 동일
    function getNormalizedPower() {
        if (__pAccuNb > 0) {
            return Math.pow(__pAccu / __pAccuNb, 0.25);
        }
        return null;
    }
}
```

**변경 사항**: ❌ **없음** (ActiveLook 100% 재사용)

#### 2.2.3 ILens (BLE 연결, ActiveLook → iLens 교체)

**파일**: `source/ILens.mc` ← `ActiveLook.mc` (교체)

**책임**:
- BLE Profile 등록 (Service UUID: iLens)
- iLens 스캔 및 연결
- **Auto-Pairing** (첫 발견 기기 자동 저장)
- Characteristic 획득
- 연결 상태 관리

**주요 메서드**:
```monkey-c
module ILens {
    // Singleton instance
    private var _instance = null;

    function getInstance() {
        if (_instance == null) {
            _instance = new ILensManager();
        }
        return _instance;
    }
}

class ILensManager {
    // iLens UUID (ActiveLook과 다름)
    private const SERVICE_UUID = BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08");
    private const EXERCISE_CHAR_UUID = BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615");

    private var _profileRegistered = false;
    private var _device = null;
    private var _exerciseCharacteristic = null;

    // ActiveLook과 동일
    function setUp() {
        if (_profileRegistered) { return; }

        BluetoothLowEnergy.setDelegate(self);
        var profile = {
            :uuid => SERVICE_UUID,
            :characteristics => [
                { :uuid => EXERCISE_CHAR_UUID }
            ]
        };
        BluetoothLowEnergy.registerProfile(profile);
        _profileRegistered = true;

        requestScanning();
    }

    // ActiveLook과 동일
    function requestScanning() {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    // ActiveLook 패턴 재사용 (Auto-Pairing)
    function onScanResult(scanResult) {
        var deviceName = scanResult.getDeviceName();
        if (deviceName == null) { deviceName = ""; }

        // Auto-save first discovered device
        if ($.ilensName.equals("")) {
            Application.Properties.setValue("ilens_name", deviceName);
            $.ilensName = deviceName;
        }
        // Only connect to saved device
        else if (!$.ilensName.equals(deviceName)) {
            return;  // Skip other devices
        }

        // Connect to iLens
        BluetoothLowEnergy.pairDevice(scanResult);
    }

    // ActiveLook과 동일
    function onConnectedStateChanged(device, state) {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _device = device;
            tryGetCharacteristic(5);  // 5회 재시도
        } else {
            _device = null;
            _exerciseCharacteristic = null;
            requestScanning();  // 재연결
        }
    }

    // ActiveLook과 동일
    function tryGetCharacteristic(attempts) {
        if (attempts <= 0) { return; }

        var service = _device.getService(SERVICE_UUID);
        if (service == null) {
            // Retry after 500ms
            var timer = new Timer.Timer();
            timer.start(method(:tryGetCharacteristic), 500, false);
            timer.setParameter(attempts - 1);
            return;
        }

        _exerciseCharacteristic = service.getCharacteristic(EXERCISE_CHAR_UUID);
    }

    // ActiveLook과 동일
    function isConnected() {
        return _device != null && _exerciseCharacteristic != null;
    }

    // iLens 프로토콜 사용 (ILensProtocol에 위임)
    function sendMetric(metricId, value) {
        if (!isConnected()) { return; }
        ILensProtocol.sendMetric(_exerciseCharacteristic, metricId, value);
    }
}
```

**변경 사항**:
- ✅ Service UUID 변경: ActiveLook → iLens
- ✅ Characteristic UUID 변경
- ✅ Auto-Pairing 로직 유지 (`ilens_name` property)
- ✅ sendMetric() → ILensProtocol에 위임

#### 2.2.4 ILensProtocol (BLE 프로토콜, ActiveLookSDK → iLens 교체)

**파일**: `source/ILensProtocol.mc` ← `ActiveLookSDK_next.mc` (교체)

**책임**:
- iLens BLE 프로토콜 구현
- 바이너리 페이로드 생성 (5 bytes)
- BLE Write 실행

**주요 메서드**:
```monkey-c
module ILensProtocol {
    // iLens 바이너리 프로토콜 (ActiveLook 텍스트 프로토콜과 다름)
    function sendMetric(characteristic, metricId, value) {
        var payload = new [5]b;
        payload[0] = metricId;

        var valueInt = value.toNumber();
        payload[1] = (valueInt & 0xFF);
        payload[2] = ((valueInt >> 8) & 0xFF);
        payload[3] = ((valueInt >> 16) & 0xFF);
        payload[4] = ((valueInt >> 24) & 0xFF);

        try {
            characteristic.requestWrite(payload, {
                :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
            });
        } catch (ex) {
            (:debug) System.println("BLE Write failed: " + ex.getErrorMessage());
        }
    }
}
```

**변경 사항**:
- ✅ ActiveLook 텍스트 프로토콜 제거
- ✅ iLens 바이너리 프로토콜 구현 (5 bytes)
- ✅ commandBuffer() 제거 (ActiveLook 전용)
- ✅ Little-Endian UINT32 변환 추가

**제거된 ActiveLook 메서드**:
- `commandBuffer(id, data)` - 텍스트 프로토콜 버퍼 생성
- `setText(x, y, text)` - 텍스트 레이아웃 명령
- `setLayout(id)` - 레이아웃 변경 명령
- `setBrightness(level)` - 밝기 조절 명령

#### 2.2.5 Properties (설정, ActiveLook 100% 복사)

**파일**: `resources/settings/properties.xml` ← `properties.xml`

**내용**:
```xml
<properties>
    <property id="ilens_name" type="string">
        <default></default>  <!-- Empty: auto-save first -->
    </property>
    <property id="ilens_enabled" type="boolean">
        <default>true</default>
    </property>
</properties>
```

**변경 사항**:
- ✅ `glasses_name` → `ilens_name` (이름만 변경)
- ❌ 나머지 동일 (ActiveLook 패턴 재사용)

#### 2.2.6 Strings (다국어, ActiveLook 100% 복사)

**파일**: `resources/strings/strings.xml` ← `strings.xml`

**내용**:
```xml
<strings>
    <string id="AppName">RunVision-IQ</string>
    <string id="Connecting">Connecting...</string>
    <string id="Connected">Connected</string>
    <string id="Disconnected">Disconnected</string>
</strings>
```

**변경 사항**:
- ✅ `AppName` 변경: "ActiveLook" → "RunVision-IQ"
- ❌ 나머지 동일

#### 2.2.7 Settings (UI, ActiveLook 100% 복사)

**파일**: `resources/settings/settings.xml` ← `settings.xml`

**내용**: ActiveLook과 동일 (Garmin Connect Mobile Settings UI)

**변경 사항**: ❌ **없음**

---

## 3. BLE 레이어 교체 전략

### 3.1 교체 범위

| 계층 | ActiveLook | RunVision-IQ | 변경 |
|------|-----------|--------------|------|
| **Application** | DataFieldView | RunVisionIQView | ❌ 복사 |
| **Business Logic** | ActivityInfo | RunVisionIQActivityInfo | ❌ 복사 |
| **BLE Connection** | ActiveLook.mc | **ILens.mc** | ✅ **교체** |
| **BLE Protocol** | ActiveLookSDK_next.mc | **ILensProtocol.mc** | ✅ **교체** |
| **Configuration** | properties.xml | properties.xml | ❌ 복사 |
| **Localization** | strings.xml | strings.xml | ❌ 복사 |
| **Settings UI** | settings.xml | settings.xml | ❌ 복사 |

### 3.2 교체 상세 (ActiveLook → iLens)

#### 3.2.1 BLE UUID 변경

**ActiveLook**:
```monkey-c
// ActiveLook Service UUID
private const SERVICE_UUID = BluetoothLowEnergy.stringToUuid("0783b03e-8535-b5a0-7140-a304d2495cb7");

// ActiveLook Characteristic UUIDs
private const TX_CHAR_UUID = BluetoothLowEnergy.stringToUuid("0783b03e-8535-b5a0-7140-a304d2495cb8");
private const RX_CHAR_UUID = BluetoothLowEnergy.stringToUuid("0783b03e-8535-b5a0-7140-a304d2495cba");
```

**iLens**:
```monkey-c
// iLens Service UUID
private const SERVICE_UUID = BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08");

// iLens Exercise Characteristic UUID
private const EXERCISE_CHAR_UUID = BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615");
```

#### 3.2.2 프로토콜 변경

**ActiveLook 프로토콜** (텍스트 기반):
```
Format: [0xFF, cmd, 0x00, len, data..., 0xAA]
Example: setText(10, 20, "12.5km")
  → [0xFF, 0x37, 0x00, 0x0B, 0x0A, 0x00, 0x14, 0x00, '1', '2', '.', '5', 'k', 'm', 0xAA]
```

**iLens 프로토콜** (바이너리):
```
Format: [Metric_ID, UINT32 Little-Endian]
Example: sendMetric(0x07, 85)  // 8.5 km/h
  → [0x07, 0x55, 0x00, 0x00, 0x00]
```

#### 3.2.3 Auto-Pairing 로직 유지

**ActiveLook**:
```monkey-c
function onScanResult(scanResult) {
    var deviceName = scanResult.getDeviceName();
    var glassesArray = $.sdk.splitString($.glassesName, ",");
    if (scanResult.getDeviceName() == null) { deviceName = ""; }
    if ($.glassesName.equals("")) {
        Application.Properties.setValue("glasses_name", deviceName);
        $.glassesName = deviceName;
    } else if (glassesArray.indexOf(deviceName) < 0) { return; }
    $.sdk.connect(scanResult);
}
```

**iLens** (동일 로직):
```monkey-c
function onScanResult(scanResult) {
    var deviceName = scanResult.getDeviceName();
    if (deviceName == null) { deviceName = ""; }
    if ($.ilensName.equals("")) {
        Application.Properties.setValue("ilens_name", deviceName);
        $.ilensName = deviceName;
    } else if (!$.ilensName.equals(deviceName)) { return; }
    BluetoothLowEnergy.pairDevice(scanResult);
}
```

### 3.3 교체 검증 체크리스트

- [ ] Service UUID 변경 확인
- [ ] Characteristic UUID 변경 확인
- [ ] Auto-Pairing 로직 동일 확인
- [ ] iLens 바이너리 프로토콜 구현 확인
- [ ] ActiveLook 텍스트 프로토콜 제거 확인
- [ ] 7개 메트릭 전송 로직 확인
- [ ] BLE Write 에러 처리 확인
- [ ] 연결/재연결 로직 동일 확인

---

## 4. 데이터 흐름

### 4.1 전체 데이터 흐름

```
Garmin OS (Run App)
         │
         │ compute(info) 50ms (20Hz)
         ↓
┌────────────────────────────┐
│  RunVisionIQView.compute() │
└─────────────┬──────────────┘
              │
              ├─────────────────┐
              │                 │
              ↓                 ↓
     ┌────────────────┐  ┌──────────────────┐
     │ ActivityInfo   │  │ Activity.Info    │
     │ .accumulate()  │  │ 추출:            │
     │                │  │ - currentSpeed   │
     │ 파워 계산:     │  │ - elapsedDistance│
     │ - 30-sample    │  │ - currentHeartRate│
     │ - 3-sec avg    │  │ - currentCadence │
     │ - normalized   │  │ - currentPower   │
     └────────┬───────┘  └─────────┬────────┘
              │                     │
              └──────────┬──────────┘
                         │
                         ↓ Throttling (1Hz)
              ┌──────────────────────┐
              │ ILens.sendMetric()   │
              └──────────┬───────────┘
                         │
                         ↓
              ┌──────────────────────────┐
              │ ILensProtocol.sendMetric()│
              │ → 바이너리 페이로드 생성  │
              └──────────┬───────────────┘
                         │ BLE Write
                         ↓
              ┌──────────────────────┐
              │   iLens AR 글래스     │
              │ (7개 메트릭 수신)     │
              └──────────────────────┘
```

### 4.2 Throttling 로직 (ActiveLook 재사용)

**목적**: compute() 20Hz → BLE 전송 1Hz 감소

**구현**:
```monkey-c
private var _lastSendTime = 0;
private var _sendIntervalMs = 1000;  // 1Hz

function compute(info) {
    // ... (파워 계산 등)

    // Throttling
    var now = System.getTimer();
    if (now - _lastSendTime < _sendIntervalMs) {
        return;  // Skip this cycle
    }
    _lastSendTime = now;

    // BLE 전송 (1Hz)
    sendMetrics();
}
```

### 4.3 파워 계산 흐름 (ActiveLook 재사용)

```
compute(info) 20Hz
     │
     ↓
ActivityInfo.accumulate(info)
     │
     ├─ __pSamples.add(power)           // 30-sample buffer
     │
     ├─ if (size >= 30):
     │     avg30 = sum(__pSamples) / 30
     │     __pAccu += pow(avg30, 4)     // Normalized Power 누적
     │     __pAccuNb++
     │
     ↓ (1Hz 전송 시)
     │
     ├─ getThreeSecPower()
     │    → last 6 samples avg
     │
     ├─ getNormalizedPower()
     │    → pow(__pAccu / __pAccuNb, 0.25)
     │
     ↓
sendMetric(0x11, threeSecPower)
sendMetric(0x12, normalizedPower)
sendMetric(0x13, power)
```

---

## 5. 상태 관리

### 5.1 BLE 연결 상태 (ActiveLook State Machine 재사용)

```
┌─────────────────────────────────────────────────────────┐
│                  BLE Connection State                    │
└─────────────────────────────────────────────────────────┘

     [Idle]
       │
       │ setUp()
       ↓
     [Profile Registered]
       │
       │ requestScanning()
       ↓
     [Scanning]
       │
       │ onScanResult(device)
       │ + Auto-Pairing 체크
       ↓
     [Pairing]
       │
       │ onConnectedStateChanged(CONNECTED)
       ↓
     [Connected]
       │
       │ tryGetCharacteristic()
       ↓
     [Characteristic Ready]
       │
       │ sendMetric() 가능
       ↓
     [Transmitting]
       │
       │ onConnectedStateChanged(DISCONNECTED)
       ↓
     [Disconnected]
       │
       │ requestScanning() (자동 재연결)
       └──────────────→ [Scanning]
```

### 5.2 Auto-Pairing 상태 (ActiveLook 패턴 재사용)

```
ilensName (Property)
     │
     ├─ "" (빈 문자열)
     │    │
     │    │ onScanResult(device)
     │    │ → 첫 발견 기기
     │    ↓
     │    Properties.setValue("ilens_name", deviceName)
     │    $.ilensName = deviceName
     │    pairDevice(device)
     │
     ├─ "iLens-sw-A1B2C3" (저장됨)
     │    │
     │    │ onScanResult(device)
     │    │ → deviceName == "iLens-sw-A1B2C3"?
     │    │
     │    ├─ Yes: pairDevice(device)
     │    └─ No: return (무시)
     │
     └─ (사용자가 Garmin Connect Mobile에서 변경 가능)
```

---

## 6. 에러 처리

### 6.1 BLE 연결 에러 (ActiveLook 재사용)

| 에러 상황 | 감지 방법 | 대응 방안 |
|----------|----------|----------|
| **iLens 발견 못함** | onScanResult() 30초 미호출 | requestScanning() 재시도 |
| **연결 실패** | onConnectedStateChanged(DISCONNECTED) | 자동 재스캔 |
| **Characteristic 없음** | getCharacteristic() null | tryGetCharacteristic() 5회 재시도 |
| **BLE Write 실패** | requestWrite() exception | try-catch, 로그, 스킵 |

### 6.2 Null Safety (ActiveLook 재사용)

**Activity.Info Null 체크**:
```monkey-c
function extractSpeed(info) {
    if (info.currentSpeed != null && info.currentSpeed > 0) {
        return (info.currentSpeed * 3.6).toNumber();
    }
    return 0;
}

function extractPower(info) {
    if (info.currentPower != null && info.currentPower > 0) {
        return info.currentPower.toNumber();
    }
    return null;  // Power는 null 허용 (센서 없을 수 있음)
}
```

### 6.3 메모리 관리 (ActiveLook 재사용)

**고정 크기 배열** (동적 할당 최소화):
```monkey-c
private var __pSamples = new [30];  // 고정 크기

// 30개 유지
if (__pSamples.size() >= 30) {
    __pSamples = __pSamples.slice(-30, null);
}
```

---

## 7. 성능 요구사항

### 7.1 처리 성능

| 항목 | 요구사항 | 근거 |
|------|---------|------|
| **compute() 주기** | ~50ms (20Hz) | Garmin OS 제어 |
| **BLE 전송 주기** | 1000ms ±100ms (1Hz) | Throttling 로직 |
| **파워 계산 시간** | <5ms | ActiveLook 검증됨 |
| **Auto-Pairing 시간** | <10초 (95%) | 스캔부터 연결까지 |

### 7.2 메모리 사용

| 항목 | 사용량 | 비고 |
|------|--------|------|
| **DataFieldView** | ~500 bytes | 변수, 싱글톤 |
| **ActivityInfo** | ~150 bytes | 30-sample buffer (30*4 + 기타) |
| **ILens** | ~100 bytes | BLE 상태, 디바이스 참조 |
| **ILensProtocol** | ~50 bytes | 페이로드 버퍼 |
| **총 메모리** | **<2.5MB** | Garmin 워치 제한 (5-10MB) |

### 7.3 배터리 소모

| 시나리오 | 목표 | 근거 |
|---------|------|------|
| **1시간 러닝** | +3.0-4.0% | iLens BLE + 파워 계산 |
| **하프 마라톤** | +6% | 평균 2시간 |

**ActiveLook 대비**: 동일 (BLE 프로토콜만 교체, 계산 로직 동일)

---

## 8. 확장성

### 8.1 Phase 2 확장 (ActiveLook 패턴 재사용)

**추가 메트릭**:
- Altitude (0x08)
- Average Pace (0x09)
- Lap Count (0x0A)

**추가 기능**:
- onTimerLap() 이벤트 처리
- Settings 확장 (전송 간격 설정)
- UI 개선 (iLens 연결 상태 + 저장된 이름 표시)

### 8.2 iLens 프로토콜 확장

**현재**:
- 7개 메트릭 (0x01, 0x06, 0x07, 0x0B, 0x0E, 0x11, 0x12, 0x13)

**확장 가능**:
- 0x08: Altitude
- 0x09: Average Pace
- 0x0A: Lap Count
- 0x14~0x1F: 예약 (향후 추가 메트릭)

**확장 방법**:
```monkey-c
// ILensProtocol.mc에 메서드 추가만 하면 됨
function sendAltitude(characteristic, altitude) {
    sendMetric(characteristic, 0x08, altitude);
}
```

---

## 9. 테스트 전략

### 9.1 단위 테스트 (Simulator)

**대상**:
- ActivityInfo 파워 계산 로직 (30-sample buffer)
- Auto-Pairing 로직 (ilens_name 빈 문자열)
- Throttling 로직 (1Hz)
- Null Safety (Activity.Info 필드)

**도구**: Connect IQ Simulator

### 9.2 통합 테스트 (실기)

**대상**:
- iLens BLE 연결 (10회 반복)
- 7개 메트릭 전송 확인
- 파워 계산 정확도 (Stryd 비교)
- Auto-Pairing (여러 iLens 환경)
- 재연결 (끊김 후 자동)

**기기**: Forerunner 265, iLens Series 1/2

### 9.3 성능 테스트

**측정**:
- 파워 계산 시간 (<5ms)
- BLE Write 지연 (<100ms)
- 메모리 사용량 (<2.5MB)
- 배터리 소모율 (1시간: <4.0%)

---

## 10. 참조 문서

**내부 문서**:
- `PRD-RunVision-IQ.md` v3.0 - 제품 요구사항
- `ActiveLook-Source-Analysis-Complete.md` - ActiveLook 완전 분석
- `iLens-BLE-Protocol-Analysis.md` - iLens 프로토콜 분석
- `BLE-Protocol-Mapping.md` (신규 작성 예정)
- `Module-Design.md` (재작성 예정)
- `Implementation-Guide.md` (신규 작성 예정)
- `Test-Specification.md` (재작성 예정)

**ActiveLook 소스**:
- `activeLook/source/ActiveLookDataFieldView.mc` (579 lines)
- `activeLook/source/ActiveLookActivityInfo.mc` (865 lines)
- `activeLook/source/ActiveLookSDK_next.mc` (1092 lines)
- `activeLook/resources/settings/properties.xml`

**외부 리소스**:
- [Connect IQ DataField API](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html)
- [BLE API Reference](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
- [ActiveLook GitHub](https://github.com/ActiveLook/Garmin-Datafield-sample-code)

---

**문서 이력**:
- v1.0 (2025-11-15): 초기 작성 (Activity App 기준)
- v2.0 (2025-11-15): DataField 기준으로 재작성
- **v3.0 (2025-11-15): ActiveLook 100% 복사 전략 반영**

**승인 상태**: ✅ Ready for Implementation (v3.0 최종)

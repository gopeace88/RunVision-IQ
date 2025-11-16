# Module Design Document: RunVision-IQ

**문서 버전**: v3.0
**작성일**: 2025-11-15
**프로젝트**: RunVision-IQ (Garmin Connect IQ DataField)
**목적**: 7개 모듈의 상세 설계 (클래스, 메서드, 상태 머신, 데이터 흐름)

---

## 📋 Table of Contents

1. [Document Overview](#1-document-overview)
2. [Module Summary](#2-module-summary)
3. [Module 1: RunVisionIQView.mc](#3-module-1-runvisioniqviewmc)
4. [Module 2: RunVisionIQActivityInfo.mc](#4-module-2-runvisioniqactivityinfomc)
5. [Module 3: ILens.mc](#5-module-3-ilensmc)
6. [Module 4: ILensProtocol.mc](#6-module-4-ilensprotocolmc)
7. [Module 5: properties.xml](#7-module-5-propertiesxml)
8. [Module 6: strings.xml](#8-module-6-stringsxml)
9. [Module 7: settings.xml](#9-module-7-settingsxml)
10. [Module Dependencies](#10-module-dependencies)
11. [State Machines](#11-state-machines)
12. [Data Flow Diagrams](#12-data-flow-diagrams)
13. [Performance Requirements](#13-performance-requirements)
14. [Testing Strategy](#14-testing-strategy)

---

## 1. Document Overview

### 1.1 Purpose

이 문서는 RunVision-IQ DataField의 **7개 모듈에 대한 완전하고 정확한 설계**를 제공합니다. 각 모듈의 클래스 구조, 메서드 시그니처, 상태 머신, 데이터 흐름을 코드 레벨까지 상세히 정의합니다.

### 1.2 Design Strategy

**v3.0 전략**: ActiveLook 100% 복사 + BLE 레이어만 교체

| 전략 요소 | 설명 | 비율 |
|----------|------|------|
| **복사** | ActiveLook 5개 모듈 그대로 복사 | 67% (~1,590 lines) |
| **교체** | BLE 레이어 2개 모듈 새로 작성 | 33% (~800 lines) |
| **총계** | 7개 모듈 | 100% (~2,390 lines) |

### 1.3 Module Classification

| 모듈 | 파일명 | 원본 | 변경 유형 | 라인 수 | 우선순위 |
|------|--------|------|----------|---------|----------|
| **DataFieldView** | RunVisionIQView.mc | ActiveLookDataFieldView.mc | ❌ 복사 | ~600 | P0 |
| **ActivityInfo** | RunVisionIQActivityInfo.mc | ActiveLookActivityInfo.mc | ❌ 복사 | ~900 | P0 |
| **ILens** | ILens.mc | ActiveLook.mc | ✅ 교체 | ~500 | P0 |
| **ILensProtocol** | ILensProtocol.mc | ActiveLookSDK_next.mc | ✅ 교체 | ~300 | P0 |
| **Properties** | properties.xml | properties.xml | ❌ 복사 | ~10 | P1 |
| **Strings** | strings.xml | strings.xml | ❌ 복사 | ~50 | P1 |
| **Settings** | settings.xml | settings.xml | ❌ 복사 | ~30 | P1 |

**P0**: 핵심 기능 (Week 1-2)
**P1**: 설정 및 UI (Week 3-4)

---

## 2. Module Summary

### 2.1 Module Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Garmin OS (Connect IQ)                      │
│  - Activity.Info (GPS, HR, Cadence, Power)                  │
│  - Position API, Sensor API                                 │
└────────────────────┬────────────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────────────┐
│         Module 1: RunVisionIQView.mc (DataField)            │
│  - compute(info): 20Hz 호출                                  │
│  - onUpdate(dc): UI 렌더링                                   │
│  - 1Hz Throttling                                            │
└────────┬────────────────────────────────────┬───────────────┘
         ↓                                    ↓
┌──────────────────────────┐   ┌──────────────────────────────┐
│ Module 2: ActivityInfo   │   │ Module 3: ILens.mc           │
│  - Power 계산            │   │  - BLE 연결 관리             │
│  - 30-Sample Buffer      │   │  - Auto-Pairing              │
│  - Normalized Power      │   │  - 상태 머신                 │
└──────────────────────────┘   └───────────┬──────────────────┘
                                           ↓
                             ┌──────────────────────────────┐
                             │ Module 4: ILensProtocol.mc   │
                             │  - sendMetric()              │
                             │  - Binary Encoding           │
                             │  - Little-Endian             │
                             └─────────┬────────────────────┘
                                       ↓
                             ┌──────────────────────────────┐
                             │   iLens BLE Service          │
                             │   Exercise Characteristic    │
                             │   (c259c1bd-...)             │
                             └──────────────────────────────┘
```

### 2.2 Responsibility Matrix

| 모듈 | 책임 | 입력 | 출력 |
|------|------|------|------|
| **RunVisionIQView** | DataField UI, Throttling | Activity.Info (20Hz) | UI 업데이트, BLE 전송 (1Hz) |
| **RunVisionIQActivityInfo** | Power 계산 | Activity.Info.currentPower | 3-Sec Power, Normalized Power |
| **ILens** | BLE 연결 관리 | Scan 결과 | BLE 연결 상태 |
| **ILensProtocol** | BLE 프로토콜 | Metric ID + Value | 5-byte Binary Packet |
| **properties.xml** | 설정 저장 | 사용자 입력 | 설정값 (ilens_name, etc.) |
| **strings.xml** | i18n | Locale | 번역된 문자열 |
| **settings.xml** | 설정 UI | 사용자 액션 | 설정 변경 |

### 2.3 Change Impact Analysis

| 변경 항목 | 영향받는 모듈 | 변경 유형 | 리스크 |
|----------|--------------|----------|--------|
| **UUID 변경** | ILens.mc | UUID 문자열 교체 | 낮음 |
| **프로토콜 변경** | ILensProtocol.mc | 전체 재작성 | 중간 |
| **Metric ID 변경** | RunVisionIQView.mc | ID 매핑 변경 | 낮음 |
| **Auto-Pairing** | ILens.mc, properties.xml | 로직 복사 | 낮음 |
| **Power 계산** | RunVisionIQActivityInfo.mc | 로직 복사 | 낮음 |

---

## 3. Module 1: RunVisionIQView.mc

### 3.1 Module Overview

**파일명**: `RunVisionIQView.mc`
**원본**: `ActiveLookDataFieldView.mc` (ActiveLook 프로젝트)
**변경 유형**: ❌ 복사 (95% 재사용, UUID/Metric ID만 변경)
**라인 수**: ~600 lines
**역할**: Connect IQ DataField 메인 클래스

**책임**:
- ✅ Activity.Info 수신 (20Hz)
- ✅ 1Hz Throttling (sendMetric 호출)
- ✅ ILens BLE 전송 조율
- ✅ UI 렌더링
- ✅ Timer 관리

### 3.2 Class Structure

```monkey-c
using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.ActivityRecording as Recording;
using ILens;
using ILensProtocol;

class RunVisionIQView extends Ui.DataField {
    // ===== Private Fields =====
    private var _session;                      // ActivityRecording.Session
    private var _ilens;                        // ILens.ILens (singleton)
    private var _activityInfo;                 // RunVisionIQActivityInfo
    private var _lastSendTime;                 // Long (System.getTimer())
    private var _sendIntervalMs;               // Long (1000ms)

    // ===== Constructor =====
    function initialize() {
        DataField.initialize();

        _session = null;
        _ilens = ILens.getInstance();
        _activityInfo = new RunVisionIQActivityInfo();
        _lastSendTime = 0;
        _sendIntervalMs = 1000;  // 1Hz
    }

    // ===== Public Methods (Connect IQ Callbacks) =====
    function onLayout(dc) { ... }
    function onUpdate(dc) { ... }
    function compute(info) { ... }
    function onTimerStart() { ... }
    function onTimerStop() { ... }
    function onTimerPause() { ... }
    function onTimerResume() { ... }
    function onTimerLap() { ... }
    function onTimerReset() { ... }

    // ===== Private Methods =====
    private function extractSpeed(info) { ... }
    private function extractDistance(info) { ... }
    private function extractHeartRate(info) { ... }
    private function extractCadence(info) { ... }
    private function extractPower(info) { ... }
    private function sendMetricsToILens(info) { ... }
}
```

### 3.3 Key Methods

#### 3.3.1 initialize()

**시그니처**:
```monkey-c
function initialize()
```

**구현** (ActiveLook 복사):
```monkey-c
function initialize() {
    DataField.initialize();

    _session = null;
    _ilens = ILens.getInstance();
    _activityInfo = new RunVisionIQActivityInfo();
    _lastSendTime = 0;
    _sendIntervalMs = 1000;  // 1Hz
}
```

**책임**:
- DataField 초기화
- ILens 싱글턴 가져오기
- ActivityInfo 인스턴스 생성
- Throttling 변수 초기화

**변경 사항**:
- ActiveLook → ILens (싱글턴 이름 변경)

#### 3.3.2 compute(info)

**시그니처**:
```monkey-c
function compute(info as Activity.Info) as Void
```

**구현** (ActiveLook 복사 + 수정):
```monkey-c
function compute(info) {
    if (info == null) { return; }

    // Step 1: Power 계산 (ActivityInfo에 위임)
    _activityInfo.accumulate(info);

    // Step 2: Throttling (1Hz)
    var now = System.getTimer();
    if (now - _lastSendTime < _sendIntervalMs) {
        return;  // Skip this cycle
    }
    _lastSendTime = now;

    // Step 3: iLens 전송
    sendMetricsToILens(info);
}
```

**호출 빈도**: 20Hz (Garmin OS가 자동 호출)
**실제 전송**: 1Hz (Throttling)

**책임**:
1. Power 계산 위임 (RunVisionIQActivityInfo.accumulate())
2. 1Hz Throttling 체크
3. iLens 메트릭 전송

**변경 사항**:
- ActiveLook.sendCommand() → ILens.sendMetric()

#### 3.3.3 sendMetricsToILens(info)

**시그니처**:
```monkey-c
private function sendMetricsToILens(info as Activity.Info) as Void
```

**구현** (새로 작성, iLens Metric ID 사용):
```monkey-c
private function sendMetricsToILens(info) {
    var ilens = ILens.getInstance();
    if (!ilens.isConnected()) {
        return;  // Not connected, skip
    }

    // Extract metrics from Activity.Info
    var speed = extractSpeed(info);          // km/h
    var distance = extractDistance(info);    // meters
    var heartRate = extractHeartRate(info);  // bpm
    var cadence = extractCadence(info);      // spm
    var power = extractPower(info);          // W

    // Get calculated power metrics
    var threeSecPower = _activityInfo.getThreeSecPower();      // W
    var normalizedPower = _activityInfo.getNormalizedPower();  // W

    // Send to iLens (with NULL checks)
    if (speed != null) {
        var speedScaled = (speed * 10).toNumber();  // Scale: 0.1 km/h
        ilens.sendMetric(0x07, speedScaled);
    }
    if (distance != null) {
        ilens.sendMetric(0x06, distance.toNumber());
    }
    if (heartRate != null) {
        ilens.sendMetric(0x0B, heartRate.toNumber());
    }
    if (cadence != null) {
        ilens.sendMetric(0x0E, cadence.toNumber());
    }
    if (threeSecPower != null) {
        ilens.sendMetric(0x11, threeSecPower.toNumber());
    }
    if (normalizedPower != null) {
        ilens.sendMetric(0x12, normalizedPower.toNumber());
    }
    if (power != null) {
        ilens.sendMetric(0x13, power.toNumber());
    }
}
```

**책임**:
1. Activity.Info에서 메트릭 추출
2. NULL 체크
3. Scale 적용 (Velocity만 × 10)
4. iLens BLE 전송 (7개 메트릭)

**변경 사항** (ActiveLook 대비):
- 텍스트 명령어 → 바이너리 메트릭
- Metric ID 매핑 (0x07, 0x06, 0x0B, 0x0E, 0x11, 0x12, 0x13)
- Scale 적용 (Velocity × 10)

#### 3.3.4 extractSpeed(info)

**시그니처**:
```monkey-c
private function extractSpeed(info as Activity.Info) as Float or Null
```

**구현** (ActiveLook 복사):
```monkey-c
private function extractSpeed(info) {
    if (info has :currentSpeed && info.currentSpeed != null) {
        return info.currentSpeed * 3.6;  // m/s → km/h
    }
    return null;
}
```

**책임**:
- Activity.Info.currentSpeed 추출 (m/s)
- km/h로 변환 (× 3.6)
- NULL 처리

#### 3.3.5 extractDistance(info)

**시그니처**:
```monkey-c
private function extractDistance(info as Activity.Info) as Float or Null
```

**구현** (ActiveLook 복사):
```monkey-c
private function extractDistance(info) {
    if (info has :elapsedDistance && info.elapsedDistance != null) {
        return info.elapsedDistance;  // meters
    }
    return null;
}
```

#### 3.3.6 extractHeartRate(info)

**시그니처**:
```monkey-c
private function extractHeartRate(info as Activity.Info) as Number or Null
```

**구현** (ActiveLook 복사):
```monkey-c
private function extractHeartRate(info) {
    if (info has :currentHeartRate && info.currentHeartRate != null) {
        return info.currentHeartRate;  // bpm
    }
    return null;
}
```

#### 3.3.7 extractCadence(info)

**시그니처**:
```monkey-c
private function extractCadence(info as Activity.Info) as Number or Null
```

**구현** (ActiveLook 복사):
```monkey-c
private function extractCadence(info) {
    if (info has :currentCadence && info.currentCadence != null) {
        return info.currentCadence * 2;  // Garmin: strides/min → spm
    }
    return null;
}
```

**주의**: Garmin은 currentCadence를 **strides/min** (한쪽 발)로 제공하므로 × 2 필요.

#### 3.3.8 extractPower(info)

**시그니처**:
```monkey-c
private function extractPower(info as Activity.Info) as Number or Null
```

**구현** (ActiveLook 복사):
```monkey-c
private function extractPower(info) {
    if (info has :currentPower && info.currentPower != null) {
        return info.currentPower;  // W
    }
    return null;
}
```

#### 3.3.9 onUpdate(dc)

**시그니처**:
```monkey-c
function onUpdate(dc as Dc) as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function onUpdate(dc) {
    // Clear background
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
    dc.clear();

    // Draw DataField label
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    dc.drawText(
        dc.getWidth() / 2,
        dc.getHeight() / 2,
        Graphics.FONT_MEDIUM,
        "RunVision-IQ",
        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
    );

    // Draw connection status
    var ilens = ILens.getInstance();
    var status = ilens.isConnected() ? "Connected" : "Disconnected";
    dc.drawText(
        dc.getWidth() / 2,
        dc.getHeight() / 2 + 30,
        Graphics.FONT_SMALL,
        status,
        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
    );
}
```

**책임**:
- DataField UI 렌더링
- 연결 상태 표시

**변경 사항**: 없음 (ActiveLook과 동일)

#### 3.3.10 onTimerStart()

**시그니처**:
```monkey-c
function onTimerStart() as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function onTimerStart() {
    var ilens = ILens.getInstance();
    ilens.startScan();  // BLE 스캔 시작
}
```

**호출 시점**: 사용자가 러닝 세션 시작 버튼 누를 때

#### 3.3.11 onTimerStop()

**시그니처**:
```monkey-c
function onTimerStop() as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function onTimerStop() {
    var ilens = ILens.getInstance();
    ilens.disconnect();  // BLE 연결 해제
}
```

**호출 시점**: 사용자가 러닝 세션 종료 버튼 누를 때

### 3.4 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **클래스명** | ActiveLookDataFieldView | RunVisionIQView | 이름 변경 |
| **BLE 싱글턴** | ActiveLook.getInstance() | ILens.getInstance() | 이름 변경 |
| **전송 메서드** | sendCommand(cmd) | sendMetric(id, val) | 시그니처 변경 |
| **Metric ID** | txt(0, ...) | 0x07, 0x06, ... | ID 매핑 변경 |
| **Scale** | 없음 | Velocity × 10 | 로직 추가 |
| **나머지** | 복사 | 복사 | 변경 없음 |

**총 변경 라인 수**: ~50 / 600 lines (**8% 수정, 92% 복사**)

---

## 4. Module 2: RunVisionIQActivityInfo.mc

### 4.1 Module Overview

**파일명**: `RunVisionIQActivityInfo.mc`
**원본**: `ActiveLookActivityInfo.mc` (ActiveLook 프로젝트)
**변경 유형**: ❌ 복사 (100% 재사용)
**라인 수**: ~900 lines
**역할**: Power 메트릭 계산 (3-Second Power, Normalized Power)

**책임**:
- ✅ currentPower 샘플 수집 (30-sample buffer)
- ✅ 3-Second Power 계산 (6 samples average)
- ✅ Normalized Power 계산 (`(avg(power^4))^(1/4)`)
- ✅ Activity.Info 메트릭 추출

### 4.2 Class Structure

```monkey-c
using Toybox.Math as Math;

class RunVisionIQActivityInfo {
    // ===== Private Fields =====
    private var __pSamples;      // Array<Number> (30-sample buffer)
    private var __pAccu;         // Float (sum of power^4)
    private var __pAccuNb;       // Number (count)

    // ===== Constructor =====
    function initialize() {
        __pSamples = [];
        __pAccu = 0.0;
        __pAccuNb = 0;
    }

    // ===== Public Methods =====
    function accumulate(info) { ... }
    function getThreeSecPower() { ... }
    function getNormalizedPower() { ... }
    function reset() { ... }
}
```

### 4.3 Key Methods

#### 4.3.1 accumulate(info)

**시그니처**:
```monkey-c
function accumulate(info as Activity.Info) as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function accumulate(info) {
    if (info == null || info.currentPower == null) {
        return;  // No power data
    }

    var power = info.currentPower;

    // Add to 30-sample buffer
    __pSamples.add(power);

    // Keep only last 30 samples
    if (__pSamples.size() >= 30) {
        __pSamples = __pSamples.slice(-30, null);

        // Calculate 30-sample average
        var tmp = 0;
        for (var i = 0; i < 30; i++) {
            tmp += __pSamples[i];
        }
        var avg30 = tmp / 30.0;

        // Accumulate power^4 for Normalized Power
        __pAccu += Math.pow(avg30, 4);
        __pAccuNb++;
    }
}
```

**호출 빈도**: 20Hz (compute() 내부에서 호출)
**실제 계산**: 30 samples 채워지면 (1.5초 후)

**책임**:
1. currentPower 샘플 추가
2. 30-sample 롤링 버퍼 유지
3. 30-sample 평균 계산
4. power^4 누적 (Normalized Power용)

#### 4.3.2 getThreeSecPower()

**시그니처**:
```monkey-c
function getThreeSecPower() as Float or Null
```

**구현** (ActiveLook 복사):
```monkey-c
function getThreeSecPower() {
    if (__pSamples.size() >= 6) {
        var tmp = __pSamples.slice(-6, null);
        return (tmp[0] + tmp[1] + tmp[2] + tmp[3] + tmp[4] + tmp[5]) / 6.0;
    }
    return null;
}
```

**반환값**:
- 최근 6개 샘플 평균 (3초 @ 20Hz → 60 samples, 하지만 30-sample 롤링이므로 6개 사용)
- NULL: 6개 미만일 때

#### 4.3.3 getNormalizedPower()

**시그니처**:
```monkey-c
function getNormalizedPower() as Float or Null
```

**구현** (ActiveLook 복사):
```monkey-c
function getNormalizedPower() {
    if (__pAccuNb > 0) {
        return Math.pow(__pAccu / __pAccuNb, 0.25);  // 4th root
    }
    return null;
}
```

**수식**:
```
NP = (sum(power^4) / count)^(1/4)
```

**반환값**:
- Normalized Power (W)
- NULL: 데이터 없을 때

#### 4.3.4 reset()

**시그니처**:
```monkey-c
function reset() as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function reset() {
    __pSamples = [];
    __pAccu = 0.0;
    __pAccuNb = 0;
}
```

**호출 시점**: onTimerReset() 또는 새 세션 시작 시

### 4.4 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **클래스명** | ActiveLookActivityInfo | RunVisionIQActivityInfo | 이름 변경 |
| **로직** | 복사 | 복사 | 변경 없음 |
| **알고리즘** | 복사 | 복사 | 변경 없음 |

**총 변경 라인 수**: 0 / 900 lines (**0% 수정, 100% 복사**)

---

## 5. Module 3: ILens.mc

### 5.1 Module Overview

**파일명**: `ILens.mc`
**원본**: `ActiveLook.mc` (ActiveLook 프로젝트)
**변경 유형**: ✅ 교체 (UUID + Auto-Pairing 로직은 복사, 나머지는 iLens 전용)
**라인 수**: ~500 lines
**역할**: iLens BLE 연결 관리 (Singleton)

**책임**:
- ✅ BLE 스캔 및 연결
- ✅ Auto-Pairing (properties.xml 기반)
- ✅ 연결 상태 관리
- ✅ 재연결 로직
- ✅ sendMetric() 제공

### 5.2 Class Structure

```monkey-c
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.System as Sys;
using Toybox.Application.Properties as Props;
using ILensProtocol;

class ILens extends Ble.BleDelegate {
    // ===== Private Static Fields =====
    private static var _instance = null;

    // ===== Private Fields =====
    private var _state;                  // Symbol (:STATE_IDLE, :STATE_SCANNING, ...)
    private var _device;                 // Ble.Device
    private var _service;                // Ble.Service
    private var _exerciseCharacteristic; // Ble.Characteristic
    private var _ilensName;              // String (from properties.xml)

    // UUIDs
    private const SERVICE_UUID = "4b329cf2-3816-498c-8453-ee8798502a08";
    private const EXERCISE_CHAR_UUID = "c259c1bd-18d3-c348-b88d-5447aea1b615";

    // ===== Constructor (Private) =====
    private function initialize() {
        BleDelegate.initialize();

        _state = :STATE_IDLE;
        _device = null;
        _service = null;
        _exerciseCharacteristic = null;
        _ilensName = Props.getValue("ilens_name");
        if (_ilensName == null) { _ilensName = ""; }
    }

    // ===== Public Static Methods =====
    static function getInstance() { ... }

    // ===== Public Methods =====
    function startScan() { ... }
    function disconnect() { ... }
    function isConnected() { ... }
    function sendMetric(metricId, value) { ... }

    // ===== BleDelegate Callbacks =====
    function onScanResults(scanResults) { ... }
    function onConnectedStateChanged(device, state) { ... }

    // ===== Private Methods =====
    private function setState(newState) { ... }
    private function pairDevice(scanResult) { ... }
    private function discoverServices() { ... }
    private function discoverCharacteristics() { ... }
}
```

### 5.3 State Machine

```
┌─────────────┐
│ STATE_IDLE  │
└──────┬──────┘
       │ startScan()
       ↓
┌──────────────┐
│STATE_SCANNING│
└──────┬───────┘
       │ onScanResults()
       ↓
┌──────────────┐
│STATE_PAIRING │
└──────┬───────┘
       │ onConnectedStateChanged(CONNECTED)
       ↓
┌───────────────────┐
│STATE_DISCOVERING  │
└──────┬────────────┘
       │ discoverServices() → discoverCharacteristics()
       ↓
┌──────────────┐
│STATE_CONNECTED│ ←──┐
└──────┬───────┘     │
       │ disconnect()│ Auto-Reconnect
       ↓             │
┌─────────────────┐  │
│STATE_DISCONNECTED├──┘
└─────────────────┘
```

### 5.4 Key Methods

#### 5.4.1 getInstance()

**시그니처**:
```monkey-c
static function getInstance() as ILens
```

**구현** (ActiveLook 복사):
```monkey-c
static function getInstance() {
    if (_instance == null) {
        _instance = new ILens();
    }
    return _instance;
}
```

**패턴**: Singleton

#### 5.4.2 startScan()

**시그니처**:
```monkey-c
function startScan() as Void
```

**구현** (ActiveLook 복사 + UUID 변경):
```monkey-c
function startScan() {
    if (_state != :STATE_IDLE && _state != :STATE_DISCONNECTED) {
        return;  // Already scanning or connected
    }

    setState(:STATE_SCANNING);

    var serviceUuid = Ble.stringToUuid(SERVICE_UUID);
    var scanOptions = {
        :serviceUuids => [serviceUuid]
    };

    try {
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        Ble.scanForDevices(self, scanOptions);
    } catch (ex) {
        (:debug) Sys.println("Scan failed: " + ex.getErrorMessage());
        setState(:STATE_IDLE);
    }
}
```

**책임**:
- BLE 스캔 시작
- iLens Service UUID로 필터링
- 상태 전이: IDLE/DISCONNECTED → SCANNING

**변경 사항**:
- ActiveLook UUID → iLens UUID

#### 5.4.3 onScanResults(scanResults)

**시그니처**:
```monkey-c
function onScanResults(scanResults as Ble.Iterator) as Void
```

**구현** (ActiveLook 복사, Auto-Pairing 유지):
```monkey-c
function onScanResults(scanResults) {
    for (var result = scanResults.next(); result != null; result = scanResults.next()) {
        var deviceName = result.getDeviceName();
        if (deviceName == null) { deviceName = ""; }

        (:debug) Sys.println("Found device: " + deviceName);

        // Auto-Pairing: Save first discovered device
        if (_ilensName.equals("")) {
            Props.setValue("ilens_name", deviceName);
            _ilensName = deviceName;
            (:debug) Sys.println("Auto-saved device: " + deviceName);
        }

        // Only pair with saved device
        if (_ilensName.equals(deviceName)) {
            pairDevice(result);
            return;
        }
    }
}
```

**Auto-Pairing 로직** (ActiveLook 복사):
1. `ilens_name` 속성이 비어있으면 → 첫 발견 기기 저장
2. `ilens_name`과 일치하는 기기만 연결
3. 나머지 기기 무시

**변경 사항**: 없음 (ActiveLook과 동일)

#### 5.4.4 pairDevice(scanResult)

**시그니처**:
```monkey-c
private function pairDevice(scanResult as Ble.ScanResult) as Void
```

**구현** (ActiveLook 복사):
```monkey-c
private function pairDevice(scanResult) {
    setState(:STATE_PAIRING);

    try {
        Ble.pairDevice(scanResult);
        _device = scanResult.getDevice();
    } catch (ex) {
        (:debug) Sys.println("Pairing failed: " + ex.getErrorMessage());
        setState(:STATE_IDLE);
    }
}
```

**책임**:
- BLE Pairing 시작
- Device 객체 저장
- 상태 전이: SCANNING → PAIRING

#### 5.4.5 onConnectedStateChanged(device, state)

**시그니처**:
```monkey-c
function onConnectedStateChanged(device as Ble.Device, state as Ble.ConnectionState) as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function onConnectedStateChanged(device, state) {
    if (state == Ble.CONNECTION_STATE_CONNECTED) {
        (:debug) Sys.println("Connected to iLens");
        setState(:STATE_DISCOVERING);
        discoverServices();
    } else if (state == Ble.CONNECTION_STATE_DISCONNECTED) {
        (:debug) Sys.println("Disconnected from iLens");
        setState(:STATE_DISCONNECTED);

        // Auto-Reconnect (optional)
        // startScan();
    }
}
```

**책임**:
- 연결 상태 변화 감지
- CONNECTED → Service Discovery 시작
- DISCONNECTED → 재연결 옵션

#### 5.4.6 discoverServices()

**시그니처**:
```monkey-c
private function discoverServices() as Void
```

**구현** (ActiveLook 복사 + UUID 변경):
```monkey-c
private function discoverServices() {
    if (_device == null) { return; }

    var serviceUuid = Ble.stringToUuid(SERVICE_UUID);

    try {
        _service = _device.getService(serviceUuid);
        if (_service != null) {
            discoverCharacteristics();
        } else {
            (:debug) Sys.println("Service not found");
            setState(:STATE_DISCONNECTED);
        }
    } catch (ex) {
        (:debug) Sys.println("Service discovery failed: " + ex.getErrorMessage());
        setState(:STATE_DISCONNECTED);
    }
}
```

**책임**:
- iLens Service UUID로 서비스 검색
- Service 객체 저장
- 다음 단계: Characteristic Discovery

**변경 사항**:
- ActiveLook UUID → iLens UUID

#### 5.4.7 discoverCharacteristics()

**시그니처**:
```monkey-c
private function discoverCharacteristics() as Void
```

**구현** (ActiveLook 복사 + UUID 변경):
```monkey-c
private function discoverCharacteristics() {
    if (_service == null) { return; }

    var exerciseUuid = Ble.stringToUuid(EXERCISE_CHAR_UUID);

    try {
        _exerciseCharacteristic = _service.getCharacteristic(exerciseUuid);
        if (_exerciseCharacteristic != null) {
            (:debug) Sys.println("Exercise Characteristic found");
            setState(:STATE_CONNECTED);
        } else {
            (:debug) Sys.println("Exercise Characteristic not found");
            setState(:STATE_DISCONNECTED);
        }
    } catch (ex) {
        (:debug) Sys.println("Characteristic discovery failed: " + ex.getErrorMessage());
        setState(:STATE_DISCONNECTED);
    }
}
```

**책임**:
- Exercise Characteristic UUID로 특성 검색
- Characteristic 객체 저장
- 상태 전이: DISCOVERING → CONNECTED

**변경 사항**:
- ActiveLook Tx/Flow Characteristic → iLens Exercise Characteristic (단일)

#### 5.4.8 isConnected()

**시그니처**:
```monkey-c
function isConnected() as Boolean
```

**구현** (ActiveLook 복사):
```monkey-c
function isConnected() {
    return _state == :STATE_CONNECTED && _exerciseCharacteristic != null;
}
```

**반환값**:
- `true`: STATE_CONNECTED && Characteristic 존재
- `false`: 그 외

#### 5.4.9 sendMetric(metricId, value)

**시그니처**:
```monkey-c
function sendMetric(metricId as Number, value as Number) as Void
```

**구현** (새로 작성, ILensProtocol에 위임):
```monkey-c
function sendMetric(metricId, value) {
    if (!isConnected()) {
        return;  // Not connected
    }

    ILensProtocol.sendMetric(_exerciseCharacteristic, metricId, value);
}
```

**책임**:
- 연결 상태 확인
- ILensProtocol.sendMetric() 호출

**변경 사항**:
- ActiveLook.sendCommand(cmd) → ILens.sendMetric(id, val)

#### 5.4.10 disconnect()

**시그니처**:
```monkey-c
function disconnect() as Void
```

**구현** (ActiveLook 복사):
```monkey-c
function disconnect() {
    if (_device != null) {
        try {
            Ble.unpairDevice(_device);
        } catch (ex) {
            (:debug) Sys.println("Disconnect failed: " + ex.getErrorMessage());
        }
    }

    _device = null;
    _service = null;
    _exerciseCharacteristic = null;
    setState(:STATE_IDLE);
}
```

**책임**:
- BLE Unpair
- 모든 객체 초기화
- 상태 전이: 모든 상태 → IDLE

### 5.5 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **클래스명** | ActiveLook | ILens | 이름 변경 |
| **Service UUID** | 0783b03e-... | 4b329cf2-... | UUID 변경 |
| **Characteristic** | Tx + Flow | Exercise (단일) | UUID + 개수 변경 |
| **Auto-Pairing** | 복사 | 복사 | 변경 없음 |
| **상태 머신** | 복사 | 복사 | 변경 없음 |
| **sendMetric()** | sendCommand() | sendMetric() | 시그니처 변경 |

**총 변경 라인 수**: ~100 / 500 lines (**20% 수정, 80% 복사**)

---

## 6. Module 4: ILensProtocol.mc

### 6.1 Module Overview

**파일명**: `ILensProtocol.mc`
**원본**: `ActiveLookSDK_next.mc` (ActiveLook 프로젝트)
**변경 유형**: ✅ 교체 (전체 재작성, 바이너리 프로토콜)
**라인 수**: ~300 lines
**역할**: iLens BLE 바이너리 프로토콜 구현

**책임**:
- ✅ sendMetric() 구현 (5-byte binary)
- ✅ Little-Endian 인코딩
- ✅ BLE Write 요청
- ✅ 에러 처리

### 6.2 Module Structure

```monkey-c
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.System as Sys;

module ILensProtocol {
    // ===== Public Functions =====
    function sendMetric(characteristic, metricId, value) { ... }

    // ===== Private Functions =====
    function buildPayload(metricId, value) { ... }
}
```

### 6.3 Key Functions

#### 6.3.1 sendMetric(characteristic, metricId, value)

**시그니처**:
```monkey-c
function sendMetric(
    characteristic as Ble.Characteristic,
    metricId as Number,
    value as Number
) as Void
```

**구현**:
```monkey-c
function sendMetric(characteristic, metricId, value) {
    if (characteristic == null) {
        (:debug) Sys.println("Characteristic is null");
        return;
    }

    var payload = buildPayload(metricId, value);

    try {
        characteristic.requestWrite(payload, {
            :writeType => Ble.WRITE_TYPE_DEFAULT
        });
    } catch (ex) {
        (:debug) Sys.println("BLE Write failed: " + ex.getErrorMessage());
    }
}
```

**책임**:
1. NULL 체크
2. 바이너리 페이로드 생성
3. BLE Write 요청
4. 에러 처리

**파라미터**:
- `characteristic`: iLens Exercise Characteristic
- `metricId`: 0x07, 0x06, 0x0B, 0x0E, 0x11, 0x12, 0x13
- `value`: UINT32 값

**예외 처리**:
- `characteristic == null` → 조기 반환
- BLE Write 실패 → 로그 출력 (crash 방지)

#### 6.3.2 buildPayload(metricId, value)

**시그니처**:
```monkey-c
function buildPayload(
    metricId as Number,
    value as Number
) as ByteArray
```

**구현**:
```monkey-c
function buildPayload(metricId, value) {
    var payload = new [5]b;

    // Byte 0: Metric ID
    payload[0] = metricId;

    // Bytes 1-4: UINT32 Little-Endian
    var valueInt = value.toNumber();
    payload[1] = (valueInt & 0xFF);           // LSB
    payload[2] = ((valueInt >> 8) & 0xFF);
    payload[3] = ((valueInt >> 16) & 0xFF);
    payload[4] = ((valueInt >> 24) & 0xFF);   // MSB

    return payload;
}
```

**패킷 구조**:
```
[Metric_ID(1 byte), UINT32(4 bytes, Little-Endian)]
```

**예시**:
```monkey-c
// Velocity: 57.6 km/h → 576 (0.1 km/h units)
buildPayload(0x07, 576)
// → [0x07, 0x40, 0x02, 0x00, 0x00]

// Heart Rate: 145 bpm
buildPayload(0x0B, 145)
// → [0x0B, 0x91, 0x00, 0x00, 0x00]
```

**Little-Endian 인코딩**:
```
Value: 576 (0x0240)
LSB first: [0x40, 0x02, 0x00, 0x00]
```

### 6.4 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **모듈명** | ActiveLookSDK_next | ILensProtocol | 이름 변경 |
| **함수** | sendCommand(cmd) | sendMetric(char, id, val) | 시그니처 변경 |
| **프로토콜** | 텍스트 기반 | 바이너리 | 전체 재작성 |
| **패킷 크기** | ~20 bytes | 5 bytes | 77% 감소 |
| **인코딩** | UTF-8 String | UINT32 Little-Endian | 전체 재작성 |

**총 변경 라인 수**: ~300 / 300 lines (**100% 재작성**)

---

## 7. Module 5: properties.xml

### 7.1 Module Overview

**파일명**: `properties.xml`
**원본**: `properties.xml` (ActiveLook 프로젝트)
**변경 유형**: ❌ 복사 (100% 재사용)
**라인 수**: ~10 lines
**역할**: 앱 속성 정의 (Auto-Pairing용)

### 7.2 File Content

```xml
<properties>
    <property id="ilens_name" type="string">
        <settingConfig type="alphaNumeric" />
        <default></default>
    </property>
</properties>
```

**속성**:
- `ilens_name`: Auto-Pairing을 위한 기기 이름 저장
- 기본값: 빈 문자열
- 타입: alphaNumeric

### 7.3 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **속성 이름** | activelook_name | ilens_name | 이름 변경 |
| **나머지** | 복사 | 복사 | 변경 없음 |

**총 변경 라인 수**: 1 / 10 lines (**10% 수정, 90% 복사**)

---

## 8. Module 6: strings.xml

### 8.1 Module Overview

**파일명**: `strings.xml`
**원본**: `strings.xml` (ActiveLook 프로젝트)
**변경 유형**: ❌ 복사 (95% 재사용, 브랜드 이름만 변경)
**라인 수**: ~50 lines
**역할**: 다국어 문자열 정의

### 8.2 File Content

```xml
<strings>
    <string id="AppName">RunVision-IQ</string>

    <!-- Connection Status -->
    <string id="Scanning">Scanning...</string>
    <string id="Connecting">Connecting...</string>
    <string id="Connected">Connected</string>
    <string id="Disconnected">Disconnected</string>

    <!-- Metrics -->
    <string id="Speed">Speed</string>
    <string id="Distance">Distance</string>
    <string id="HeartRate">Heart Rate</string>
    <string id="Cadence">Cadence</string>
    <string id="Power">Power</string>

    <!-- Settings -->
    <string id="SettingsTitle">RunVision-IQ Settings</string>
    <string id="DeviceName">iLens Device Name</string>
</strings>
```

### 8.3 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **AppName** | ActiveLook DataField | RunVision-IQ | 브랜드 변경 |
| **DeviceName** | ActiveLook Device Name | iLens Device Name | 브랜드 변경 |
| **나머지** | 복사 | 복사 | 변경 없음 |

**총 변경 라인 수**: ~5 / 50 lines (**10% 수정, 90% 복사**)

---

## 9. Module 7: settings.xml

### 9.1 Module Overview

**파일명**: `settings.xml`
**원본**: `settings.xml` (ActiveLook 프로젝트)
**변경 유형**: ❌ 복사 (100% 재사용)
**라인 수**: ~30 lines
**역할**: 설정 UI 정의

### 9.2 File Content

```xml
<settings>
    <setting propertyKey="@Properties.ilens_name" title="@Strings.DeviceName">
        <settingConfig type="alphaNumeric" />
    </setting>
</settings>
```

**설정 항목**:
- `ilens_name`: iLens 기기 이름 입력

### 9.3 Change Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **propertyKey** | activelook_name | ilens_name | 이름 변경 |
| **나머지** | 복사 | 복사 | 변경 없음 |

**총 변경 라인 수**: 1 / 30 lines (**3% 수정, 97% 복사**)

---

## 10. Module Dependencies

### 10.1 Dependency Graph

```
RunVisionIQView.mc
    ├── Toybox.WatchUi
    ├── Toybox.System
    ├── Toybox.ActivityRecording
    ├── ILens.mc
    └── RunVisionIQActivityInfo.mc

RunVisionIQActivityInfo.mc
    └── Toybox.Math

ILens.mc
    ├── Toybox.BluetoothLowEnergy
    ├── Toybox.System
    ├── Toybox.Application.Properties
    └── ILensProtocol.mc

ILensProtocol.mc
    ├── Toybox.BluetoothLowEnergy
    └── Toybox.System

properties.xml
    (no dependencies)

strings.xml
    (no dependencies)

settings.xml
    ├── properties.xml
    └── strings.xml
```

### 10.2 Compile Order

1. **ILensProtocol.mc** (no dependencies)
2. **ILens.mc** (depends on ILensProtocol)
3. **RunVisionIQActivityInfo.mc** (no dependencies)
4. **RunVisionIQView.mc** (depends on ILens, RunVisionIQActivityInfo)
5. **properties.xml**
6. **strings.xml**
7. **settings.xml** (depends on properties, strings)

### 10.3 Circular Dependency Check

✅ **No circular dependencies**

---

## 11. State Machines

### 11.1 ILens BLE Connection State Machine

**States**:
- `STATE_IDLE`: 초기 상태
- `STATE_SCANNING`: BLE 스캔 중
- `STATE_PAIRING`: 페어링 중
- `STATE_DISCOVERING`: Service/Characteristic Discovery 중
- `STATE_CONNECTED`: 연결 완료
- `STATE_DISCONNECTED`: 연결 해제

**Transitions**:

```
[IDLE]
  │ startScan()
  ↓
[SCANNING]
  │ onScanResults() + Auto-Pairing Match
  ↓
[PAIRING]
  │ onConnectedStateChanged(CONNECTED)
  ↓
[DISCOVERING]
  │ discoverServices() → discoverCharacteristics()
  ↓
[CONNECTED]
  │ disconnect() OR onConnectedStateChanged(DISCONNECTED)
  ↓
[DISCONNECTED]
  │ (optional) Auto-Reconnect: startScan()
  ↓
[SCANNING] ...
```

**State Predicates**:
- `isConnected()`: state == STATE_CONNECTED && _exerciseCharacteristic != null
- `isScanning()`: state == STATE_SCANNING
- `isIdle()`: state == STATE_IDLE

### 11.2 Auto-Pairing State Machine

**States**:
- `NO_SAVED_DEVICE`: `ilens_name` 속성이 비어있음
- `SAVED_DEVICE_EXISTS`: `ilens_name` 속성에 기기 이름 저장됨

**Transitions**:

```
[NO_SAVED_DEVICE]
  │ onScanResults() → 첫 발견 기기
  ↓
[SAVED_DEVICE_EXISTS]
  │ Properties.setValue("ilens_name", deviceName)
  ↓
[AUTO_PAIR_DEVICE]
  │ Ble.pairDevice(scanResult)
```

**Logic**:
```monkey-c
if (_ilensName.equals("")) {
    // Save first discovered device
    Props.setValue("ilens_name", deviceName);
    _ilensName = deviceName;
}

// Only pair with saved device
if (_ilensName.equals(deviceName)) {
    pairDevice(scanResult);
}
```

---

## 12. Data Flow Diagrams

### 12.1 Overall Data Flow (1Hz)

```
┌─────────────────────────────────────┐
│   Garmin OS (Activity.Info)        │
│   - currentSpeed: 16.0 m/s          │
│   - elapsedDistance: 5200 m         │
│   - currentHeartRate: 145 bpm       │
│   - currentCadence: 88 strides/min  │
│   - currentPower: 250 W             │
└────────────┬────────────────────────┘
             │ 20Hz
             ↓
┌─────────────────────────────────────┐
│  RunVisionIQView.compute(info)      │
│  1. ActivityInfo.accumulate(info)   │
│  2. Throttling (1Hz)                │
│  3. sendMetricsToILens(info)        │
└────────┬────────────────────────────┘
         │ 1Hz
         ↓
┌────────────────────────────┬────────────────────────────┐
│ Extract Activity.Info      │ Get Calculated Metrics     │
│ - speed: 57.6 km/h         │ - 3-sec power: 248 W       │
│ - distance: 5200 m         │ - normalized power: 242 W  │
│ - heartRate: 145 bpm       │                            │
│ - cadence: 176 spm         │                            │
│ - power: 250 W             │                            │
└────────┬───────────────────┴────────────────────────────┘
         │ 1Hz
         ↓
┌─────────────────────────────────────┐
│  ILens.sendMetric(id, value)        │
│  - 0x07: 576 (57.6 km/h)            │
│  - 0x06: 5200 (distance)            │
│  - 0x0B: 145 (HR)                   │
│  - 0x0E: 176 (cadence)              │
│  - 0x11: 248 (3-sec power)          │
│  - 0x12: 242 (normalized power)     │
│  - 0x13: 250 (instant power)        │
└────────┬────────────────────────────┘
         │ 1Hz
         ↓
┌─────────────────────────────────────┐
│  ILensProtocol.sendMetric()         │
│  buildPayload(0x07, 576)            │
│  → [0x07, 0x40, 0x02, 0x00, 0x00]   │
│  BLE Write Request                  │
└────────┬────────────────────────────┘
         │ 1Hz
         ↓
┌─────────────────────────────────────┐
│  iLens BLE Service                  │
│  Exercise Characteristic            │
│  (c259c1bd-...)                     │
└─────────────────────────────────────┘
```

### 12.2 Power Calculation Data Flow

```
┌─────────────────────────────────────┐
│  Activity.Info.currentPower         │
│  250 W                              │
└────────────┬────────────────────────┘
             │ 20Hz
             ↓
┌─────────────────────────────────────┐
│  ActivityInfo.accumulate(info)      │
│  1. __pSamples.add(250)             │
│  2. Keep last 30 samples            │
│  3. Calculate 30-sample avg         │
│  4. Accumulate power^4              │
└────────┬────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────┐
│  __pSamples (30-sample buffer)      │
│  [248, 249, 250, 251, ...]          │
└────────┬────────────────────────────┘
         │
         ├────────────────┬─────────────────┐
         ↓                ↓                 ↓
┌────────────────┐ ┌──────────────┐ ┌──────────────────┐
│ 3-Sec Power    │ │ Norm Power   │ │ Instant Power    │
│ avg(last 6)    │ │ (avg(p^4))^¼ │ │ currentPower     │
│ 248 W          │ │ 242 W        │ │ 250 W            │
└────────────────┘ └──────────────┘ └──────────────────┘
         │                │                 │
         └────────────────┴─────────────────┘
                          ↓
                   ┌──────────────┐
                   │ iLens BLE TX │
                   └──────────────┘
```

### 12.3 Auto-Pairing Data Flow

```
┌─────────────────────────────────────┐
│  properties.xml                     │
│  ilens_name: "" (empty)             │
└────────────┬────────────────────────┘
             │ Load at startup
             ↓
┌─────────────────────────────────────┐
│  ILens.initialize()                 │
│  _ilensName = Props.getValue(...)   │
│  _ilensName == ""                   │
└────────────┬────────────────────────┘
             │ startScan()
             ↓
┌─────────────────────────────────────┐
│  BLE Scan Results                   │
│  - Device 1: "iLens-A1B2"           │
│  - Device 2: "iLens-C3D4"           │
└────────────┬────────────────────────┘
             │ onScanResults()
             ↓
┌─────────────────────────────────────┐
│  Auto-Pairing Logic                 │
│  if (_ilensName.equals("")) {       │
│    Props.setValue("ilens_name",     │
│                   "iLens-A1B2");    │
│    _ilensName = "iLens-A1B2";       │
│  }                                  │
└────────────┬────────────────────────┘
             │ pairDevice()
             ↓
┌─────────────────────────────────────┐
│  properties.xml (Updated)           │
│  ilens_name: "iLens-A1B2"           │
└─────────────────────────────────────┘
             │ Next scan
             ↓
┌─────────────────────────────────────┐
│  Only connect to "iLens-A1B2"       │
│  Ignore other devices               │
└─────────────────────────────────────┘
```

---

## 13. Performance Requirements

### 13.1 Timing Requirements

| 메트릭 | 요구사항 | 측정 방법 |
|--------|----------|----------|
| **compute() 호출 주기** | 20Hz (50ms) | Garmin OS 보장 |
| **BLE 전송 주기** | 1Hz (1000ms) | Throttling 검증 |
| **BLE Write 지연** | <100ms | nRF Connect 측정 |
| **Service Discovery** | <5s | onConnectedStateChanged → STATE_CONNECTED |
| **Auto-Pairing** | <10s | startScan() → STATE_CONNECTED |

### 13.2 Resource Requirements

| 리소스 | 요구사항 | 측정 방법 |
|--------|----------|----------|
| **메모리 (Heap)** | <100KB | Connect IQ Profiler |
| **CPU 사용률** | <5% | Garmin Device Profiler |
| **배터리 소모** | <1%/hour | 실제 러닝 세션 측정 |
| **BLE 패킷 크기** | 5 bytes/metric | nRF Connect 캡처 |

### 13.3 Reliability Requirements

| 메트릭 | 요구사항 | 측정 방법 |
|--------|----------|----------|
| **BLE 전송 성공률** | >99% | 1시간 러닝 세션 |
| **재연결 성공률** | >95% | 연결 끊김 후 재연결 |
| **Crash 없음** | 100% | 1시간 러닝 세션 |

---

## 14. Testing Strategy

### 14.1 Unit Testing

**Module 1: RunVisionIQView.mc**
- [ ] `extractSpeed()`: m/s → km/h 변환
- [ ] `extractDistance()`: meters 추출
- [ ] `extractHeartRate()`: bpm 추출
- [ ] `extractCadence()`: strides/min → spm 변환
- [ ] `extractPower()`: W 추출
- [ ] `sendMetricsToILens()`: NULL 체크, Scale 적용

**Module 2: RunVisionIQActivityInfo.mc**
- [ ] `accumulate()`: 30-sample buffer 유지
- [ ] `getThreeSecPower()`: 6-sample 평균 계산
- [ ] `getNormalizedPower()`: (avg(power^4))^(1/4) 계산
- [ ] `reset()`: 상태 초기화

**Module 3: ILens.mc**
- [ ] `startScan()`: BLE 스캔 시작
- [ ] `onScanResults()`: Auto-Pairing 로직
- [ ] `pairDevice()`: 페어링 요청
- [ ] `discoverServices()`: Service UUID 검색
- [ ] `discoverCharacteristics()`: Characteristic UUID 검색
- [ ] `isConnected()`: 상태 확인
- [ ] `sendMetric()`: ILensProtocol 위임
- [ ] `disconnect()`: 연결 해제

**Module 4: ILensProtocol.mc**
- [ ] `buildPayload()`: 5-byte 바이너리 생성
- [ ] Little-Endian 인코딩: 576 → [0x40, 0x02, 0x00, 0x00]
- [ ] NULL 체크
- [ ] Edge cases: 0, MAX_UINT32

### 14.2 Integration Testing

**Scenario 1: Full Connection Flow**
```
1. startScan()
2. onScanResults() → Auto-Pairing
3. pairDevice()
4. onConnectedStateChanged(CONNECTED)
5. discoverServices()
6. discoverCharacteristics()
7. isConnected() == true
8. sendMetric(0x07, 576)
9. nRF Connect 패킷 검증: [0x07, 0x40, 0x02, 0x00, 0x00]
```

**Scenario 2: Metric Transmission**
```
1. 러닝 시작 (onTimerStart)
2. 1Hz 전송 검증 (Throttling)
3. 7개 메트릭 모두 전송 확인
4. iLens 화면에 데이터 표시 확인
```

**Scenario 3: Reconnection**
```
1. 연결 해제 (disconnect)
2. 재연결 (startScan)
3. Auto-Pairing 재사용 (saved device)
4. 5초 이내 재연결 성공
```

### 14.3 System Testing

**Test Case 1: 1시간 러닝 세션**
- [ ] BLE 전송 성공률 >99%
- [ ] CPU 사용률 <5%
- [ ] 배터리 소모 <1%/hour
- [ ] Crash 없음

**Test Case 2: 연결 끊김 및 재연결**
- [ ] iLens 글래스 끄기 → 재연결 (10초 이내)
- [ ] 워치 Bluetooth 끄기/켜기 → 재연결 (5초 이내)

**Test Case 3: Power Metric 정확성**
- [ ] 3-Second Power: 실제 파워와 ±5% 이내
- [ ] Normalized Power: TrainingPeaks 계산과 ±3% 이내

### 14.4 Validation Checklist

- [ ] **UUID 검증**: Service + Characteristic UUID 정확성
- [ ] **프로토콜 검증**: 5-byte 바이너리 패킷 구조
- [ ] **Little-Endian 검증**: nRF Connect 바이트 순서 확인
- [ ] **Metric ID 검증**: 7개 메트릭 ID 매핑 정확성
- [ ] **Scale 검증**: Velocity × 10 정확성
- [ ] **Auto-Pairing 검증**: 첫 발견 기기 자동 저장
- [ ] **Throttling 검증**: 1Hz 전송 주기
- [ ] **Power 계산 검증**: 3-Sec Power, Normalized Power 정확성

---

## Document Metadata

**버전 관리**:
- v3.0 (2025-11-15): 초기 작성 (ActiveLook 100% 복사 전략 기반)
  - 7개 모듈 상세 설계
  - ILens.mc, ILensProtocol.mc 완전 명세
  - 상태 머신, 데이터 흐름 다이어그램
  - 테스트 전략

**참조 문서**:
- PRD-RunVision-IQ.md v3.0
- System-Architecture.md v3.0
- BLE-Protocol-Mapping.md v1.0
- ActiveLook-Source-Analysis-Complete.md
- ActiveLook-Code-Analysis.md

**관련 파일**:
- RunVisionIQView.mc (생성 예정)
- RunVisionIQActivityInfo.mc (생성 예정)
- ILens.mc (생성 예정)
- ILensProtocol.mc (생성 예정)
- properties.xml (생성 예정)
- strings.xml (생성 예정)
- settings.xml (생성 예정)

---

**문서 종료**

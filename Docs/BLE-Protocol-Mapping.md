# BLE Protocol Mapping Guide: ActiveLook → iLens

**문서 버전**: v1.0
**작성일**: 2025-11-15
**프로젝트**: RunVision-IQ (Garmin Connect IQ DataField)
**목적**: ActiveLook BLE 프로토콜을 iLens BLE 프로토콜로 정확히 변환하는 상세 가이드

---

## 📋 Table of Contents

1. [Document Overview](#1-document-overview)
2. [Protocol Architecture Comparison](#2-protocol-architecture-comparison)
3. [UUID Mapping](#3-uuid-mapping)
4. [Protocol Format Comparison](#4-protocol-format-comparison)
5. [Metric-by-Metric Mapping](#5-metric-by-metric-mapping)
6. [Code Transformation Guide](#6-code-transformation-guide)
7. [Validation Checklist](#7-validation-checklist)
8. [Common Pitfalls and Solutions](#8-common-pitfalls-and-solutions)
9. [Testing Strategy](#9-testing-strategy)

---

## 1. Document Overview

### 1.1 Purpose

이 문서는 ActiveLook 스마트 글래스 BLE 프로토콜을 iLens BLE 프로토콜로 변환하는 **완전하고 정확한 매핑 가이드**를 제공합니다.

**핵심 변환 항목**:
- ✅ UUID 변경 (Service + Characteristic)
- ✅ 프로토콜 형식 변경 (텍스트 기반 → 바이너리)
- ✅ 메트릭 ID 매핑 (7개 메트릭)
- ✅ 데이터 인코딩 변경 (ActiveLook 텍스트 → iLens UINT32 Little-Endian)

### 1.2 Scope

**이 문서에서 다루는 것**:
- BLE Service/Characteristic UUID 변경
- 프로토콜 패킷 구조 변환
- 7개 메트릭 매핑 (Velocity, Distance, HR, Cadence, 3 Power Metrics)
- Monkey C 코드 변환 예제

**이 문서에서 다루지 않는 것**:
- BLE 연결 상태 머신 (변경 없음, ActiveLook 로직 재사용)
- Auto-Pairing 로직 (변경 없음, ActiveLook 로직 재사용)
- Throttling 로직 (변경 없음, 1Hz 전송 유지)

### 1.3 Target Audience

- Connect IQ 개발자 (Monkey C)
- RunVision-IQ 프로젝트 구현 담당자
- BLE 프로토콜 검증 담당자

---

## 2. Protocol Architecture Comparison

### 2.1 ActiveLook Protocol (Text-Based)

ActiveLook는 **텍스트 기반 명령어 프로토콜**을 사용합니다.

**패킷 구조**:
```
[0xFF, Command, Length, ...Data..., 0xAA]
```

**예시: 속도 전송 (57.6 km/h)**:
```
텍스트 명령어: "txt(0,\"57.6 km/h\")"
실제 바이트: [0xFF, 0x37, 0x0F, 0x74, 0x78, 0x74, 0x28, 0x30, 0x2C,
              0x22, 0x35, 0x37, 0x2E, 0x36, 0x20, 0x6B, 0x6D, 0x2F, 0x68,
              0x22, 0x29, 0xAA]
패킷 크기: ~22 bytes
```

**특징**:
- ❌ 패킷 크기 큼 (20+ bytes per metric)
- ❌ 파싱 복잡 (텍스트 → 숫자 변환)
- ✅ 디버깅 쉬움 (사람이 읽을 수 있음)

### 2.2 iLens Protocol (Binary)

iLens는 **바이너리 프로토콜**을 사용합니다.

**패킷 구조**:
```
[Metric_ID(1 byte), UINT32(4 bytes, Little-Endian)]
```

**예시: 속도 전송 (57.6 km/h = 576 * 0.1)**:
```
Metric ID: 0x07
Value: 576 (0x0240)
Little-Endian: [0x40, 0x02, 0x00, 0x00]

실제 바이트: [0x07, 0x40, 0x02, 0x00, 0x00]
패킷 크기: 5 bytes
```

**특징**:
- ✅ 패킷 크기 작음 (5 bytes per metric, **77% 감소**)
- ✅ 파싱 단순 (바이너리 → 숫자 직접)
- ❌ 디버깅 어려움 (사람이 읽을 수 없음)

### 2.3 Protocol Efficiency Comparison

| 항목 | ActiveLook | iLens | 개선율 |
|------|-----------|-------|--------|
| **패킷 크기** (1개 메트릭) | ~22 bytes | 5 bytes | **77% 감소** |
| **전송량** (7개 메트릭, 1Hz, 1시간) | ~554 KB | 126 KB | **77% 감소** |
| **파싱 CPU** | 높음 (텍스트) | 낮음 (바이너리) | **~50% 감소** |
| **BLE 충돌 위험** | 중간 | 낮음 | **개선** |

---

## 3. UUID Mapping

### 3.1 Service UUID

| Protocol | Service UUID | 역할 |
|----------|-------------|------|
| **ActiveLook** | `0783b03e-8535-b5a0-7140-a304d2495cb7` | ActiveLook 글래스 전용 서비스 |
| **iLens** | `4b329cf2-3816-498c-8453-ee8798502a08` | iLens 글래스 전용 서비스 |

**Monkey C 코드 변경**:
```monkey-c
// BEFORE (ActiveLook)
var serviceUuid = BluetoothLowEnergy.stringToUuid("0783b03e-8535-b5a0-7140-a304d2495cb7");

// AFTER (iLens)
var serviceUuid = BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08");
```

### 3.2 Characteristic UUID

ActiveLook는 **여러 Characteristic**을 사용하지만, iLens는 **단일 Characteristic**으로 모든 메트릭을 전송합니다.

| Protocol | Characteristic UUID | 역할 | 사용 개수 |
|----------|-------------------|------|----------|
| **ActiveLook** | `0783b03e-8535-b5a0-7140-a304d2495cba` (Tx) | 명령어 전송 | 1개 |
| **ActiveLook** | `0783b03e-8535-b5a0-7140-a304d2495cbb` (Flow) | 흐름 제어 | 1개 (옵션) |
| **ActiveLook** | `0783b03e-8535-b5a0-7140-a304d2495cbf` (Sensor) | 센서 데이터 수신 | 1개 (옵션) |
| **iLens** | `c259c1bd-18d3-c348-b88d-5447aea1b615` (Exercise) | 운동 메트릭 전송 | **1개만** |

**Monkey C 코드 변경**:
```monkey-c
// BEFORE (ActiveLook)
var txUuid = BluetoothLowEnergy.stringToUuid("0783b03e-8535-b5a0-7140-a304d2495cba");
var flowUuid = BluetoothLowEnergy.stringToUuid("0783b03e-8535-b5a0-7140-a304d2495cbb");

// AFTER (iLens) - 단일 Characteristic
var exerciseUuid = BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615");
```

**⚠️ 중요 변경점**:
- ActiveLook: Tx + Flow Characteristic 사용 (명령어 전송 + 흐름 제어)
- iLens: **Exercise Characteristic 하나만** 사용 (모든 메트릭 전송)
- Flow Control 불필요 (바이너리 프로토콜로 충분히 빠름)

---

## 4. Protocol Format Comparison

### 4.1 ActiveLook Command Structure

ActiveLook는 **텍스트 명령어**를 `txt()` 함수로 전송합니다.

**기본 구조**:
```
txt(layout_id, "text_content")
```

**예시**:
```monkey-c
// 속도 전송 (57.6 km/h)
var command = "txt(0,\"57.6 km/h\")";

// 심박수 전송 (145 bpm)
var command = "txt(1,\"145 bpm\")";

// 거리 전송 (5.2 km)
var command = "txt(2,\"5.2 km\")";
```

**패킷 인코딩 과정**:
1. 문자열 생성: `"txt(0,\"57.6 km/h\")"`
2. UTF-8 바이트 배열 변환: `[0x74, 0x78, 0x74, 0x28, ...]`
3. 패킷 래핑: `[0xFF, 0x37, len, ...data..., 0xAA]`

**문제점**:
- 📦 패킷 크기 큼 (20+ bytes)
- 🐢 문자열 생성 오버헤드
- 🔢 숫자 → 문자열 변환 필요

### 4.2 iLens Binary Structure

iLens는 **5바이트 바이너리 패킷**을 전송합니다.

**기본 구조**:
```
[Metric_ID, Value_Byte0, Value_Byte1, Value_Byte2, Value_Byte3]
```

**예시**:
```monkey-c
// 속도 전송 (57.6 km/h = 576 in 0.1 km/h units)
var payload = [0x07, 0x40, 0x02, 0x00, 0x00];

// 심박수 전송 (145 bpm)
var payload = [0x0B, 0x91, 0x00, 0x00, 0x00];

// 거리 전송 (5200 meters)
var payload = [0x06, 0x50, 0x14, 0x00, 0x00];
```

**패킷 인코딩 과정**:
1. 숫자 → UINT32 변환: `576`
2. Little-Endian 바이트 배열: `[0x40, 0x02, 0x00, 0x00]`
3. Metric ID 추가: `[0x07, 0x40, 0x02, 0x00, 0x00]`

**장점**:
- 📦 패킷 크기 작음 (5 bytes, **77% 감소**)
- 🚀 바이너리 직접 전송 (오버헤드 없음)
- 🔢 숫자 그대로 사용 (변환 불필요)

---

## 5. Metric-by-Metric Mapping

### 5.1 Mapping Table

| Metric | Unit | ActiveLook | iLens | Scale | 예시 |
|--------|------|-----------|-------|-------|------|
| **Velocity** | km/h | txt(0, "57.6 km/h") | 0x07, 576 (0.1 km/h) | 실제값 × 10 | 57.6 → 576 |
| **Distance** | m | txt(2, "5200 m") | 0x06, 5200 | 실제값 | 5200 → 5200 |
| **Heart Rate** | bpm | txt(1, "145 bpm") | 0x0B, 145 | 실제값 | 145 → 145 |
| **Cadence** | spm | txt(3, "176 spm") | 0x0E, 176 | 실제값 | 176 → 176 |
| **3-Second Power** | W | txt(4, "250 W") | 0x11, 250 | 실제값 | 250 → 250 |
| **Normalized Power** | W | txt(5, "240 W") | 0x12, 240 | 실제값 | 240 → 240 |
| **Instant Power** | W | txt(6, "255 W") | 0x13, 255 | 실제값 | 255 → 255 |

### 5.2 Detailed Metric Mapping

#### 5.2.1 Velocity (속도)

**ActiveLook**:
```monkey-c
var speedKmh = 57.6;
var command = "txt(0,\"" + speedKmh.format("%.1f") + " km/h\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var speedKmh = 57.6;
var speedScaled = (speedKmh * 10).toNumber();  // 576
sendMetric(0x07, speedScaled);
```

**변환 로직**:
1. **Scale 적용**: 실제값 × 10 (소수점 1자리 보존)
2. **Metric ID**: 0x07
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0F, 0x74, 0x78, 0x74, 0x28, 0x30, 0x2C,
             0x22, 0x35, 0x37, 0x2E, 0x36, 0x20, 0x6B, 0x6D, 0x2F, 0x68,
             0x22, 0x29, 0xAA]  (22 bytes)

iLens:      [0x07, 0x40, 0x02, 0x00, 0x00]  (5 bytes, 77% reduction)
```

#### 5.2.2 Distance (거리)

**ActiveLook**:
```monkey-c
var distanceM = 5200;
var command = "txt(2,\"" + distanceM.format("%d") + " m\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var distanceM = 5200;
sendMetric(0x06, distanceM);
```

**변환 로직**:
1. **Scale 적용**: 없음 (미터 그대로)
2. **Metric ID**: 0x06
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0C, 0x74, 0x78, 0x74, 0x28, 0x32, 0x2C,
             0x22, 0x35, 0x32, 0x30, 0x30, 0x20, 0x6D, 0x22, 0x29, 0xAA]  (19 bytes)

iLens:      [0x06, 0x50, 0x14, 0x00, 0x00]  (5 bytes, 74% reduction)
```

#### 5.2.3 Heart Rate (심박수)

**ActiveLook**:
```monkey-c
var heartRate = 145;
var command = "txt(1,\"" + heartRate.format("%d") + " bpm\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var heartRate = 145;
sendMetric(0x0B, heartRate);
```

**변환 로직**:
1. **Scale 적용**: 없음 (bpm 그대로)
2. **Metric ID**: 0x0B
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0D, 0x74, 0x78, 0x74, 0x28, 0x31, 0x2C,
             0x22, 0x31, 0x34, 0x35, 0x20, 0x62, 0x70, 0x6D, 0x22, 0x29, 0xAA]  (20 bytes)

iLens:      [0x0B, 0x91, 0x00, 0x00, 0x00]  (5 bytes, 75% reduction)
```

#### 5.2.4 Cadence (케이던스)

**ActiveLook**:
```monkey-c
var cadence = 176;
var command = "txt(3,\"" + cadence.format("%d") + " spm\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var cadence = 176;
sendMetric(0x0E, cadence);
```

**변환 로직**:
1. **Scale 적용**: 없음 (spm 그대로)
2. **Metric ID**: 0x0E
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0D, 0x74, 0x78, 0x74, 0x28, 0x33, 0x2C,
             0x22, 0x31, 0x37, 0x36, 0x20, 0x73, 0x70, 0x6D, 0x22, 0x29, 0xAA]  (20 bytes)

iLens:      [0x0E, 0xB0, 0x00, 0x00, 0x00]  (5 bytes, 75% reduction)
```

#### 5.2.5 3-Second Power (3초 평균 파워)

**ActiveLook**:
```monkey-c
var threeSecPower = 250;
var command = "txt(4,\"" + threeSecPower.format("%d") + " W\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var threeSecPower = 250;
sendMetric(0x11, threeSecPower);
```

**변환 로직**:
1. **Scale 적용**: 없음 (W 그대로)
2. **Metric ID**: 0x11
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0B, 0x74, 0x78, 0x74, 0x28, 0x34, 0x2C,
             0x22, 0x32, 0x35, 0x30, 0x20, 0x57, 0x22, 0x29, 0xAA]  (18 bytes)

iLens:      [0x11, 0xFA, 0x00, 0x00, 0x00]  (5 bytes, 72% reduction)
```

#### 5.2.6 Normalized Power (정규화 파워)

**ActiveLook**:
```monkey-c
var normalizedPower = 240;
var command = "txt(5,\"" + normalizedPower.format("%d") + " W\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var normalizedPower = 240;
sendMetric(0x12, normalizedPower);
```

**변환 로직**:
1. **Scale 적용**: 없음 (W 그대로)
2. **Metric ID**: 0x12
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0B, 0x74, 0x78, 0x74, 0x28, 0x35, 0x2C,
             0x22, 0x32, 0x34, 0x30, 0x20, 0x57, 0x22, 0x29, 0xAA]  (18 bytes)

iLens:      [0x12, 0xF0, 0x00, 0x00, 0x00]  (5 bytes, 72% reduction)
```

#### 5.2.7 Instantaneous Power (순간 파워)

**ActiveLook**:
```monkey-c
var power = 255;
var command = "txt(6,\"" + power.format("%d") + " W\")";
sendCommand(command);
```

**iLens**:
```monkey-c
var power = 255;
sendMetric(0x13, power);
```

**변환 로직**:
1. **Scale 적용**: 없음 (W 그대로)
2. **Metric ID**: 0x13
3. **Value**: UINT32 (Little-Endian)

**패킷 비교**:
```
ActiveLook: [0xFF, 0x37, 0x0B, 0x74, 0x78, 0x74, 0x28, 0x36, 0x2C,
             0x22, 0x32, 0x35, 0x35, 0x20, 0x57, 0x22, 0x29, 0xAA]  (18 bytes)

iLens:      [0x13, 0xFF, 0x00, 0x00, 0x00]  (5 bytes, 72% reduction)
```

---

## 6. Code Transformation Guide

### 6.1 ActiveLook Code Structure

**ActiveLookSDK_next.mc** (원본):
```monkey-c
module ActiveLookSDK_next {
    // 텍스트 명령어 전송
    function sendCommand(command) {
        if (_txCharacteristic == null) { return; }

        var cmdBytes = stringToBytes(command);
        var packet = buildPacket(cmdBytes);

        try {
            _txCharacteristic.requestWrite(packet, {
                :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
            });
        } catch (ex) {
            (:debug) System.println("BLE Write failed: " + ex.getErrorMessage());
        }
    }

    // 문자열 → 바이트 배열 변환
    function stringToBytes(str) {
        var bytes = [];
        for (var i = 0; i < str.length(); i++) {
            bytes.add(str.substring(i, i+1).toNumber());
        }
        return bytes;
    }

    // 패킷 래핑 [0xFF, cmd, len, ...data..., 0xAA]
    function buildPacket(data) {
        var packet = new [data.size() + 4]b;
        packet[0] = 0xFF;
        packet[1] = 0x37;  // txt command
        packet[2] = data.size();
        for (var i = 0; i < data.size(); i++) {
            packet[3 + i] = data[i];
        }
        packet[packet.size() - 1] = 0xAA;
        return packet;
    }
}
```

### 6.2 iLens Code Structure

**ILensProtocol.mc** (변환):
```monkey-c
module ILensProtocol {
    // 바이너리 메트릭 전송
    function sendMetric(characteristic, metricId, value) {
        if (characteristic == null) { return; }

        var payload = buildPayload(metricId, value);

        try {
            characteristic.requestWrite(payload, {
                :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
            });
        } catch (ex) {
            (:debug) System.println("BLE Write failed: " + ex.getErrorMessage());
        }
    }

    // 5바이트 바이너리 패킷 생성
    function buildPayload(metricId, value) {
        var payload = new [5]b;

        // Metric ID
        payload[0] = metricId;

        // UINT32 Little-Endian
        var valueInt = value.toNumber();
        payload[1] = (valueInt & 0xFF);
        payload[2] = ((valueInt >> 8) & 0xFF);
        payload[3] = ((valueInt >> 16) & 0xFF);
        payload[4] = ((valueInt >> 24) & 0xFF);

        return payload;
    }
}
```

### 6.3 Step-by-Step Transformation

#### Step 1: Replace Module Name
```monkey-c
// BEFORE
module ActiveLookSDK_next { ... }

// AFTER
module ILensProtocol { ... }
```

#### Step 2: Replace Function Signature
```monkey-c
// BEFORE
function sendCommand(command)  // 문자열 입력

// AFTER
function sendMetric(characteristic, metricId, value)  // 바이너리 입력
```

#### Step 3: Replace Encoding Logic
```monkey-c
// BEFORE (텍스트 기반)
var cmdBytes = stringToBytes(command);
var packet = buildPacket(cmdBytes);

// AFTER (바이너리 기반)
var payload = buildPayload(metricId, value);
```

#### Step 4: Replace Packet Building
```monkey-c
// BEFORE (텍스트 패킷)
function buildPacket(data) {
    var packet = new [data.size() + 4]b;
    packet[0] = 0xFF;
    packet[1] = 0x37;
    packet[2] = data.size();
    for (var i = 0; i < data.size(); i++) {
        packet[3 + i] = data[i];
    }
    packet[packet.size() - 1] = 0xAA;
    return packet;
}

// AFTER (바이너리 패킷)
function buildPayload(metricId, value) {
    var payload = new [5]b;
    payload[0] = metricId;

    var valueInt = value.toNumber();
    payload[1] = (valueInt & 0xFF);
    payload[2] = ((valueInt >> 8) & 0xFF);
    payload[3] = ((valueInt >> 16) & 0xFF);
    payload[4] = ((valueInt >> 24) & 0xFF);

    return payload;
}
```

### 6.4 Usage Comparison

#### BEFORE (ActiveLook)
```monkey-c
using ActiveLookSDK_next as SDK;

function sendSpeed(speedKmh) {
    var command = "txt(0,\"" + speedKmh.format("%.1f") + " km/h\")";
    SDK.sendCommand(command);
}

function sendHeartRate(hr) {
    var command = "txt(1,\"" + hr.format("%d") + " bpm\")";
    SDK.sendCommand(command);
}

function sendDistance(distanceM) {
    var command = "txt(2,\"" + distanceM.format("%d") + " m\")";
    SDK.sendCommand(command);
}
```

#### AFTER (iLens)
```monkey-c
using ILensProtocol as Proto;

function sendSpeed(speedKmh) {
    var speedScaled = (speedKmh * 10).toNumber();
    Proto.sendMetric(_exerciseCharacteristic, 0x07, speedScaled);
}

function sendHeartRate(hr) {
    Proto.sendMetric(_exerciseCharacteristic, 0x0B, hr);
}

function sendDistance(distanceM) {
    Proto.sendMetric(_exerciseCharacteristic, 0x06, distanceM);
}
```

**코드 라인 수 비교**:
- ActiveLook: 3 lines per metric (문자열 포맷팅 + 전송)
- iLens: 1-2 lines per metric (스케일링 + 전송)
- **33-50% 코드 감소**

---

## 7. Validation Checklist

### 7.1 UUID Validation

- [ ] **Service UUID 변경 확인**
  - [ ] ActiveLook UUID `0783b03e-8535-b5a0-7140-a304d2495cb7` 제거
  - [ ] iLens UUID `4b329cf2-3816-498c-8453-ee8798502a08` 추가
  - [ ] `BluetoothLowEnergy.stringToUuid()` 호출 검증

- [ ] **Characteristic UUID 변경 확인**
  - [ ] ActiveLook Tx UUID `0783b03e-8535-b5a0-7140-a304d2495cba` 제거
  - [ ] ActiveLook Flow UUID `0783b03e-8535-b5a0-7140-a304d2495cbb` 제거 (사용 안 함)
  - [ ] iLens Exercise UUID `c259c1bd-18d3-c348-b88d-5447aea1b615` 추가
  - [ ] 단일 Characteristic만 사용하는지 확인

### 7.2 Protocol Validation

- [ ] **패킷 구조 검증**
  - [ ] 패킷 크기 5바이트 확인
  - [ ] Metric ID (1 byte) 위치 확인
  - [ ] UINT32 (4 bytes) Little-Endian 확인

- [ ] **Little-Endian 인코딩 검증**
  - [ ] `payload[1] = (value & 0xFF)` (LSB)
  - [ ] `payload[2] = ((value >> 8) & 0xFF)`
  - [ ] `payload[3] = ((value >> 16) & 0xFF)`
  - [ ] `payload[4] = ((value >> 24) & 0xFF)` (MSB)

- [ ] **텍스트 코드 제거 확인**
  - [ ] `stringToBytes()` 함수 제거
  - [ ] `buildPacket()` 함수 제거
  - [ ] `txt()` 명령어 생성 코드 제거
  - [ ] `format()` 문자열 포맷팅 제거

### 7.3 Metric Mapping Validation

각 메트릭별로 다음을 검증:

**Velocity (0x07)**:
- [ ] Scale 적용: `speedKmh * 10`
- [ ] Metric ID: `0x07`
- [ ] 단위: 0.1 km/h
- [ ] 예시 검증: 57.6 km/h → 576

**Distance (0x06)**:
- [ ] Scale 적용: 없음
- [ ] Metric ID: `0x06`
- [ ] 단위: meters
- [ ] 예시 검증: 5200 m → 5200

**Heart Rate (0x0B)**:
- [ ] Scale 적용: 없음
- [ ] Metric ID: `0x0B`
- [ ] 단위: bpm
- [ ] 예시 검증: 145 bpm → 145

**Cadence (0x0E)**:
- [ ] Scale 적용: 없음
- [ ] Metric ID: `0x0E`
- [ ] 단위: spm
- [ ] 예시 검증: 176 spm → 176

**3-Second Power (0x11)**:
- [ ] Scale 적용: 없음
- [ ] Metric ID: `0x11`
- [ ] 단위: W
- [ ] 예시 검증: 250 W → 250

**Normalized Power (0x12)**:
- [ ] Scale 적용: 없음
- [ ] Metric ID: `0x12`
- [ ] 단위: W
- [ ] 예시 검증: 240 W → 240

**Instantaneous Power (0x13)**:
- [ ] Scale 적용: 없음
- [ ] Metric ID: `0x13`
- [ ] 단위: W
- [ ] 예시 검증: 255 W → 255

### 7.4 Code Transformation Validation

- [ ] **모듈 이름 변경**
  - [ ] `ActiveLookSDK_next` → `ILensProtocol`

- [ ] **함수 시그니처 변경**
  - [ ] `sendCommand(command)` → `sendMetric(characteristic, metricId, value)`

- [ ] **바이너리 인코딩 구현**
  - [ ] `buildPayload(metricId, value)` 함수 추가
  - [ ] Little-Endian 변환 로직 추가

- [ ] **호출 코드 변경**
  - [ ] 모든 `sendCommand()` 호출 → `sendMetric()` 호출로 변경
  - [ ] 문자열 포맷팅 제거
  - [ ] Metric ID 추가
  - [ ] Scale 적용 (Velocity만)

### 7.5 Testing Validation

- [ ] **Unit Test**
  - [ ] `buildPayload()` 함수 테스트 (7개 메트릭)
  - [ ] Little-Endian 인코딩 테스트
  - [ ] Edge case 테스트 (0, MAX_UINT32, NULL)

- [ ] **Integration Test**
  - [ ] iLens 글래스 실제 연결 테스트
  - [ ] 7개 메트릭 전송 및 수신 확인
  - [ ] BLE 패킷 캡처 및 검증 (nRF Connect 사용)

- [ ] **Performance Test**
  - [ ] 1Hz 전송 성공률 측정 (>99%)
  - [ ] BLE Write 지연시간 측정 (<100ms)
  - [ ] CPU 사용률 비교 (ActiveLook vs iLens)

---

## 8. Common Pitfalls and Solutions

### 8.1 Pitfall #1: Endianness Confusion

**문제**:
```monkey-c
// WRONG: Big-Endian (MSB first)
payload[1] = ((value >> 24) & 0xFF);
payload[2] = ((value >> 16) & 0xFF);
payload[3] = ((value >> 8) & 0xFF);
payload[4] = (value & 0xFF);

// 예시: 576 → [0x00, 0x00, 0x02, 0x40] (잘못됨!)
```

**해결**:
```monkey-c
// CORRECT: Little-Endian (LSB first)
payload[1] = (value & 0xFF);
payload[2] = ((value >> 8) & 0xFF);
payload[3] = ((value >> 16) & 0xFF);
payload[4] = ((value >> 24) & 0xFF);

// 예시: 576 → [0x40, 0x02, 0x00, 0x00] (올바름!)
```

**검증 방법**:
```monkey-c
// Test case
var value = 576;
var payload = buildPayload(0x07, value);

// Expected: [0x07, 0x40, 0x02, 0x00, 0x00]
// payload[0] == 0x07
// payload[1] == 0x40  (LSB)
// payload[2] == 0x02
// payload[3] == 0x00
// payload[4] == 0x00  (MSB)
```

### 8.2 Pitfall #2: Velocity Scale Forgotten

**문제**:
```monkey-c
// WRONG: 속도 그대로 전송
var speedKmh = 57.6;
sendMetric(0x07, speedKmh);  // 57 전송 (소수점 손실!)
```

**해결**:
```monkey-c
// CORRECT: 속도 * 10 전송
var speedKmh = 57.6;
var speedScaled = (speedKmh * 10).toNumber();  // 576
sendMetric(0x07, speedScaled);
```

**검증 방법**:
```monkey-c
// Test case
var speedKmh = 57.6;
var speedScaled = (speedKmh * 10).toNumber();

// Expected: 576
// speedScaled == 576
```

### 8.3 Pitfall #3: NULL Value Handling

**문제**:
```monkey-c
// WRONG: NULL 체크 없음
var hr = info.currentHeartRate;  // NULL 가능
sendMetric(0x0B, hr);  // Crash!
```

**해결**:
```monkey-c
// CORRECT: NULL 체크 추가
var hr = info.currentHeartRate;
if (hr != null) {
    sendMetric(0x0B, hr);
}
```

### 8.4 Pitfall #4: Float to Int Conversion

**문제**:
```monkey-c
// WRONG: Float 그대로 전송
var power = 250.7;
sendMetric(0x11, power);  // 소수점 처리 불확실
```

**해결**:
```monkey-c
// CORRECT: 명시적 Integer 변환
var power = 250.7;
sendMetric(0x11, power.toNumber());  // 250 (소수점 버림)
```

### 8.5 Pitfall #5: Multiple Characteristic Confusion

**문제**:
```monkey-c
// WRONG: ActiveLook처럼 여러 Characteristic 사용
var txChar = service.getCharacteristic(txUuid);
var flowChar = service.getCharacteristic(flowUuid);
```

**해결**:
```monkey-c
// CORRECT: iLens는 Exercise Characteristic 하나만
var exerciseChar = service.getCharacteristic(exerciseUuid);
```

### 8.6 Pitfall #6: Packet Size Assumption

**문제**:
```monkey-c
// WRONG: 가변 길이 패킷 가정
var payload = new [metricData.size()]b;  // 크기 달라짐
```

**해결**:
```monkey-c
// CORRECT: iLens는 항상 5바이트 고정
var payload = new [5]b;  // 고정 크기
```

### 8.7 Pitfall #7: Write Type Mismatch

**문제**:
```monkey-c
// WRONG: 잘못된 Write Type
characteristic.requestWrite(payload, {
    :writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE
});
```

**해결**:
```monkey-c
// CORRECT: iLens는 WRITE_TYPE_DEFAULT 사용
characteristic.requestWrite(payload, {
    :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT
});
```

---

## 9. Testing Strategy

### 9.1 Unit Testing

**테스트 대상**: `ILensProtocol.buildPayload()`

**Test Case 1: Basic Payload Construction**
```monkey-c
// Test: Velocity 576 (57.6 km/h)
var payload = ILensProtocol.buildPayload(0x07, 576);

// Assert
assert(payload.size() == 5);
assert(payload[0] == 0x07);
assert(payload[1] == 0x40);  // LSB
assert(payload[2] == 0x02);
assert(payload[3] == 0x00);
assert(payload[4] == 0x00);  // MSB
```

**Test Case 2: All 7 Metrics**
```monkey-c
// Velocity
var p1 = ILensProtocol.buildPayload(0x07, 576);
assert(p1[0] == 0x07 && p1[1] == 0x40 && p1[2] == 0x02);

// Distance
var p2 = ILensProtocol.buildPayload(0x06, 5200);
assert(p2[0] == 0x06 && p2[1] == 0x50 && p2[2] == 0x14);

// Heart Rate
var p3 = ILensProtocol.buildPayload(0x0B, 145);
assert(p3[0] == 0x0B && p3[1] == 0x91 && p3[2] == 0x00);

// Cadence
var p4 = ILensProtocol.buildPayload(0x0E, 176);
assert(p4[0] == 0x0E && p4[1] == 0xB0 && p4[2] == 0x00);

// 3-Second Power
var p5 = ILensProtocol.buildPayload(0x11, 250);
assert(p5[0] == 0x11 && p5[1] == 0xFA && p5[2] == 0x00);

// Normalized Power
var p6 = ILensProtocol.buildPayload(0x12, 240);
assert(p6[0] == 0x12 && p6[1] == 0xF0 && p6[2] == 0x00);

// Instantaneous Power
var p7 = ILensProtocol.buildPayload(0x13, 255);
assert(p7[0] == 0x13 && p7[1] == 0xFF && p7[2] == 0x00);
```

**Test Case 3: Edge Cases**
```monkey-c
// Zero value
var p1 = ILensProtocol.buildPayload(0x07, 0);
assert(p1[1] == 0x00 && p1[2] == 0x00 && p1[3] == 0x00 && p1[4] == 0x00);

// Max UINT32
var p2 = ILensProtocol.buildPayload(0x07, 0xFFFFFFFF);
assert(p2[1] == 0xFF && p2[2] == 0xFF && p2[3] == 0xFF && p2[4] == 0xFF);

// Negative value (should be clamped to 0)
var p3 = ILensProtocol.buildPayload(0x07, -100);
// Monkey C behavior: negative → 0 or error
```

### 9.2 Integration Testing

**테스트 환경**:
- Garmin 워치 실물 (Forerunner 265/955/965)
- iLens 글래스 실물
- nRF Connect 앱 (BLE 패킷 캡처)

**Test Scenario 1: Full Connection Flow**
```
1. 워치에서 DataField 실행
2. iLens 글래스 자동 스캔 및 연결
3. 7개 메트릭 전송 (1Hz)
4. iLens 화면에 데이터 표시 확인
5. nRF Connect로 패킷 캡처 및 검증
```

**Test Scenario 2: Packet Verification**
```
1. nRF Connect로 iLens Service (4b329cf2...) 연결
2. Exercise Characteristic (c259c1bd...) 모니터링
3. 워치에서 러닝 시작
4. 캡처된 패킷 분석:
   - 패킷 크기: 5 bytes
   - Metric ID: 0x07, 0x06, 0x0B, 0x0E, 0x11, 0x12, 0x13
   - Little-Endian 확인
```

**Test Scenario 3: Performance Test**
```
1. 1시간 러닝 세션
2. 전송 성공률 측정: >99%
3. BLE Write 지연시간: <100ms
4. CPU 사용률: <5%
5. 배터리 소모: <1%/hour
```

### 9.3 Regression Testing

**회귀 테스트 체크리스트**:
- [ ] ActiveLook 코드 제거 후 빌드 성공
- [ ] iLens 연결 성공 (Auto-Pairing)
- [ ] 7개 메트릭 모두 전송 및 표시
- [ ] 1Hz Throttling 정상 작동
- [ ] BLE 재연결 정상 작동
- [ ] 배터리 소모 정상 범위 (<1%/hour)
- [ ] UI 업데이트 정상 (DataFieldView.compute())

---

## 10. Summary and Quick Reference

### 10.1 Key Changes Summary

| 항목 | ActiveLook | iLens | 변경 유형 |
|------|-----------|-------|----------|
| **Service UUID** | 0783b03e-... | 4b329cf2-... | ⚠️ BREAKING |
| **Characteristic UUID** | 0783b03e-...-cba (Tx) | c259c1bd-... (Exercise) | ⚠️ BREAKING |
| **Protocol Type** | Text-based | Binary | ⚠️ BREAKING |
| **Packet Size** | ~20 bytes | 5 bytes | ✅ IMPROVEMENT |
| **Encoding** | UTF-8 String | UINT32 Little-Endian | ⚠️ BREAKING |
| **Metric Count** | 4 | 7 | ✅ ENHANCEMENT |
| **Scale (Velocity)** | km/h as string | 0.1 km/h as int | ⚠️ BREAKING |

### 10.2 Quick Reference Table

| Metric | ActiveLook | iLens | Scale | 예시 변환 |
|--------|-----------|-------|-------|----------|
| **Velocity** | `txt(0,"57.6 km/h")` | `0x07, 576` | × 10 | 57.6 → 576 |
| **Distance** | `txt(2,"5200 m")` | `0x06, 5200` | - | 5200 → 5200 |
| **Heart Rate** | `txt(1,"145 bpm")` | `0x0B, 145` | - | 145 → 145 |
| **Cadence** | `txt(3,"176 spm")` | `0x0E, 176` | - | 176 → 176 |
| **3-Sec Power** | `txt(4,"250 W")` | `0x11, 250` | - | 250 → 250 |
| **Norm Power** | `txt(5,"240 W")` | `0x12, 240` | - | 240 → 240 |
| **Instant Power** | `txt(6,"255 W")` | `0x13, 255` | - | 255 → 255 |

### 10.3 Code Snippet Quick Copy

**iLens sendMetric() 완전 구현**:
```monkey-c
module ILensProtocol {
    function sendMetric(characteristic, metricId, value) {
        if (characteristic == null) { return; }

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

**UUID 정의**:
```monkey-c
// iLens Service UUID
var serviceUuid = BluetoothLowEnergy.stringToUuid(
    "4b329cf2-3816-498c-8453-ee8798502a08"
);

// iLens Exercise Characteristic UUID
var exerciseUuid = BluetoothLowEnergy.stringToUuid(
    "c259c1bd-18d3-c348-b88d-5447aea1b615"
);
```

**7개 메트릭 전송 예제**:
```monkey-c
function sendAllMetrics(info) {
    var ilens = ILens.getInstance();
    if (!ilens.isConnected()) { return; }

    var speed = extractSpeed(info);
    var distance = extractDistance(info);
    var hr = extractHeartRate(info);
    var cadence = extractCadence(info);
    var threeSecPower = _activityInfo.getThreeSecPower();
    var normalizedPower = _activityInfo.getNormalizedPower();
    var power = extractPower(info);

    if (speed != null) {
        var speedScaled = (speed * 10).toNumber();
        ilens.sendMetric(0x07, speedScaled);
    }
    if (distance != null) { ilens.sendMetric(0x06, distance); }
    if (hr != null) { ilens.sendMetric(0x0B, hr); }
    if (cadence != null) { ilens.sendMetric(0x0E, cadence); }
    if (threeSecPower != null) { ilens.sendMetric(0x11, threeSecPower); }
    if (normalizedPower != null) { ilens.sendMetric(0x12, normalizedPower); }
    if (power != null) { ilens.sendMetric(0x13, power); }
}
```

---

## 11. Appendix

### 11.1 iLens BLE Specification Reference

**Service UUID**: `4b329cf2-3816-498c-8453-ee8798502a08`
**Characteristic UUID**: `c259c1bd-18d3-c348-b88d-5447aea1b615`
**Properties**: Write, Write Without Response

**Metric ID Reference**:
```
0x06 = Distance (meters)
0x07 = Velocity (0.1 km/h)
0x0B = Heart Rate (bpm)
0x0E = Cadence (spm)
0x11 = 3-Second Power (W)
0x12 = Normalized Power (W)
0x13 = Instantaneous Power (W)
```

### 11.2 ActiveLook BLE Specification Reference

**Service UUID**: `0783b03e-8535-b5a0-7140-a304d2495cb7`
**Tx Characteristic UUID**: `0783b03e-8535-b5a0-7140-a304d2495cba`
**Flow Characteristic UUID**: `0783b03e-8535-b5a0-7140-a304d2495cbb`
**Properties**: Write, Notify

**Command Reference**:
```
txt(layout_id, "text_content")
```

### 11.3 Byte Order Reference

**Little-Endian** (Intel, ARM, iLens):
```
Value: 0x12345678
Bytes: [0x78, 0x56, 0x34, 0x12]
       LSB              MSB
```

**Big-Endian** (Network, Motorola):
```
Value: 0x12345678
Bytes: [0x12, 0x34, 0x56, 0x78]
       MSB              LSB
```

**iLens는 Little-Endian 사용!**

### 11.4 Monkey C Bit Operations Reference

```monkey-c
// Extract LSB (Least Significant Byte)
var lsb = (value & 0xFF);

// Extract 2nd byte
var byte2 = ((value >> 8) & 0xFF);

// Extract 3rd byte
var byte3 = ((value >> 16) & 0xFF);

// Extract MSB (Most Significant Byte)
var msb = ((value >> 24) & 0xFF);
```

---

## Document Metadata

**버전 관리**:
- v1.0 (2025-11-15): 초기 작성
  - 프로토콜 비교 분석
  - 7개 메트릭 상세 매핑
  - 코드 변환 가이드
  - 검증 체크리스트

**참조 문서**:
- PRD-RunVision-IQ.md v3.0
- System-Architecture.md v3.0
- iLens BLE V1.0.10.pdf
- ActiveLook-Code-Analysis.md
- ActiveLook-Source-Analysis-Complete.md

**관련 파일**:
- ILensProtocol.mc (생성 예정)
- ILens.mc (생성 예정)
- RunVisionIQView.mc (생성 예정)

---

**문서 종료**

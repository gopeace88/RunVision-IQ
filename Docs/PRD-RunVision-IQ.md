# RunVision-IQ - Product Requirements Document (PRD)

**버전**: 3.0
**작성일**: 2025-11-15
**최종 수정일**: 2025-11-15
**작성자**: Development Team
**상태**: Ready for Implementation
**앱 타입**: DataField (Plugin)

---

## 📋 v3.0 주요 변경사항

**v2.0 → v3.0 전략 변경**:

| 항목 | v2.0 전략 | v3.0 전략 (최종) | 변경 이유 |
|------|----------|-----------------|----------|
| **코드 재사용** | 90% 재사용, 간소화 | **100% 복사** | 검증된 안정성 최대화 |
| **통계 계산** | ❌ 제거 (간소화) | ✅ **유지** (ActiveLook 로직 재사용) | iLens가 파워 메트릭 지원 (0x11~0x13) |
| **메트릭 개수** | 4개 (기본만) | **7개** (기본 4 + 파워 3) | iLens 고급 기능 활용 |
| **BLE 교체** | 단순 프로토콜 변경 | **모듈 단위 교체** | ActiveLook.mc → ILens.mc, SDK → Protocol |
| **Pairing** | ❌ 미정의 | ✅ **Auto-Pairing** | ActiveLook properties.xml 방식 채택 |
| **개발 기간** | 2-3주 | **4주** | 통계 계산 추가로 1주 증가 |

**핵심 결정**:
- ✅ **ActiveLook 100% 복사**: 검증된 DataField 패턴 완전 재사용
- ✅ **BLE 레이어만 교체**: 2개 모듈 (`ActiveLook.mc` → `ILens.mc`, `ActiveLookSDK_next.mc` → `ILensProtocol.mc`)
- ✅ **통계 계산 유지**: 3-Second Power, Normalized Power 로직 재사용
- ✅ **7개 메트릭 전송**: iLens가 지원하는 파워 메트릭 활용 (ActiveLook 글래스는 미지원)
- ✅ **Auto-Pairing**: `ilens_name` property로 첫 발견 기기 자동 저장

---

## 1. 제품 개요

### 1.1 제품 비전

**RunVision-IQ**는 Garmin 워치의 Native Run/Bike 앱에서 실행되는 **DataField 플러그인**으로, Garmin OS가 수집한 러닝/사이클링 데이터를 iLens AR 스마트 글래스에 실시간 전송합니다.

**핵심 가치 제안**:
- 🔌 **Plugin 방식**: Garmin Run/Bike 앱 내에서 동작, GPS/센서 관리 불필요
- 📊 **고급 메트릭**: 속도, 거리, 심박수, 케이던스 + **3-Second Power, Normalized Power**
- 🚀 **빠른 개발**: ActiveLook 검증된 코드 100% 재사용, BLE만 교체
- 🔗 **Auto-Pairing**: 첫 발견 iLens 자동 저장, 재연결 자동

### 1.2 문제 정의 및 해결책

**기존 접근 (Activity App)**:
- GPS, 센서, Activity Recording, FIT 파일 모두 직접 구현
- 개발 기간: 6-8주
- 복잡도: ⭐⭐⭐⭐⭐

**RunVision-IQ (DataField, ActiveLook 기반)**:
- ActiveLook 검증된 DataField 100% 복사
- BLE 레이어만 교체 (ActiveLook → iLens 프로토콜)
- 통계 계산 로직 재사용 (3-second power, normalized power)
- **개발 기간: 4주** (BLE 교체 3주 + 테스트 1주)
- 복잡도: ⭐⭐

### 1.3 타겟 사용자

**Primary Persona**: 기존 Garmin Run/Bike 사용자

- Garmin Run/Bike 앱 익숙
- Forerunner 265/955/965 또는 Fenix 7 보유 (BLE Central 지원)
- iLens AR 글래스 소유
- 러닝/사이클링 중 실시간 메트릭을 AR로 보고 싶음
- **파워 메트릭 관심** (사이클리스트, 진지한 러너)
- 추가 앱 설치 거부감, 기존 워크플로우 선호

**Secondary Persona**: 미니멀리스트 운동자

- Phone 없이 워치만으로 운동
- 복잡한 설정 싫어함
- Garmin Connect 자동 동기화 선호

### 1.4 기기 호환성

**Garmin 워치 요구사항**:

| 모델 | BLE Central | Connect IQ 4.0+ | 검증 상태 | 비고 |
|------|------------|----------------|----------|------|
| **Forerunner 265** | ✅ | ✅ | 📋 Phase 1 | 주요 타겟 |
| **Forerunner 965** | ✅ | ✅ | 📋 Phase 1 | 프리미엄 모델 |
| **Forerunner 955** | ✅ | ✅ | 📋 Phase 1 | - |
| **Fenix 7 Series** | ✅ | ✅ | 📋 Phase 2 | - |
| **Forerunner 255** | ❌ | ✅ | ❌ Unsupported | BLE Central 미지원 |

**필수 요구사항**:
- **BLE Central** 지원 (2022년 이후 고급 모델만)
- Connect IQ SDK 4.0+
- Monkey C 런타임

**iLens 호환성**:

| 모델 | BLE 프로토콜 | 펌웨어 | 검증 상태 |
|------|-------------|--------|----------|
| **iLens Series 1** | v1.0.10+ | v2.0+ | 📋 Planned |
| **iLens Series 2** | v1.0.10+ | v2.5+ | 📋 Planned |

**Service UUID**: `4b329cf2-3816-498c-8453-ee8798502a08`
**Exercise Characteristic UUID**: `c259c1bd-18d3-c348-b88d-5447aea1b615`

---

## 2. 제품 철학

### 2.1 핵심 원칙

**Principle 1: 100% Code Reuse**
- ActiveLook 검증된 패턴 완전 복사
- 5개 소스 파일 재사용: DataFieldView, ActivityInfo, Properties, Strings, Settings
- **오직 BLE 레이어만 교체** (2개 모듈)

**Principle 2: Seamless Integration**
- Garmin Run/Bike 앱 내에서 자연스럽게 동작
- 사용자는 "데이터 필드" 하나 추가하는 것으로 인식
- 기존 워크플로우 변경 없음

**Principle 3: Advanced Metrics**
- 기본 4개: 속도, 거리, 심박수, 케이던스
- **파워 3개**: 3-Second Power, Normalized Power, Instantaneous Power
- ActiveLook 통계 계산 로직 재사용 (30-sample buffer, 4차 평균)

**Principle 4: Auto-Pairing**
- 첫 발견 iLens 자동 저장 (`ilens_name` property)
- 이후 연결은 저장된 기기만
- Garmin Connect Mobile에서 기기 변경 가능

### 2.2 설계 원칙

**Proven Over New**
- ActiveLook 검증된 코드 100% 재사용
- 새로운 로직 최소화 (BLE 프로토콜만)
- 3년간 실전 검증된 안정성

**Efficient Over Feature-Rich**
- compute() 호출 20Hz → BLE 전송 1Hz (Throttling)
- Debug 로그는 release 빌드에서 제거 (`(:debug)` / `(:release)`)
- 메모리: 고정 크기 배열 (30-sample power buffer)

**Compatible Over Custom**
- iLens BLE 프로토콜 v1.0.10 준수
- ActiveLook BLE 구조 재사용 (Singleton, State Machine)
- Auto-Pairing 패턴 재사용 (properties.xml)

---

## 3. 핵심 기능

### 3.1 기능 우선순위

| Priority | 기능 | 설명 | Phase |
|----------|------|------|-------|
| **A (Must Have)** | iLens BLE 연결 | BLE Central로 iLens 자동 스캔 및 연결 | 1 |
| **A (Must Have)** | Auto-Pairing | 첫 발견 iLens 자동 저장, 이후 저장된 기기만 연결 | 1 |
| **A (Must Have)** | 실시간 데이터 전송 | 1Hz로 iLens에 **7개 메트릭** 전송 | 1 |
| **A (Must Have)** | 파워 계산 | 3-Second Power, Normalized Power (ActiveLook 로직) | 1 |
| **A (Must Have)** | Activity.Info 데이터 추출 | 속도, 거리, 심박수, 케이던스, **파워** | 1 |
| **B (Should Have)** | 연결 상태 UI | iLens 연결 상태 표시 | 2 |
| **C (Nice to Have)** | 다국어 지원 | 한국어, 영어 | 2 |

**v3.0 추가 기능** (vs v2.0):
- ✅ 파워 계산 (3-Second Power, Normalized Power)
- ✅ Auto-Pairing (properties.xml)
- ✅ 7개 메트릭 전송 (vs 4개)

**제외된 기능** (Activity App과 차이):
- ❌ GPS 직접 수집 (Garmin OS 처리)
- ❌ Activity Recording 구현 (호스트 앱 처리)
- ❌ FIT 파일 생성 (호스트 앱 처리)

---

## 4. 기능 명세

### 4.1 DataField Lifecycle (Priority A)

**기능 설명**:
Garmin Run/Bike 앱이 DataField 라이프사이클 메서드를 호출하면, RunVision-IQ가 iLens 연결 및 데이터 전송을 처리합니다.

**Lifecycle 메서드** (ActiveLook 패턴 재사용):

```monkey-c
class RunVisionIQView extends WatchUi.DataField {
    function initialize() {
        DataField.initialize();
        // 1. Properties에서 ilensName 읽기
        // 2. ILens singleton 초기화
        // 3. BLE Profile 등록 (setUp())
        // 4. Activity Info 객체 초기화
    }

    function compute(info) {
        // 1. 50ms마다 Garmin OS가 자동 호출 (20Hz)
        // 2. Activity.Info에서 메트릭 추출
        // 3. 파워 계산 (accumulate) - ActiveLook 로직
        // 4. Throttling: 1Hz로 제한 (1000ms)
        // 5. iLens에 BLE 전송 (7개 메트릭)
        // 6. Auto-pairing 관리
    }

    function onUpdate(dc) {
        // 1. DataField UI 업데이트
        // 2. iLens 연결 상태 표시 (선택)
    }

    // Timer Events (ActiveLook 패턴)
    function onTimerStart() { /* Record Status 0x01 = 0 */ }
    function onTimerPause() { /* Record Status 0x01 = 1 */ }
    function onTimerStop()  { /* Record Status 0x01 = 2 */ }
}
```

**요구사항**:
- `compute(info)`: Garmin OS가 ~50ms마다 자동 호출
- Throttling: 1000ms (1Hz)로 전송 제한
- `Activity.Info`: 이미 계산된 메트릭 수신 + 파워 계산

### 4.2 Auto-Pairing (Priority A, v3.0 추가)

**기능 설명**:
ActiveLook과 동일한 Auto-Pairing 전략으로 여러 iLens 중 자동으로 선택합니다.

**요구사항**:
- Properties: `ilens_name` (String, 기본값: 빈 문자열)
- 첫 발견 시: 자동 저장
- 이후 연결: 저장된 이름만 연결
- 기기 변경: Garmin Connect Mobile에서 `ilens_name` 수정

**Auto-Pairing 로직** (ActiveLook `onScanResult()` 패턴):

```monkey-c
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
```

**Properties 설정** (`properties.xml`):

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

**기기 변경 방법**:
1. Garmin Connect Mobile → RunVision-IQ → Settings
2. `ilens_name` 필드를 다른 iLens 이름으로 수정
3. 또는 빈 문자열로 설정 → 다음 스캔 시 자동 저장

**장점**:
- ✅ UI 불필요 (Garmin 워치에 선택 화면 없음)
- ✅ 첫 연결 자동화 (사용자 개입 없음)
- ✅ 검증된 패턴 (ActiveLook 3년 운영)

### 4.3 실시간 데이터 전송 (Priority A, v3.0 확장)

**기능 설명**:
1Hz로 iLens에 **7개 메트릭**을 BLE로 전송합니다 (v2.0: 4개 → v3.0: 7개).

**요구사항**:
- 전송 주기: 1Hz (1000ms)
- BLE Write: Characteristic `c259c1bd-18d3-c348-b88d-5447aea1b615`
- 페이로드: iLens 프로토콜 v1.0.10 준수

**전송 데이터 및 페이로드**:

| 메트릭 | Metric ID | 데이터 타입 | 단위 | 변환 | v3.0 추가 |
|--------|----------|-----------|------|------|----------|
| 속도 | 0x07 | UINT32 | km/h * 10 | `(info.currentSpeed * 3.6 * 10).toNumber()` | - |
| 거리 | 0x06 | UINT32 | m | `(info.elapsedDistance).toNumber()` | - |
| 심박수 | 0x0B | UINT32 | bpm | `info.currentHeartRate.toNumber()` | - |
| 케이던스 | 0x0E | UINT32 | spm | `info.currentCadence.toNumber()` | - |
| **3-Second Power** | **0x11** | **UINT32** | **W** | `threeSecPower.toNumber()` | ✅ |
| **Normalized Power** | **0x12** | **UINT32** | **W** | `normalizedPower.toNumber()` | ✅ |
| **Instantaneous Power** | **0x13** | **UINT32** | **W** | `info.currentPower.toNumber()` | ✅ |

**페이로드 포맷** (각 메트릭 개별 전송):
```
Byte 0:     Metric ID
Byte 1-4:   UINT32 (Little-Endian)
```

**전송 순서** (compute() 1Hz):
```monkey-c
// 기본 4개
sendMetric(0x07, speed);     // Velocity
sendMetric(0x06, distance);  // Distance
sendMetric(0x0B, heartRate); // Heart Rate
sendMetric(0x0E, cadence);   // Cadence

// 파워 3개 (v3.0 추가)
sendMetric(0x11, threeSecPower);    // 3-Second Power
sendMetric(0x12, normalizedPower);  // Normalized Power
sendMetric(0x13, power);            // Instantaneous Power
```

**구현 코드** (ActiveLook 패턴):
```monkey-c
function sendMetric(metricId, value) {
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
}
```

### 4.4 파워 계산 (Priority A, v3.0 추가)

**기능 설명**:
ActiveLook의 검증된 파워 계산 로직을 재사용하여 3-Second Power와 Normalized Power를 계산합니다.

**요구사항**:
- 30-sample buffer (Rolling window)
- 3-Second Power: 최근 6 샘플 평균
- Normalized Power: `(avg(power^4))^(1/4)` - 4차 평균의 4차 근

**파워 계산 로직** (ActiveLook `ActiveLookActivityInfo.mc` 재사용):

```monkey-c
// Power buffer (30 samples)
private var __pSamples = new [30];
private var __pAccu = 0.0;      // Sum of (30-sample-avg)^4
private var __pAccuNb = 0;      // Number of accumulated samples

// accumulate() - compute()에서 매번 호출
function accumulate(info) {
    if (info == null || info.currentPower == null) { return; }

    var power = info.currentPower;
    __pSamples.add(power);

    if (__pSamples.size() >= 30) {
        // Keep last 30 samples
        __pSamples = __pSamples.slice(-30, null);

        // Calculate 30-sample average
        var tmp = 0;
        for(var i = 0; i < 30; i++) {
            tmp += __pSamples[i];
        }
        var avg30 = tmp / 30.0;

        // Accumulate for normalized power: (avg30)^4
        __pAccu += Math.pow(avg30, 4);
        __pAccuNb++;
    }
}

// compute() - 1Hz 전송 시 호출
function getThreeSecPower() {
    // Last 6 samples (3 seconds at 2 Hz)
    if (__pSamples.size() >= 6) {
        var tmp = __pSamples.slice(-6, null);
        return (tmp[0] + tmp[1] + tmp[2] + tmp[3] + tmp[4] + tmp[5]) / 6.0;
    }
    return null;
}

function getNormalizedPower() {
    // (avg(power^4))^(1/4)
    if (__pAccuNb > 0) {
        return Math.pow(__pAccu / __pAccuNb, 0.25);
    }
    return null;
}
```

**파워 메트릭 의미**:
- **3-Second Power**: 최근 3초 평균 파워 (단기 변동 평활화)
- **Normalized Power**: 생리학적 부하 반영 (4차 평균)
- **Instantaneous Power**: 현재 순간 파워 (Activity.Info 직접)

**ActiveLook과 차이**:
- ActiveLook: 파워 계산만, 글래스는 파워 미표시
- RunVision-IQ: 파워 계산 + **iLens에 전송 (0x11, 0x12, 0x13)**

### 4.5 Activity.Info 데이터 추출 (Priority A, v3.0 확장)

**기능 설명**:
Garmin OS가 제공하는 `Activity.Info` 객체에서 러닝/사이클링 메트릭을 추출합니다.

**요구사항**:
- Null Safety: 모든 필드 null 체크
- 기본값: null인 경우 0 반환 (파워는 null 허용)
- 단위 변환: m/s → km/h (속도)

**추출 메서드** (ActiveLook 패턴):

```monkey-c
function extractSpeed(info) {
    if (info.currentSpeed != null && info.currentSpeed > 0) {
        return (info.currentSpeed * 3.6).toNumber();  // m/s → km/h
    }
    return 0;
}

function extractDistance(info) {
    if (info.elapsedDistance != null) {
        return info.elapsedDistance.toNumber();  // meters
    }
    return 0;
}

function extractHeartRate(info) {
    if (info.currentHeartRate != null && info.currentHeartRate > 0) {
        return info.currentHeartRate.toNumber();  // bpm
    }
    return 0;
}

function extractCadence(info) {
    if (info.currentCadence != null && info.currentCadence > 0) {
        return info.currentCadence.toNumber();  // spm
    }
    return 0;
}

// v3.0 추가
function extractPower(info) {
    if (info.currentPower != null && info.currentPower > 0) {
        return info.currentPower.toNumber();  // Watts
    }
    return null;  // Power는 null 허용
}
```

**Activity.Info 주요 필드**:
- `currentSpeed`: Float, m/s
- `elapsedDistance`: Long, meters
- `currentHeartRate`: Integer, bpm
- `currentCadence`: Integer, spm
- **`currentPower`**: Integer, Watts (v3.0 추가)
- `timerState`: Integer (TIMER_STATE_ON, TIMER_STATE_PAUSED, TIMER_STATE_STOPPED)

### 4.6 Timer Event 처리 (Priority B)

**기능 설명**:
Garmin Run/Bike 앱의 타이머 이벤트에 반응하여 iLens에 Record Status를 전송합니다.

**Timer Events** (ActiveLook 패턴):
- `onTimerStart()`: 운동 시작 → Record Status 0x01 = 0 (Start)
- `onTimerPause()`: 일시정지 → Record Status 0x01 = 1 (Pause)
- `onTimerResume()`: 재개 → Record Status 0x01 = 0 (Resume)
- `onTimerStop()`: 종료 → Record Status 0x01 = 2 (Stop)

**Record Status 전송**:
```monkey-c
function onTimerStart() {
    DataField.onTimerStart();
    sendRecordStatus(0);  // Start
}

function onTimerPause() {
    DataField.onTimerPause();
    sendRecordStatus(1);  // Pause
}

function onTimerStop() {
    DataField.onTimerStop();
    sendRecordStatus(2);  // Stop
}

function sendRecordStatus(status) {
    var ilens = ILens.getInstance();
    if (ilens.isConnected()) {
        ilens.sendMetric(0x01, status);  // Metric ID 0x01
    }
}
```

---

## 5. 사용자 시나리오

### 5.1 Happy Path: DataField로 러닝 (Auto-Pairing)

**사전 조건**:
- Garmin Run 앱에 RunVision-IQ DataField 추가됨
- Settings: `ilens_enabled = true`, `ilens_name = ""` (첫 사용)
- iLens 충전 및 켜짐

**시나리오**:
```
1. 사용자: Garmin Run 앱 시작
   → RunVision-IQ: initialize() 호출
   → ILens: setUp() → BLE Profile 등록
   → ILens: requestScanning() → iLens 스캔 시작
   → Properties: ilensName = "" (빈 문자열)

2. 5-10초 후: iLens 발견 (예: "iLens-sw-A1B2C3")
   → onScanResult() 호출
   → ilensName == "" → 자동 저장
   → Properties.setValue("ilens_name", "iLens-sw-A1B2C3")
   → $.ilensName = "iLens-sw-A1B2C3"
   → pairDevice() → 자동 연결
   → 연결 성공

3. 다음 사용 시:
   → Properties: ilensName = "iLens-sw-A1B2C3" (저장됨)
   → onScanResult(): "iLens-sw-A1B2C3"만 연결
   → 다른 iLens 무시

4. 사용자: START 버튼 누름
   → onTimerStart() → Record Status 0x01 = 0

5. 러닝 중 (30분):
   → compute(info) 호출 (50ms마다, 20Hz)
   → accumulate(info) → 파워 계산 (ActiveLook 로직)
   → Throttling (1Hz만 전송)
   → 7개 메트릭 전송: 속도, 거리, 심박수, 케이던스, 3-sec power, norm power, power
   → iLens AR: 실시간 메트릭 표시

6. 사용자: STOP 버튼 누름
   → onTimerStop() → Record Status 0x01 = 2
   → Garmin Connect에 자동 동기화
```

**기대 결과**:
- ✅ 첫 사용: iLens 자동 저장, 이후 자동 연결
- ✅ 7개 메트릭 실시간 표시 (파워 포함)
- ✅ Garmin Connect에 러닝 기록 저장

### 5.2 Edge Case: 여러 iLens 중 선택

**시나리오**:
```
1. 환경: 주변에 2개 iLens 존재
   - "iLens-sw-A1B2C3" (내 글래스)
   - "iLens-sw-D4E5F6" (다른 사람 글래스)

2. 첫 사용 (ilensName = ""):
   → 스캔 시작
   → "iLens-sw-A1B2C3" 먼저 발견 (가까움)
   → 자동 저장 및 연결
   → ilensName = "iLens-sw-A1B2C3"

3. 이후 사용:
   → "iLens-sw-A1B2C3"만 연결
   → "iLens-sw-D4E5F6" 발견해도 무시

4. 기기 변경 (Garmin Connect Mobile):
   → Settings → ilens_name = "iLens-sw-D4E5F6"
   → 다음 러닝: "iLens-sw-D4E5F6"만 연결
```

**기대 결과**:
- ✅ UI 없이 자동 선택 (첫 발견 기기)
- ✅ 기기 변경 가능 (Garmin Connect Mobile)

### 5.3 Edge Case: iLens 연결 실패

(v2.0과 동일, 생략)

### 5.4 Edge Case: 러닝 중 iLens 끊김

(v2.0과 동일, 생략)

---

## 6. 비기능 요구사항

### 6.1 성능 요구사항

| 항목 | 요구사항 | 측정 방법 |
|------|---------|----------|
| **compute() 주기** | ~50ms (20Hz, Garmin OS 제어) | System.getTimer() |
| **BLE 전송 주기** | 1000ms ±100ms (1Hz) | Throttling 로직 |
| **파워 계산** | <5ms (30-sample avg) | ActiveLook 검증됨 |
| **iLens 연결 시간** | <10초 (95%) | 스캔 시작부터 연결까지 |
| **메모리 사용** | <2.5MB | Power buffer 추가 (+0.5MB) |

### 6.2 배터리 요구사항

| 시나리오 | 목표 배터리 소비 | 근거 |
|---------|----------------|------|
| **1시간 러닝** | +3.0-4.0% (iLens BLE + 파워 계산) | v2.0: 2.5-3.5% → 파워 계산 추가 |
| **하프 마라톤** | +6% | 평균 2시간 |

**v2.0 대비 증가**: 파워 계산 로직 추가 (+0.5-1.0%)

### 6.3 안정성 요구사항

| 항목 | 요구사항 |
|------|---------|
| **앱 크래시율** | <0.1% (ActiveLook 3년 검증) |
| **BLE 재연결 성공률** | >90% (Auto-pairing) |
| **Null Safety** | 100% (모든 Activity.Info 필드) |
| **메모리 누수** | 0 (고정 크기 배열, 싱글톤) |

### 6.4 호환성 요구사항

| 항목 | 요구사항 |
|------|---------|
| **Connect IQ SDK** | 4.0+ |
| **Garmin 기기** | Forerunner 265, 955, 965, Fenix 7 (BLE Central 지원) |
| **iLens 펌웨어** | v2.0+ (BLE 프로토콜 v1.0.10) |
| **파워 센서** | Activity.Info.currentPower 필요 (Foot Pod, Stryd 등) |

---

## 7. 사용자 인터페이스

### 7.1 DataField 화면 (선택 사항)

**Option 1: 최소 구현** (추천, ActiveLook 패턴)
```
onUpdate(dc) {
    // 호스트 앱이 메트릭 표시
}
```

**Option 2: iLens 연결 상태 표시** (Phase 2)
```
┌───────────────────┐
│  iLens: ✓ 연결됨  │
│  (iLens-sw-A1B2)  │  ← Auto-saved name 표시
└───────────────────┘
```

### 7.2 Settings 화면

**Settings (properties.xml)**:
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

**Settings UI** (Garmin Connect Mobile):
```
┌─────────────────────────┐
│  RunVision-IQ Settings  │
├─────────────────────────┤
│                         │
│  [✓] iLens 활성화       │
│                         │
│  iLens 기기 이름:       │
│  [iLens-sw-A1B2C3   ]   │  ← 저장된 이름, 변경 가능
│                         │
│  * 빈 문자열로 설정 시  │
│    다음 스캔에서 첫     │
│    발견 기기 자동 저장  │
│                         │
└─────────────────────────┘
  [취소]          [저장]
```

---

## 8. 데이터 모델

### 8.1 Activity.Info 구조 (v3.0 확장)

```monkey-c
Activity.Info {
    currentSpeed: Float or null,        // m/s
    elapsedDistance: Long or null,      // meters
    currentHeartRate: Integer or null,  // bpm
    currentCadence: Integer or null,    // spm
    currentPower: Integer or null,      // Watts (v3.0)
    timerState: Integer,                // TIMER_STATE_*
    elapsedTime: Long,                  // milliseconds
}
```

### 8.2 iLens BLE 페이로드 (v3.0 확장)

**메트릭 정의**:
| Metric ID | 이름 | 데이터 타입 | 단위 | v3.0 추가 |
|-----------|------|-----------|------|----------|
| 0x01 | Record Status | UINT32 | - | - |
| 0x06 | Distance | UINT32 | meters | - |
| 0x07 | Velocity | UINT32 | km/h * 10 | - |
| 0x0B | Heart Rate | UINT32 | bpm | - |
| 0x0E | Cadence | UINT32 | spm | - |
| **0x11** | **3-Second Power** | **UINT32** | **W** | ✅ |
| **0x12** | **Normalized Power** | **UINT32** | **W** | ✅ |
| **0x13** | **Instantaneous Power** | **UINT32** | **W** | ✅ |

**전송 순서** (compute() 1Hz):
```monkey-c
// 기본 4개
sendMetric(0x07, speed);
sendMetric(0x06, distance);
sendMetric(0x0B, heartRate);
sendMetric(0x0E, cadence);

// 파워 3개 (v3.0)
if (threeSecPower != null) { sendMetric(0x11, threeSecPower); }
if (normalizedPower != null) { sendMetric(0x12, normalizedPower); }
if (power != null) { sendMetric(0x13, power); }
```

### 8.3 내부 상태 변수 (v3.0 확장)

**RunVisionIQView 클래스**:
```monkey-c
private var _ilensEnabled = false;         // Settings
private var _ilensName = "";               // Auto-saved device name
private var _lastSendTime = 0;             // 마지막 전송 시간 (ms)
private var _sendIntervalMs = 1000;        // 1Hz

// Power calculation (ActiveLook)
private var __pSamples = new [30];         // 30-sample buffer
private var __pAccu = 0.0;                 // Sum of (avg30)^4
private var __pAccuNb = 0;                 // Accumulated count
```

**ILens 클래스**:
```monkey-c
private var _profileRegistered = false;
private var _device = null;                // BLE Device
private var _exerciseCharacteristic = null;// Exercise Char
```

---

## 9. 기술 제약사항

### 9.1 DataField 제약사항

(v2.0과 동일, 생략)

### 9.2 BLE 제약사항

(v2.0과 동일, 생략)

### 9.3 파워 계산 제약사항 (v3.0 추가)

| 제약사항 | 설명 | 대응 방안 |
|---------|------|----------|
| **파워 센서 필요** | Activity.Info.currentPower는 외부 센서 필요 | Foot Pod, Stryd, 파워 미터 등 |
| **30-sample buffer** | 메모리 30*4 = 120 bytes | 고정 크기 배열 |
| **Normalized Power 정확도** | 30-sample 누적 필요 | 첫 30초는 null |

---

## 10. 보안 및 프라이버시

(v2.0과 동일, 생략)

---

## 11. 테스트 요구사항

### 11.1 시뮬레이터 테스트

**Connect IQ Simulator**:
- DataField 라이프사이클 테스트
- Activity.Info 시뮬레이션 (파워 포함)
- 파워 계산 로직 검증 (30-sample buffer)
- Auto-Pairing 로직 검증 (ilens_name 빈 문자열)

### 11.2 실제 기기 테스트

**필수 테스트 시나리오**:
1. ✅ Auto-Pairing: 첫 iLens 자동 저장 (10회)
2. ✅ 저장된 기기만 연결 (다른 iLens 무시)
3. ✅ 7개 메트릭 전송 (30분 러닝)
4. ✅ 파워 계산 정확도 (Stryd와 비교)
5. ✅ 30-sample buffer 메모리 관리
6. ✅ iLens 재연결 (끊김 후 자동)
7. ✅ Garmin Connect 저장 확인
8. ✅ 기기 변경 (ilens_name 수정)

### 11.3 성능 테스트

**측정 항목**:
- 파워 계산 시간 (<5ms)
- 메모리 사용량 (파워 buffer 포함)
- 배터리 소모율 (1시간 러닝, 파워 계산 포함)
- BLE Write 지연 (7개 메트릭)

---

## 12. 출시 계획

### 12.1 Phase 1: ActiveLook 복사 + BLE 교체 (3주)

**Week 1: ActiveLook 소스 복사 및 프로젝트 설정**
- ✅ ActiveLook 5개 소스 파일 복사
  - `ActiveLookDataFieldView.mc` → `RunVisionIQView.mc`
  - `ActiveLookActivityInfo.mc` → `RunVisionIQActivityInfo.mc`
  - `properties.xml` (ilens_name, ilens_enabled)
  - `strings.xml` (다국어)
  - `settings.xml` (Settings UI)
- ✅ Connect IQ 프로젝트 초기화
- ✅ Forerunner 265 시뮬레이터 테스트

**Week 2: BLE 레이어 교체**
- ✅ `ActiveLook.mc` → `ILens.mc` 교체
  - onScanResult() 수정 (Auto-Pairing 로직 유지)
  - Service UUID 변경: ActiveLook → iLens
  - Characteristic UUID 변경
- ✅ `ActiveLookSDK_next.mc` → `ILensProtocol.mc` 교체
  - commandBuffer() 제거 (ActiveLook 텍스트 프로토콜)
  - sendMetric() 추가 (iLens 바이너리 프로토콜)
  - 7개 메트릭 전송 로직 구현
- ✅ 파워 계산 로직 검증 (ActivityInfo.mc 유지)

**Week 3: 통합 테스트 및 디버깅**
- ✅ Forerunner 265 실기 테스트
- ✅ iLens Series 1/2 연동 테스트
- ✅ Auto-Pairing 검증 (10회 반복)
- ✅ 7개 메트릭 전송 확인
- ✅ 30분 러닝 안정성 테스트

**출시**:
- Connect IQ Store Private Beta

### 12.2 Phase 2: UI 및 다국어 (1주)

**목표**: 사용자 경험 개선

**기능**:
- ✅ DataField UI (iLens 연결 상태 + 저장된 이름 표시)
- ✅ 다국어 지원 (한국어, 영어) - ActiveLook strings.xml 재사용
- ✅ Settings 확장 (Auto-Pairing 설명 추가)
- ✅ Fenix 7 Series 지원

**테스트**:
- 베타 테스터 10명
- 장거리 러닝 테스트 (10km+)

**출시**:
- Connect IQ Store Public Beta

### 12.3 Phase 3: 고급 기능 (선택, 1-2주)

**목표**: 추가 메트릭 및 사용자 편의

**기능**:
- ✅ 추가 메트릭 전송 (Altitude, Average Pace)
- ✅ 랩 이벤트 전송 (onTimerLap)
- ✅ 수동 재연결 버튼 (UI)
- ✅ 전송 간격 설정 (500ms, 1000ms, 2000ms)

**출시**:
- Connect IQ Store 정식 출시

---

## 13. 성공 지표

### 13.1 기술 지표

| 지표 | 목표 | 측정 방법 |
|------|------|----------|
| **앱 크래시율** | <0.1% (ActiveLook 검증) | Connect IQ 애널리틱스 |
| **iLens 연결 성공률** | >95% (Auto-Pairing) | 연결 로그 분석 |
| **파워 계산 정확도** | ±2% (vs Stryd) | 실기 비교 테스트 |
| **BLE 전송 지연** | <100ms (7개 메트릭) | requestWrite() 타임스탬프 |
| **배터리 소모** | <4.0% (1시간) | 실기 측정 |

### 13.2 사용자 지표

| 지표 | 목표 | 측정 방법 |
|------|------|----------|
| **일간 활성 사용자** | 50+ (3개월) | Connect IQ 애널리틱스 |
| **평균 세션 길이** | 30분+ | Activity 기록 분석 |
| **사용자 만족도** | 4.5/5.0+ | Connect IQ Store 리뷰 |

---

## 14. 위험 관리

### 14.1 기술 위험

| 위험 | 확률 | 영향 | 대응 방안 |
|------|------|------|----------|
| **BLE 프로토콜 호환 이슈** | 저 | 고 | ActiveLook 검증된 BLE 패턴 재사용 |
| **파워 센서 필수** | 중 | 중 | 파워 센서 없으면 기본 4개 메트릭만 |
| **메모리 부족** | 저 | 중 | 고정 크기 배열, 30-sample buffer 검증됨 |
| **Auto-Pairing 혼란** | 중 | 중 | Settings UI에 명확한 설명 추가 |

### 14.2 비즈니스 위험

| 위험 | 확률 | 영향 | 대응 방안 |
|------|------|------|----------|
| **Garmin 정책 변경** | 저 | 고 | Connect IQ 커뮤니티 모니터링 |
| **iLens 프로토콜 변경** | 저 | 고 | iLens 팀과 협력 |

---

## 15. v2.0 vs v3.0 비교

| 항목 | v2.0 (간소화) | v3.0 (ActiveLook 100%) |
|------|---------------|------------------------|
| **코드 재사용** | 90% 재사용 | **100% 복사** |
| **메트릭 개수** | 4개 | **7개** (파워 +3) |
| **통계 계산** | ❌ 제거 | ✅ **유지** (ActiveLook 로직) |
| **Auto-Pairing** | ❌ 미정의 | ✅ **properties.xml** |
| **개발 기간** | 2-3주 | **4주** (파워 계산 +1주) |
| **배터리 소모** | 2.5-3.5% (1시간) | **3.0-4.0%** (파워 계산 추가) |
| **복잡도** | ⭐⭐ | **⭐⭐** (동일, BLE만 교체) |
| **안정성** | 신규 구현 | **검증됨** (ActiveLook 3년) |

**v3.0 장점**:
- ✅ 검증된 안정성 (ActiveLook 3년 운영)
- ✅ 고급 메트릭 (파워)
- ✅ Auto-Pairing (사용자 편의)
- ✅ 100% 코드 재사용 (유지보수 용이)

**v3.0 단점**:
- 개발 기간 1주 증가 (+33%)
- 배터리 소모 약간 증가 (+0.5-1.0%)

---

## 16. ActiveLook과 RunVision-IQ 비교

| 항목 | ActiveLook | RunVision-IQ |
|------|-----------|--------------|
| **플랫폼** | ActiveLook AR 글래스 | **iLens AR 글래스** |
| **BLE 프로토콜** | ActiveLook 텍스트 프로토콜 | **iLens 바이너리 프로토콜** |
| **메트릭 전송** | 4개 (파워 계산만, 미전송) | **7개** (파워 계산 + 전송) |
| **파워 메트릭** | ❌ 글래스 미지원 | ✅ **iLens 지원 (0x11~0x13)** |
| **BLE 모듈** | ActiveLook.mc, ActiveLookSDK_next.mc | **ILens.mc, ILensProtocol.mc** |
| **나머지 코드** | DataFieldView, ActivityInfo, Properties, Strings, Settings | **100% 동일** (복사) |
| **Auto-Pairing** | properties.xml (glasses_name) | **properties.xml (ilens_name)** |

**교체 범위**:
- ✅ BLE 레이어만 교체 (2개 모듈)
- ✅ 나머지 5개 파일 100% 재사용
- ✅ 파워 계산 로직 100% 재사용
- ✅ Auto-Pairing 로직 100% 재사용

---

## 17. 참조 문서

**내부 문서**:
- `ActiveLook-Source-Analysis-Complete.md` - ActiveLook 완전 분석 (완료)
- `ActiveLook-Code-Analysis.md` - ActiveLook 코드 분석 (완료)
- `iLens-BLE-Protocol-Analysis.md` - iLens 프로토콜 분석 (완료)
- `RunVision-IQ-Architecture-Design.md` - 아키텍처 설계 (v2.0 기준, 재작성 예정)
- `System-Architecture.md` (재작성 예정, v3.0 기준)
- `BLE-Protocol-Mapping.md` (신규 작성 예정, ActiveLook → iLens)
- `Module-Design.md` (재작성 예정, ILens 모듈 중심)
- `Implementation-Guide.md` (신규 작성 예정, 단계별 교체 가이드)
- `Test-Specification.md` (재작성 예정, v3.0 기준)

**공통 문서**:
- `iLens BLE V1.0.10.pdf` - iLens BLE 프로토콜
- `ilens user manual.pdf` - iLens 사용자 매뉴얼
- `garmin-ilens-technical-analysis.md` - 기술 분석

**ActiveLook 소스**:
- `activeLook/source/ActiveLookDataFieldView.mc` (579 lines)
- `activeLook/source/ActiveLookActivityInfo.mc` (865 lines, 파워 계산)
- `activeLook/source/ActiveLookSDK_next.mc` (1092 lines, BLE)
- `activeLook/resources/settings/properties.xml` (Auto-Pairing)
- `activeLook/resources/strings/strings.xml` (다국어)

**외부 리소스**:
- [Connect IQ 공식 문서](https://developer.garmin.com/connect-iq/overview/)
- [DataField API Reference](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html)
- [Activity.Info Reference](https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html)
- [BLE API Reference](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
- [ActiveLook GitHub](https://github.com/ActiveLook/Garmin-Datafield-sample-code)

---

**문서 이력**:
- v1.0 (2025-11-15): 초기 작성 (Activity App 기준)
- v2.0 (2025-11-15): 전면 재작성 (DataField 기준, 간소화)
- **v3.0 (2025-11-15): 전략 변경 (ActiveLook 100% 복사, 7개 메트릭, Auto-Pairing)**

**승인 상태**: ✅ Ready for Implementation (v3.0 최종)

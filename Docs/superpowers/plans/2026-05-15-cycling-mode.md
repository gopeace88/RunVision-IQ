# 사이클 모드 구현 계획 (Phase 1: 워치)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RunVision-IQ DataField에 가민 워치 사이클 액티비티 자동 감지 및 메트릭 재매핑을 Strategy 패턴으로 구현하여, 러닝 모드에 사이드이펙트가 0이 되도록 한다.

**Architecture:** `MetricValues` 데이터 컨테이너 + `RunningStrategy` / `CyclingStrategy` 두 strategy 클래스. `RunVisionIQView.compute()` 첫 호출 시 `Activity.getProfileInfo().sport` 로 strategy를 선택하고, 패킷 생성 블록을 strategy 호출로 위임. 기존 BLE/스캔/큐 로직과 패킷 인코딩(`ILensProtocol`)은 손대지 않는다.

**Tech Stack:** Monkey C, Connect IQ SDK 8.3.0, Garmin Test Framework (`(:test)` 어노테이션)

**Spec:** `Docs/superpowers/specs/2026-05-15-cycling-mode-design.md`

---

## File Structure

각 파일은 하나의 명확한 책임을 가진다.

**생성 파일:**
- `source/MetricStrategy.mc` — `MetricValues` 데이터 컨테이너 + `detectStrategy()` 함수. Strategy 인터페이스 진입점.
- `source/RunningStrategy.mc` — `RunningStrategy` 클래스. 기존 러닝 모드 패킷 생성 로직을 캡슐화.
- `source/CyclingStrategy.mc` — `CyclingStrategy` 클래스. 사이클 모드 패킷 생성 + HR 30초 락 상태 머신.

**수정 파일:**
- `source/RunVisionIQView.mc` — strategy 필드 추가, `compute()` 내 패킷 생성 블록 (line 607-612) 을 strategy 호출로 대체.
- `source/Tests.mc` — strategy 단위 테스트 추가.
- `manifest.xml` — 버전 1.1.10 → 1.2.0.
- `monkey.jungle` — 새 `.mc` 파일들이 빌드에 포함되는지 확인 (필요 시).

**미변경 (절대 손대지 말 것):**
- `source/ILensProtocol.mc`
- `source/RunVisionIQApp.mc`
- `source/DFLogger.mc`

---

## Conventions

- 모든 새 클래스/함수는 Monkey C `using` 임포트로 `ILensProtocol`, `Toybox.Activity`, `Toybox.Lang` 등을 명시.
- 테스트는 `Tests.mc` 하단에 추가, `(:test)` 어노테이션 + `Boolean` 반환.
- 커밋 메시지는 한국어 + Conventional Commits 형식 (기존 패턴 따라).
- Float → Int 변환 시 `encodeUINT32` 가 내부에서 반올림하므로, strategy 호출부에서는 Float를 그대로 넘겨도 됨. 단, `altitudeM` 같이 의미상 정수인 값은 `.toNumber()` 로 명시적으로 변환.

---

## Task 1: MetricValues 데이터 컨테이너

`MetricValues` 는 매 `compute()` 호출마다 새로 채워지는 단순 데이터 컨테이너. Strategy 간 공유 가변 상태가 아니라 **계산된 값의 전달자**.

**Files:**
- Create: `source/MetricStrategy.mc`
- Test: `source/Tests.mc` (수정)

- [ ] **Step 1.1: 실패하는 테스트 작성**

`source/Tests.mc` 끝에 다음 추가:

```monkeyc
(:test)
function testMetricValues_DefaultsAreZero(logger as Logger) as Boolean {
    var values = new MetricValues();
    logger.debug("MetricValues defaults");
    return values.elapsedSeconds == 0
        && values.distance == 0
        && values.paceSeconds == 0
        && values.speedKmh == 0
        && values.hr == 0
        && values.cadence == 0
        && values.altitudeM == 0
        && values.totalAscent == 0;
}
```

- [ ] **Step 1.2: 테스트 실패 확인**

Run: VS Code에서 Run Test (또는 `monkeyc` 빌드).
Expected: 빌드 실패 — `MetricValues` 미정의.

- [ ] **Step 1.3: MetricValues 클래스 작성**

`source/MetricStrategy.mc` 생성:

```monkeyc
using Toybox.Lang;
using Toybox.Activity;

//! Per-compute metric values container.
//! 매 compute() 호출마다 새로 채워지며 strategy 에 전달된다.
//! 누적 상태(예: HR 30초 락) 는 strategy 가 자체 보유한다.
class MetricValues {
    public var elapsedSeconds as Lang.Number = 0;
    public var distance as Lang.Number = 0;        // meters
    public var paceSeconds as Lang.Number = 0;     // running only (sec/km)
    public var speedKmh as Lang.Number = 0;        // cycling only (km/h)
    public var hr as Lang.Number = 0;              // 0 if unavailable
    public var cadence as Lang.Number = 0;         // running only (spm)
    public var altitudeM as Lang.Number = 0;       // cycling only (meters)
    public var totalAscent as Lang.Number = 0;     // cycling only (meters)

    function initialize() {
    }
}
```

- [ ] **Step 1.4: 테스트 통과 확인**

Run: Run Test → `testMetricValues_DefaultsAreZero` PASS.

- [ ] **Step 1.5: 커밋**

```bash
cd /home/jhkim/00.Projects/00.RunVision/runvision-iq
git add source/MetricStrategy.mc source/Tests.mc
git commit -m "feat: MetricValues 데이터 컨테이너 추가"
```

---

## Task 2: RunningStrategy (기존 동작 보존)

`RunningStrategy.buildPackets()` 는 기존 `RunVisionIQView.compute()` 의 line 607-612 와 **바이트 단위로 동일한 결과**를 내야 한다. 회귀 방지 테스트가 최우선.

**Files:**
- Create: `source/RunningStrategy.mc`
- Test: `source/Tests.mc` (수정)

- [ ] **Step 2.1: 회귀 방지 테스트 5개 작성**

`source/Tests.mc` 끝에 추가:

```monkeyc
// === RunningStrategy regression tests ===
// 이 테스트들은 기존 러닝 모드 패킷이 한 비트도 안 바뀌었음을 보증한다.

(:test)
function testRunningStrategy_SportTimePacket(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.elapsedSeconds = 600;  // 10:00
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // Sport Time = 0x03, 600 = 0x258 = LE [0x58, 0x02, 0x00, 0x00]
    var expected = [0x03, 0x58, 0x02, 0x00, 0x00]b;
    return findAndCompare(packets, 0x03, expected, logger);
}

(:test)
function testRunningStrategy_VelocityIsPaceSeconds(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.paceSeconds = 330;  // 5:30/km
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // 0x07, 330 = 0x14A = LE [0x4A, 0x01, 0x00, 0x00]
    var expected = [0x07, 0x4A, 0x01, 0x00, 0x00]b;
    return findAndCompare(packets, 0x07, expected, logger);
}

(:test)
function testRunningStrategy_HeartRateRaw(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.hr = 150;
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // 0x0B, 150 = LE [0x96, 0x00, 0x00, 0x00]
    var expected = [0x0B, 0x96, 0x00, 0x00, 0x00]b;
    return findAndCompare(packets, 0x0B, expected, logger);
}

(:test)
function testRunningStrategy_CadenceIsSpm(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.cadence = 170;
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // 0x0E, 170 = LE [0xAA, 0x00, 0x00, 0x00]
    var expected = [0x0E, 0xAA, 0x00, 0x00, 0x00]b;
    return findAndCompare(packets, 0x0E, expected, logger);
}

(:test)
function testRunningStrategy_DistanceMeters(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.distance = 1234;
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // 0x06, 1234 = 0x4D2 = LE [0xD2, 0x04, 0x00, 0x00]
    var expected = [0x06, 0xD2, 0x04, 0x00, 0x00]b;
    return findAndCompare(packets, 0x06, expected, logger);
}

// Helper: 주어진 ID 의 패킷을 찾아 expected 와 바이트 비교
function findAndCompare(packets as Lang.Array<Lang.ByteArray>,
                       id as Lang.Number,
                       expected as Lang.ByteArray,
                       logger as Logger) as Lang.Boolean {
    for (var i = 0; i < packets.size(); i++) {
        var p = packets[i];
        if (p.size() > 0 && p[0] == id) {
            if (p.size() != expected.size()) {
                logger.debug("packet size mismatch for id=" + id);
                return false;
            }
            for (var j = 0; j < expected.size(); j++) {
                if (p[j] != expected[j]) {
                    logger.debug("byte " + j + " mismatch for id=" + id
                        + " expected=" + expected[j] + " actual=" + p[j]);
                    return false;
                }
            }
            return true;
        }
    }
    logger.debug("packet id=" + id + " not found");
    return false;
}
```

- [ ] **Step 2.2: 테스트 실패 확인**

Run: Run Test.
Expected: 빌드 실패 — `RunningStrategy` 미정의.

- [ ] **Step 2.3: RunningStrategy 구현**

`source/RunningStrategy.mc` 생성:

```monkeyc
using Toybox.Lang;
using ILensProtocol;

//! Running mode metric strategy.
//! 기존 RunVisionIQView.compute() 의 패킷 생성 로직을 그대로 이전.
//! 변경 시 testRunningStrategy_* 테스트가 회귀를 잡아낸다.
class RunningStrategy {

    function initialize() {
    }

    //! 5개 메트릭 패킷을 순서대로 생성 (기존 line 608-612 와 동등)
    //! Sport Time → Velocity(pace) → Heart Rate → Cadence → Distance
    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(values.paceSeconds));
        packets.add(ILensProtocol.createHeartRatePacket(values.hr));
        packets.add(ILensProtocol.createCadencePacket(values.cadence));
        packets.add(ILensProtocol.createDistancePacket(values.distance));
        return packets;
    }
}
```

- [ ] **Step 2.4: 5개 테스트 통과 확인**

Run: Run Test.
Expected: 5개 모두 PASS.

- [ ] **Step 2.5: 커밋**

```bash
git add source/RunningStrategy.mc source/Tests.mc
git commit -m "feat: RunningStrategy 클래스 추가 (기존 동작 보존)"
```

---

## Task 3: CyclingStrategy 기본 패킷 (HR 락 없음)

먼저 단순 버전 — speed/altitude/distance 만 매핑하고 HR 은 그대로 전달. HR 락 로직은 Task 4에서 추가.

**Files:**
- Create: `source/CyclingStrategy.mc`
- Test: `source/Tests.mc` (수정)

- [ ] **Step 3.1: 사이클 기본 패킷 테스트 작성**

`source/Tests.mc` 끝에 추가:

```monkeyc
// === CyclingStrategy basic packet tests ===

(:test)
function testCyclingStrategy_VelocityIsSpeedKmh(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.speedKmh = 25;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 0x07, 25 = 0x19 = LE [0x19, 0x00, 0x00, 0x00]
    var expected = [0x07, 0x19, 0x00, 0x00, 0x00]b;
    return findAndCompare(packets, 0x07, expected, logger);
}

(:test)
function testCyclingStrategy_CadenceIsAltitudeM(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.altitudeM = 1200;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 0x0E, 1200 = 0x4B0 = LE [0xB0, 0x04, 0x00, 0x00]
    var expected = [0x0E, 0xB0, 0x04, 0x00, 0x00]b;
    return findAndCompare(packets, 0x0E, expected, logger);
}

(:test)
function testCyclingStrategy_DistanceMeters(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.distance = 5000;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 0x06, 5000 = 0x1388 = LE [0x88, 0x13, 0x00, 0x00]
    var expected = [0x06, 0x88, 0x13, 0x00, 0x00]b;
    return findAndCompare(packets, 0x06, expected, logger);
}

(:test)
function testCyclingStrategy_SportTimePacket(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.elapsedSeconds = 1800;  // 30:00
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 0x03, 1800 = 0x708 = LE [0x08, 0x07, 0x00, 0x00]
    var expected = [0x03, 0x08, 0x07, 0x00, 0x00]b;
    return findAndCompare(packets, 0x03, expected, logger);
}
```

- [ ] **Step 3.2: 테스트 실패 확인**

Expected: 빌드 실패 — `CyclingStrategy` 미정의.

- [ ] **Step 3.3: CyclingStrategy 기본 구현 (HR 락 없음)**

`source/CyclingStrategy.mc` 생성:

```monkeyc
using Toybox.Lang;
using ILensProtocol;

//! Cycling mode metric strategy.
//! 0x07: paceSeconds → speedKmh
//! 0x0E: cadence → altitudeM
//! 0x0B: hr (Task 4 에서 30초 락 로직 추가)
class CyclingStrategy {

    function initialize() {
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(values.speedKmh));
        packets.add(ILensProtocol.createHeartRatePacket(values.hr));
        packets.add(ILensProtocol.createCadencePacket(values.altitudeM));
        packets.add(ILensProtocol.createDistancePacket(values.distance));
        return packets;
    }
}
```

- [ ] **Step 3.4: 4개 테스트 통과 확인**

Run: Run Test.
Expected: 4개 모두 PASS. Task 2 의 5개 러닝 테스트도 여전히 PASS (회귀 확인).

- [ ] **Step 3.5: 커밋**

```bash
git add source/CyclingStrategy.mc source/Tests.mc
git commit -m "feat: CyclingStrategy 기본 패킷 (HR 락 없음)"
```

---

## Task 4: CyclingStrategy HR 30초 락 상태 머신

세션 내 슬롯 의미를 도중에 바꾸지 않기 위한 30초 락. 단 한 번 결정 후 영구 고정.

**Files:**
- Modify: `source/CyclingStrategy.mc`
- Test: `source/Tests.mc` (수정)

- [ ] **Step 4.1: HR 락 상태 머신 테스트 4개 작성**

`source/Tests.mc` 끝에 추가:

```monkeyc
// === CyclingStrategy HR lock state machine tests ===

(:test)
function testCyclingStrategy_HrLockBeforeT30_SendsHr(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.elapsedSeconds = 15;
    values.hr = 160;
    values.totalAscent = 999;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 30초 전 → HR 슬롯에 hr 그대로
    var expected = [0x0B, 0xA0, 0x00, 0x00, 0x00]b;  // 160
    return findAndCompare(packets, 0x0B, expected, logger);
}

(:test)
function testCyclingStrategy_HrLockAt30_WithHr_StaysHr(logger as Logger) as Boolean {
    var strategy = new CyclingStrategy();
    var values = new MetricValues();

    // 0~29초 동안 hr 가끔 잡힘
    values.hr = 155;
    for (var t = 0; t < 30; t++) {
        values.elapsedSeconds = t;
        strategy.buildPackets(values);
    }

    // 30초 시점 — HR 락 발동
    values.elapsedSeconds = 30;
    values.hr = 160;
    values.totalAscent = 500;
    var packets = strategy.buildPackets(values);

    // HR 모드 확정 → hr=160 전송
    var expected = [0x0B, 0xA0, 0x00, 0x00, 0x00]b;
    return findAndCompare(packets, 0x0B, expected, logger);
}

(:test)
function testCyclingStrategy_HrLockAt30_NoHr_SwitchesAscent(logger as Logger) as Boolean {
    var strategy = new CyclingStrategy();
    var values = new MetricValues();

    // 0~29초 동안 hr 항상 0 (Edge 시뮬레이션)
    values.hr = 0;
    for (var t = 0; t < 30; t++) {
        values.elapsedSeconds = t;
        strategy.buildPackets(values);
    }

    // 30초 시점 — totalAscent 락 발동
    values.elapsedSeconds = 30;
    values.hr = 0;
    values.totalAscent = 850;
    var packets = strategy.buildPackets(values);

    // totalAscent 모드 확정 → 850 전송
    var expected = [0x0B, 0x52, 0x03, 0x00, 0x00]b;  // 850 = 0x352
    return findAndCompare(packets, 0x0B, expected, logger);
}

(:test)
function testCyclingStrategy_HrComesBackAfterLockedAscent_StaysAscent(logger as Logger) as Boolean {
    var strategy = new CyclingStrategy();
    var values = new MetricValues();

    // 0~29초 hr=0
    values.hr = 0;
    for (var t = 0; t < 30; t++) {
        values.elapsedSeconds = t;
        strategy.buildPackets(values);
    }

    // 30초에 락 발동 (totalAscent 모드)
    values.elapsedSeconds = 30;
    values.totalAscent = 100;
    strategy.buildPackets(values);

    // 60초 — HR 늦게 잡혔지만 모드 깜빡임 없음
    values.elapsedSeconds = 60;
    values.hr = 150;  // HR 이제 잡힘
    values.totalAscent = 200;
    var packets = strategy.buildPackets(values);

    // 여전히 totalAscent 전송 (HR 무시)
    var expected = [0x0B, 0xC8, 0x00, 0x00, 0x00]b;  // 200
    return findAndCompare(packets, 0x0B, expected, logger);
}
```

- [ ] **Step 4.2: 테스트 실패 확인 (락 미구현)**

Run: Run Test.
Expected: `testCyclingStrategy_HrLockAt30_NoHr_SwitchesAscent` 와 `testCyclingStrategy_HrComesBackAfterLockedAscent_StaysAscent` 가 FAIL.
(앞 2개는 우연히 PASS 할 수 있음 — 락이 없으면 항상 hr 그대로 전달.)

- [ ] **Step 4.3: HR 락 로직 추가**

`source/CyclingStrategy.mc` 전체를 다음으로 교체:

```monkeyc
using Toybox.Lang;
using ILensProtocol;

//! Cycling mode metric strategy.
//! 슬롯 매핑:
//!   0x07: paceSeconds → speedKmh
//!   0x0E: cadence → altitudeM
//!   0x0B: hr OR totalAscent (30초 시점에 결정, 이후 영구 고정)
class CyclingStrategy {

    private const HR_LOCK_THRESHOLD_SEC = 30;

    private var _hrEverSeen as Lang.Boolean = false;
    private var _slotLocked as Lang.Boolean = false;
    private var _useAscent as Lang.Boolean = false;

    function initialize() {
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        updateHrLock(values.hr, values.elapsedSeconds);

        var hrSlotValue = _useAscent ? values.totalAscent : values.hr;

        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(values.speedKmh));
        packets.add(ILensProtocol.createHeartRatePacket(hrSlotValue));
        packets.add(ILensProtocol.createCadencePacket(values.altitudeM));
        packets.add(ILensProtocol.createDistancePacket(values.distance));
        return packets;
    }

    //! 30초까지 hr 가 한 번이라도 유효(>0)했으면 HR 모드, 아니면 totalAscent 모드.
    //! 30초 시점에 단 한 번 결정 후 영구 고정. 이후 hr 가 늦게 들어와도 모드 안 바뀜.
    private function updateHrLock(hr as Lang.Number, elapsedSeconds as Lang.Number) as Void {
        if (hr != null && hr > 0) {
            _hrEverSeen = true;
        }
        if (!_slotLocked && elapsedSeconds >= HR_LOCK_THRESHOLD_SEC) {
            _useAscent = !_hrEverSeen;
            _slotLocked = true;
        }
    }
}
```

- [ ] **Step 4.4: 4개 락 테스트 통과 확인**

Run: Run Test.
Expected: HR 락 테스트 4개 모두 PASS. 이전 작업의 모든 테스트도 여전히 PASS.

- [ ] **Step 4.5: 커밋**

```bash
git add source/CyclingStrategy.mc source/Tests.mc
git commit -m "feat: CyclingStrategy HR 30초 락 상태 머신 추가"
```

---

## Task 5: detectStrategy() 함수

`Activity.getProfileInfo().sport` 기반 strategy 선택. null 안전.

**Files:**
- Modify: `source/MetricStrategy.mc`
- Test: `source/Tests.mc` (수정)

- [ ] **Step 5.1: detectStrategy 테스트 작성**

`source/Tests.mc` 끝에 추가:

```monkeyc
// === detectStrategy tests ===

// 참고: Activity.Info 가 (:test) 환경에서 sport 필드를 가질 수 없으므로
// sport 정수값을 직접 받는 헬퍼 detectStrategyForSport(sportValue) 를 테스트한다.
// detectStrategy(info) 는 이 헬퍼를 호출하는 얇은 래퍼.

(:test)
function testDetectStrategy_CyclingSport_ReturnsCycling(logger as Logger) as Boolean {
    var strategy = detectStrategyForSport(Activity.SPORT_CYCLING);
    return strategy instanceof CyclingStrategy;
}

(:test)
function testDetectStrategy_RunningSport_ReturnsRunning(logger as Logger) as Boolean {
    var strategy = detectStrategyForSport(Activity.SPORT_RUNNING);
    return strategy instanceof RunningStrategy;
}

(:test)
function testDetectStrategy_GenericSport_ReturnsRunning(logger as Logger) as Boolean {
    // 알 수 없는 sport → 안전한 기본값 RunningStrategy
    var strategy = detectStrategyForSport(Activity.SPORT_GENERIC);
    return strategy instanceof RunningStrategy;
}

(:test)
function testDetectStrategy_NullSport_ReturnsRunning(logger as Logger) as Boolean {
    // sport = null (profileInfo 자체가 null 인 경우) → 안전한 기본값
    var strategy = detectStrategyForSport(null);
    return strategy instanceof RunningStrategy;
}
```

`source/Tests.mc` 상단에 import 추가:

```monkeyc
using Toybox.Activity;
```

- [ ] **Step 5.2: 테스트 실패 확인**

Expected: `detectStrategyForSport` 미정의 빌드 에러.

- [ ] **Step 5.3: detectStrategy 구현**

`source/MetricStrategy.mc` 끝에 다음 추가:

```monkeyc
//! sport 정수값으로부터 strategy 선택. 테스트 가능한 진입점.
//! Activity.SPORT_CYCLING → CyclingStrategy
//! 그 외 (RUNNING/GENERIC/null/unknown) → RunningStrategy (안전한 기본값)
function detectStrategyForSport(sportValue as Lang.Number or Null) as Lang.Object {
    if (sportValue != null && sportValue == Activity.SPORT_CYCLING) {
        return new CyclingStrategy();
    }
    return new RunningStrategy();
}

//! Activity.Info 로부터 strategy 선택. compute() 첫 호출에서 사용.
function detectStrategy(info as Activity.Info or Null) as Lang.Object {
    if (info == null) {
        return new RunningStrategy();
    }
    var profile = Activity.getProfileInfo();
    var sportValue = (profile != null) ? profile.sport : null;
    return detectStrategyForSport(sportValue);
}
```

`source/MetricStrategy.mc` 상단 import 확장:

```monkeyc
using Toybox.Lang;
using Toybox.Activity;
```

- [ ] **Step 5.4: 4개 테스트 통과 확인**

Run: Run Test.
Expected: 4개 모두 PASS.

- [ ] **Step 5.5: 커밋**

```bash
git add source/MetricStrategy.mc source/Tests.mc
git commit -m "feat: detectStrategy() 함수 추가 (sport 기반 선택)"
```

---

## Task 6: RunVisionIQView 에 strategy 연결

가장 위험한 단계. 기존 패킷 생성 블록(line 607-612) 만 strategy 호출로 대체. 다른 모든 코드는 손대지 않는다.

**Files:**
- Modify: `source/RunVisionIQView.mc`

- [ ] **Step 6.1: 변경 전 백업 확인**

기존 line 607-612 정확한 내용 (참조용):

```monkeyc
// Queue에 5개 메트릭 추가 (v1.0.2: Sport Time 사용, Power/Current Time 제거)
_writeQueue.add(ILensProtocol.createExerciseTimePacket(_elapsedSeconds));
_writeQueue.add(ILensProtocol.createVelocityPacket(paceSeconds));
_writeQueue.add(ILensProtocol.createHeartRatePacket(hr));
_writeQueue.add(ILensProtocol.createCadencePacket(cadence));
_writeQueue.add(ILensProtocol.createDistancePacket(distance != null ? distance : 0));
```

이 5줄을 strategy 호출 한 번으로 대체할 것.

- [ ] **Step 6.2: import 추가**

`source/RunVisionIQView.mc` 상단의 `using ILensProtocol;` 다음 줄에 추가:

```monkeyc
using ILensProtocol;
// (이미 있음)
```

Monkey C는 같은 디렉토리의 `.mc` 파일을 자동으로 인식하므로 `MetricStrategy`, `RunningStrategy`, `CyclingStrategy` 는 별도 `using` 불필요. 단, IDE 가 인식 못 하면 다음 추가:

```monkeyc
// (using 불필요 — 같은 패키지)
```

- [ ] **Step 6.3: strategy 멤버 변수 추가**

`source/RunVisionIQView.mc` 의 다른 멤버 변수들 근처(line 95 부근 `_pairingRetryCount` 다음) 에 추가:

```monkeyc
// === 사이클/러닝 모드 분기 (Strategy 패턴) ===
private var _strategy as Lang.Object or Null = null;
private var _metricValues as MetricValues or Null = null;
```

- [ ] **Step 6.4: initialize() 에 MetricValues 생성 추가**

`initialize()` 함수 본문 끝에 추가 (정확한 위치는 기존 `function initialize()` 블록 안):

```monkeyc
_metricValues = new MetricValues();
```

- [ ] **Step 6.5: compute() 의 strategy 초기화 + 패킷 생성 블록 교체**

`source/RunVisionIQView.mc` 의 line 604-612 (try 블록 내 5개 packet add) 를 다음으로 교체:

변경 전:
```monkeyc
if (!_isWriting) {
    _writeQueue = [] as Lang.Array<Lang.ByteArray>;

    // Queue에 5개 메트릭 추가 (v1.0.2: Sport Time 사용, Power/Current Time 제거)
    _writeQueue.add(ILensProtocol.createExerciseTimePacket(_elapsedSeconds));  // ⭐ Sport Time (0x03)
    _writeQueue.add(ILensProtocol.createVelocityPacket(paceSeconds));          // Pace
    _writeQueue.add(ILensProtocol.createHeartRatePacket(hr));                  // Heart Rate
    _writeQueue.add(ILensProtocol.createCadencePacket(cadence));              // Cadence
    _writeQueue.add(ILensProtocol.createDistancePacket(distance != null ? distance : 0));  // Distance
```

변경 후:
```monkeyc
if (!_isWriting) {
    _writeQueue = [] as Lang.Array<Lang.ByteArray>;

    // Strategy 초기화 (첫 호출 시 단 한 번)
    if (_strategy == null) {
        _strategy = detectStrategy(info);
    }

    // MetricValues 채우기 (compute() 내에서 이미 계산된 값들 복사)
    _metricValues.elapsedSeconds = _elapsedSeconds;
    _metricValues.paceSeconds = paceSeconds;
    _metricValues.speedKmh = speedKmh;
    _metricValues.hr = (hr != null) ? hr : 0;
    _metricValues.cadence = cadence;
    _metricValues.distance = (distance != null) ? distance.toNumber() : 0;
    _metricValues.altitudeM = (altitude != null) ? altitude.toNumber() : 0;
    _metricValues.totalAscent = (info != null && info has :totalAscent && info.totalAscent != null) ? info.totalAscent.toNumber() : 0;

    // Strategy 가 5개 패킷 생성 (러닝 / 사이클 분기)
    var packets = _strategy.buildPackets(_metricValues);
    for (var i = 0; i < packets.size(); i++) {
        _writeQueue.add(packets[i]);
    }
```

> **주의**: 위 코드는 `speedKmh`, `cadence`, `altitude` 변수가 같은 `compute()` 스코프에서 이미 선언되어 있음을 가정한다. 만약 `cadence`, `altitude` 가 `if` 블록 내부 스코프에서만 선언되어 위치 접근 불가능하면, 그 변수들을 try 블록 밖 (compute 함수 상단 부근)으로 끌어올린다. 컴파일 에러로 즉시 확인 가능.

- [ ] **Step 6.6: 빌드 + 빌드 에러 수정**

Run: `monkeyc` 빌드 or VS Code Build.
Expected outcome: 빌드 성공. 변수 스코프 에러 발생 시 해당 변수를 compute() 상단 적절한 위치로 이동.

- [ ] **Step 6.7: 모든 단위 테스트 재실행**

Run: Run All Tests.
Expected: Task 1~5 의 모든 테스트 + 기존 ILensProtocol 테스트 모두 PASS.

- [ ] **Step 6.8: 시뮬레이터 실기 검증 (러닝)**

Run: `run-simulator.bat` (또는 VS Code → Run Simulator).
시뮬레이터에서 RUNNING 액티비티 시작 → DFLogger 로그 또는 화면 표시 확인:
- speed/HR/cadence/distance 값이 이전 빌드와 동일하게 표시되는지
- TX 로그에 패킷이 5초 주기로 전송되는지

- [ ] **Step 6.9: 시뮬레이터 실기 검증 (사이클)**

시뮬레이터에서 CYCLING 액티비티 시작:
- 0x07 슬롯이 km/h 값 (예: 25) 으로 표시되는지
- 0x0E 슬롯이 고도 (예: 100) 로 표시되는지
- 30초 경과 후 HR 슬롯 동작 확인

- [ ] **Step 6.10: 커밋**

```bash
git add source/RunVisionIQView.mc
git commit -m "feat: RunVisionIQView.compute() 에 Strategy 디스패치 연결

기존 패킷 생성 블록(line 607-612)을 _strategy.buildPackets() 호출로 대체.
러닝 모드 패킷 바이트는 회귀 테스트로 보존 확인.

사이클 액티비티 시작 시 Activity.SPORT_CYCLING 감지 → CyclingStrategy 자동 선택."
```

---

## Task 7: manifest.xml 버전 업

새 기능이므로 마이너 버전 업.

**Files:**
- Modify: `manifest.xml`

- [ ] **Step 7.1: 현재 버전 확인**

Run: `grep 'version=' manifest.xml | head -1`
Expected: `version="1.1.10"` (또는 현재 버전)

- [ ] **Step 7.2: 버전 1.1.10 → 1.2.0 변경**

`manifest.xml` 의 `<iq:application ... version="1.1.10">` 부분을 `version="1.2.0"` 으로 변경.

- [ ] **Step 7.3: 빌드 검증**

Run: `monkeyc` 빌드.
Expected: 성공.

- [ ] **Step 7.4: 커밋**

```bash
git add manifest.xml
git commit -m "chore: manifest version 1.1.10 → 1.2.0 (사이클 모드 추가)"
```

---

## Task 8: 최종 회귀 검증 + PR

**Files:** (없음 — 검증만)

- [ ] **Step 8.1: 모든 단위 테스트 실행**

Run: Run All Tests.
Expected: 모든 테스트 PASS (예상 합계: 기존 + 17개 신규).

- [ ] **Step 8.2: 코드 리뷰 체크리스트 점검**

Spec §5 의 체크리스트:
1. [ ] `RunningStrategy.mc` 의 `buildPackets()` 가 기존 라인 608-612 와 라인별로 동등
2. [ ] `RunVisionIQView.mc` 변경이 strategy 초기화 + 디스패치 호출 + MetricValues 채우기에 한정
3. [ ] `ILensProtocol.mc` 무수정 — `git diff main -- source/ILensProtocol.mc` 출력이 비어있어야 함
4. [ ] `manifest.xml` 변경이 버전 한 줄만
5. [ ] 사이클 전용 상태 변수가 `CyclingStrategy` 내부에만 존재

- [ ] **Step 8.3: 시뮬레이터에서 변경 전/후 러닝 BLE 패킷 바이너리 비교**

main 브랜치 빌드와 현 브랜치 빌드 각각으로 같은 시나리오 (예: 15km/h, HR=140, cadence=170, distance=1000, elapsed=300) 실행 후 DFLogger TX 패킷 출력 캡처. 5개 패킷의 hex 가 완전 동일한지 확인.

- [ ] **Step 8.4: 실기기 검증 (선택, 가능한 경우)**

가민 워치 실기에서:
- 러닝 액티비티 시작 → rLens 표시 정상
- 사이클 액티비티 시작 → rLens 에 속도 (km/h), 고도, HR 표시
- 30초 이후 HR 동작 확인

- [ ] **Step 8.5: PR 생성**

```bash
gh pr create --title "feat: 사이클 모드 추가 (Phase 1: 워치)" --body "$(cat <<'EOF'
## Summary
- Garmin Connect IQ DataField 에 사이클 액티비티 자동 감지 + 메트릭 재매핑
- Strategy 패턴으로 러닝/사이클 모드를 격리 → 러닝 동작 사이드이펙트 0

## 메트릭 매핑
- 0x07: 페이스(running) → 속도(cycling)
- 0x0E: 케이던스(running) → 고도(cycling)
- 0x0B: HR(running) → HR or 누적상승(cycling, 30초 락)

## Test plan
- [ ] 17개 단위 테스트 모두 PASS
- [ ] 시뮬레이터 러닝 액티비티 — BLE 패킷 바이트가 변경 전과 동일
- [ ] 시뮬레이터 사이클 액티비티 — speed/altitude/HR 슬롯 정상
- [ ] FR165 실기기 — 러닝/사이클 각각 정상

Spec: `Docs/superpowers/specs/2026-05-15-cycling-mode-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 변경 요약

**새 파일 (3):**
- `source/MetricStrategy.mc` — MetricValues + detectStrategy
- `source/RunningStrategy.mc` — 러닝 패킷 생성
- `source/CyclingStrategy.mc` — 사이클 패킷 생성 + HR 락

**수정 파일 (3):**
- `source/RunVisionIQView.mc` — strategy 디스패치 (line 604-612 교체, 멤버 추가)
- `source/Tests.mc` — 17개 단위 테스트 추가
- `manifest.xml` — version 1.1.10 → 1.2.0

**무수정 (보호):**
- `source/ILensProtocol.mc`
- `source/RunVisionIQApp.mc`
- `source/DFLogger.mc`

---

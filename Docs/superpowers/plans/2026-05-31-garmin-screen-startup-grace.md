# Garmin 운동 시작 화면 그레이스(30초) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 운동 시작 시 글래스 화면 설정과 무관하게 처음 30초간 화면을 연속으로 켜두어 사용자가 데이터 표시를 확인할 수 있게 한다.

**Architecture:** 순수 상태머신 `ScreenGrace`(BLE I/O 없음, 단위 테스트 가능)가 이벤트를 받아 상태를 전이하고, `compute()`가 매 틱 `pump()`로 "이번 슬롯에 수행할 BLE 액션 1개"를 받아 hibernation characteristic에 read/write를 수행한다. **모든 그레이스 BLE op은 기존 메트릭 송출과 동일한 `!_isWriting` 슬롯을 공유**하므로 둘이 동시에 나가지 않는다(느린 기기 freeze 방지). fail-safe `hibernation=30`을 써서 복원 누락 시에도 펌웨어가 30초 뒤 자동으로 화면을 끈다.

**Tech Stack:** Monkey C (Garmin Connect IQ SDK), `Toybox.BluetoothLowEnergy`, `Toybox.Test` 단위 테스트.

**설계 문서:** `Docs/superpowers/specs/2026-05-31-garmin-screen-startup-grace-design.md`

---

## 공통: Mac 빌드/테스트 명령

```bash
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin"
KEY="$HOME/.Garmin/developer_key.der"
cd /Users/jhkim/00.Projects/00.RunVision/runvision-iq

# 단위 테스트 빌드 + 실행 (시뮬레이터가 떠 있어야 함)
"$SDK/monkeyc" -f monkey.jungle -o bin/test.prg -y "$KEY" -d fr165 --unit-test
"$SDK/monkeydo" bin/test.prg fr165 -t
# 기대 출력: 각 test 함수가 PASS, 마지막에 "RAN N tests ... PASSED"
```

> ⚠️ Monkey C 제약: 32-bit **signed** integer만(최대 0x7FFFFFFF). hibernation은 0–65535라 안전.

---

## File Structure

- **Create** `source/ScreenGrace.mc` — 그레이스 상태머신(순수 로직, BLE 의존 없음). 책임: "지금 어떤 화면 op을 해야 하는가"를 이벤트/pump로 결정.
- **Modify** `source/ILensProtocol.mc` — hibernation characteristic UUID 상수 + UINT16 LE 인코더/디코더 추가.
- **Modify** `source/RunVisionIQView.mc` — 프로파일에 Device Config Service+hibernation char 등록, char 확보, 이벤트 배선(onTimerStart/연결준비/콜백/종료 → 상태머신 notify), `compute()`에서 pump→BLE 수행.
- **Modify** `source/Tests.mc` — ScreenGrace 상태전이 + 인코더 단위 테스트.

> **screenOff char은 등록하지 않는다**(fail-safe 설계: hibernation-only). Task 0 검증에서 hibernation-only로 화면 유지가 안 되면 screenOff를 대칭으로 추가(별도 후속).

---

## Task 0: ble_tool 검증 슬라이스 (구현 값 확정 — 게이트)

**목적:** "어떤 값을 쓸지"와 "OFF→ON 처리 필요 여부"를 실측으로 확정. 이게 안 끝나면 Task 4–6의 BLE 동작이 추측이 된다.

**Files:** 코드 변경 없음. `tools/rlens_ble_tool.py` 사용. 글래스 + (가능하면) 메트릭 송출 중인 워치 필요.

- [ ] **Step 1: 동시성 — 메트릭 흐르는 중 hibernation write**

워치로 운동을 시작해 메트릭이 글래스로 흐르는 상태에서, `ble_tool`로 글래스 Device Config Service `f1491672-dd25-4322-b3de-20747ae657c4`에 `[0x1E,0x00]`(=30) write.
기대: write 성공(GATT OK), 워치 메트릭(HR/케이던스)이 **끊기거나 freeze되지 않음**.

- [ ] **Step 2: hibernation-only 화면 유지**

`screenOff`는 건드리지 않고 `hibernation=30`만 write.
기대: 화면이 **30초 연속 켜진 뒤 자동으로 꺼진다**.
- 안 되면(예: screenOff도 낮아야 켜짐 유지) → 결과 기록 후 STOP, 사용자에게 보고(Task 4–6에 screenOff 대칭 추가 필요).

- [ ] **Step 3: OFF→ON 즉시성**

화면이 꺼진 상태에서 `hibernation=30` write.
기대: 화면이 즉시 켜진다. 안 켜지면(설정만 바뀌고 다음 wake까지 대기) → View가 write 후 메트릭 write로 wake를 유도하는지 확인 필요. 결과 기록.

- [ ] **Step 4: op당 지연 실측**

read 1회 + write 1회 왕복 지연(ms) 측정. 기대: 각 < 1s.

- [ ] **Step 5: 검증 결과를 설계 문서에 기록 + 커밋**

`Docs/superpowers/specs/2026-05-31-garmin-screen-startup-grace-design.md` 하단에 "## 검증 결과(2026-05-31)" 절 추가(hibernation-only 가부 / OFF→ON 가부 / 동시성 / op 지연).
```bash
git add Docs/superpowers/specs/2026-05-31-garmin-screen-startup-grace-design.md
git commit -m "docs(spec): ble_tool 검증 결과 기록 (화면 그레이스)"
```

---

## Task 1: hibernation 값 인코더/디코더 (ILensProtocol)

**Files:**
- Modify: `source/ILensProtocol.mc` (module `ILensProtocol`, characteristic UUID 상수 근처)
- Test: `source/Tests.mc`

- [ ] **Step 1: 실패하는 테스트 작성** — `source/Tests.mc` 끝에 추가:

```monkeyc
(:test)
function testHibernationEncode_30(logger as Logger) as Boolean {
    var bytes = ILensProtocol.buildHibernationValue(30);   // 30 = 0x001E → LE [0x1E,0x00]
    return bytes.size() == 2 && bytes[0] == 0x1E && bytes[1] == 0x00;
}

(:test)
function testHibernationEncode_65535(logger as Logger) as Boolean {
    var bytes = ILensProtocol.buildHibernationValue(65535); // 0xFFFF → [0xFF,0xFF]
    return bytes.size() == 2 && bytes[0] == 0xFF && bytes[1] == 0xFF;
}

(:test)
function testHibernationParse_roundtrip(logger as Logger) as Boolean {
    var a = ILensProtocol.parseHibernationValue([0x05, 0x00]b);  // 5
    var b = ILensProtocol.parseHibernationValue([0x3C, 0x00]b);  // 60
    var c = ILensProtocol.parseHibernationValue([0xFF, 0xFF]b);  // 65535
    logger.debug("parsed: " + a + "," + b + "," + c);
    return a == 5 && b == 60 && c == 65535;
}

(:test)
function testHibernationParse_shortBytesDefaults(logger as Logger) as Boolean {
    return ILensProtocol.parseHibernationValue([0x05]b) == 65535; // 2바이트 미만 → 안전 기본값
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: 공통 monkeyc 테스트 빌드.
Expected: 컴파일 에러 — `buildHibernationValue`/`parseHibernationValue` 미정의.

- [ ] **Step 3: 최소 구현** — `source/ILensProtocol.mc`의 characteristic UUID 상수(예: `BATTERY_LEVEL_UUID`) 아래에 추가:

```monkeyc
    // Device Config Service(58211c97) 화면 설정 characteristic
    const HIBERNATION_TIME_UUID = BluetoothLowEnergy.stringToUuid("f1491672-dd25-4322-b3de-20747ae657c4");

    //! hibernation 초(0-65535)를 UINT16 little-endian 2바이트로 인코딩.
    //! 글래스 프로토콜(iLens BLE V1.0.10 §3.5) + Flutter setHibernationTime 인코딩과 일치.
    function buildHibernationValue(seconds as Lang.Number) as Lang.ByteArray {
        return [(seconds & 0xFF) as Lang.Number, ((seconds >> 8) & 0xFF) as Lang.Number]b;
    }

    //! UINT16 LE 2바이트를 초로 디코딩. 2바이트 미만이면 65535(항상켜짐) 안전 기본값.
    function parseHibernationValue(bytes as Lang.ByteArray) as Lang.Number {
        if (bytes.size() < 2) { return 65535; }
        return ((bytes[0] & 0xFF) | ((bytes[1] & 0xFF) << 8)) as Lang.Number;
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: 공통 monkeyc 테스트 빌드 + `monkeydo bin/test.prg fr165 -t`.
Expected: 위 4개 PASS, 기존 테스트 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add source/ILensProtocol.mc source/Tests.mc
git commit -m "feat(ilens): hibernation 값 UINT16 LE 인코더/디코더 + UUID"
```

---

## Task 2: ScreenGrace 상태머신 — pump 기반 정상 경로

**핵심:** BLE 액션은 이벤트 콜백이 즉시 발생시키지 않는다. 콜백은 상태만 전이(`notify*`)하고, **`compute()`가 매 틱 `pump()`를 호출해** 그 슬롯에 수행할 액션 1개를 받는다(메트릭 송출과 동일 슬롯 공유).

**Files:**
- Create: `source/ScreenGrace.mc`
- Test: `source/Tests.mc`

- [ ] **Step 1: 실패하는 테스트 작성** — `source/Tests.mc` 끝에 추가:

```monkeyc
(:test)
function testScreenGrace_happyPath(logger as Logger) as Boolean {
    var g = new ScreenGrace();
    g.notifyConnectionReady();
    g.notifyWorkoutStarted();                                  // ARMED
    if (g.pump(0) != ScreenGrace.ACTION_READ) { return false; }
    g.notifyReadComplete(5);                                   // OVERRIDE_READY, saved=5
    if (g.savedHibernation() != 5) { return false; }
    if (g.pump(0) != ScreenGrace.ACTION_WRITE_OVERRIDE) { return false; }
    g.notifyWriteComplete(0);                                  // ACTIVE @ t=0
    if (!g.isActive()) { return false; }
    if (g.pump(29000) != ScreenGrace.ACTION_NONE) { return false; }       // 29s: 아직
    if (g.pump(30000) != ScreenGrace.ACTION_WRITE_RESTORE) { return false; } // 30s
    g.notifyWriteComplete(30000);                              // DONE
    return g.state() == ScreenGrace.STATE_DONE;
}

(:test)
function testScreenGrace_armNeedsBothTriggers(logger as Logger) as Boolean {
    var g = new ScreenGrace();
    g.notifyWorkoutStarted();                                  // 연결 전
    if (g.pump(0) != ScreenGrace.ACTION_NONE) { return false; }
    g.notifyConnectionReady();                                 // 이제 ARMED
    return g.pump(0) == ScreenGrace.ACTION_READ;
}

(:test)
function testScreenGrace_doneIsTerminal(logger as Logger) as Boolean {
    var g = new ScreenGrace();
    g.notifyConnectionReady(); g.notifyWorkoutStarted();
    g.pump(0); g.notifyReadComplete(5); g.pump(0); g.notifyWriteComplete(0);
    g.pump(30000); g.notifyWriteComplete(30000);               // DONE
    return g.pump(60000) == ScreenGrace.ACTION_NONE
        && g.state() == ScreenGrace.STATE_DONE;
}

(:test)
function testScreenGrace_overrideValueIs30(logger as Logger) as Boolean {
    return ScreenGrace.OVERRIDE_HIB == 30;                     // fail-safe 값
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: 공통 monkeyc 테스트 빌드.
Expected: 컴파일 에러 — `ScreenGrace` 미정의.

- [ ] **Step 3: 최소 구현** — `source/ScreenGrace.mc` 생성:

```monkeyc
import Toybox.Lang;

//! 운동 시작 화면 그레이스 상태머신 (순수 로직, BLE I/O 없음).
//! 콜백은 notify*로 상태만 전이. compute()가 매 틱 pump()로 BLE 액션 1개를 받아 수행.
//! fail-safe: 오버라이드 값은 30초(복원 누락 시 펌웨어가 자동으로 화면 끔).
class ScreenGrace {
    enum {
        STATE_IDLE = 0,
        STATE_ARMED = 1,            // 두 트리거 충족, read 대기
        STATE_READ_PENDING = 2,     // read 요청 in-flight
        STATE_OVERRIDE_READY = 3,   // 오버라이드 write 대기
        STATE_OVERRIDE_PENDING = 4, // 오버라이드 write in-flight
        STATE_ACTIVE = 5,           // 화면 ON, 30초 카운트
        STATE_RESTORE_READY = 6,    // 복원 write 대기(경과 or abort)
        STATE_RESTORE_PENDING = 7,  // 복원 write in-flight
        STATE_DONE = 8
    }
    enum {
        ACTION_NONE = 0,
        ACTION_READ = 1,            // requestRead(hibernation)
        ACTION_WRITE_OVERRIDE = 2,  // requestWrite(hibernation, OVERRIDE_HIB)
        ACTION_WRITE_RESTORE = 3    // requestWrite(hibernation, savedHibernation)
    }
    static const GRACE_MS = 30000;
    static const OVERRIDE_HIB = 30;

    private var _state as Lang.Number = STATE_IDLE;
    private var _ws as Lang.Boolean = false;          // workout started
    private var _cr as Lang.Boolean = false;          // connection ready
    private var _savedHib as Lang.Number or Null = null;
    private var _graceStartMs as Lang.Number = 0;

    function initialize() {}

    function notifyWorkoutStarted() as Void { _ws = true; arm(); }
    function notifyConnectionReady() as Void { _cr = true; arm(); }
    private function arm() as Void {
        if (_state == STATE_IDLE && _ws && _cr) { _state = STATE_ARMED; }
    }

    //! compute()의 !_isWriting 슬롯에서 매 틱 호출. 이번 슬롯에 수행할 BLE 액션 1개(또는 NONE)를
    //! 반환하고 해당 *_PENDING 상태로 전이. 메트릭과 동일 슬롯을 공유 → 충돌 없음.
    function pump(nowMs as Lang.Number) as Lang.Number {
        if (_state == STATE_ARMED) {
            _state = STATE_READ_PENDING; return ACTION_READ;
        } else if (_state == STATE_OVERRIDE_READY) {
            _state = STATE_OVERRIDE_PENDING; return ACTION_WRITE_OVERRIDE;
        } else if (_state == STATE_ACTIVE) {
            if (nowMs - _graceStartMs >= GRACE_MS) {
                _state = STATE_RESTORE_PENDING; return ACTION_WRITE_RESTORE;
            }
        } else if (_state == STATE_RESTORE_READY) {
            _state = STATE_RESTORE_PENDING; return ACTION_WRITE_RESTORE;
        }
        return ACTION_NONE;
    }

    function notifyReadComplete(seconds as Lang.Number) as Void {
        if (_state == STATE_READ_PENDING) {
            _savedHib = seconds;
            _state = STATE_OVERRIDE_READY;
        }
    }

    function notifyWriteComplete(nowMs as Lang.Number) as Void {
        if (_state == STATE_OVERRIDE_PENDING) {
            _state = STATE_ACTIVE; _graceStartMs = nowMs;
        } else if (_state == STATE_RESTORE_PENDING) {
            _state = STATE_DONE;
        }
    }

    //! 조기 종료/일시정지/끊김. 오버라이드된 적 있으면(_savedHib 저장됨) 복원 예약, 아니면 종료.
    //! 복원 누락해도 OVERRIDE_HIB=30 fail-safe가 받쳐줌.
    function notifyAborted() as Void {
        if (_state == STATE_DONE) { return; }
        if (_savedHib == null) {
            _state = STATE_DONE;
        } else if (_state != STATE_RESTORE_PENDING) {
            _state = STATE_RESTORE_READY;
        }
    }

    function savedHibernation() as Lang.Number or Null { return _savedHib; }
    function state() as Lang.Number { return _state; }
    function isActive() as Lang.Boolean { return _state == STATE_ACTIVE; }
}
```

- [ ] **Step 4: 테스트 통과 확인**

`source/ScreenGrace.mc`가 빌드에 포함되는지 확인(`monkey.jungle` source 글롭이 `source/*.mc`면 자동 — 아니면 추가).
Run: 공통 monkeyc 테스트 빌드 + 실행.
Expected: Task 2의 4개 PASS, 기존 전부 PASS.

- [ ] **Step 5: 커밋**

```bash
git add source/ScreenGrace.mc source/Tests.mc
git commit -m "feat(grace): ScreenGrace pump 상태머신 정상경로"
```

---

## Task 3: ScreenGrace — 조기 종료(abort) 복원

**Files:**
- Modify: `source/Tests.mc` (테스트 추가). `notifyAborted`는 Task 2에서 이미 구현됨 → 이 Task는 동작 검증.

- [ ] **Step 1: 테스트 작성** — `source/Tests.mc` 끝에 추가:

```monkeyc
(:test)
function testScreenGrace_abortDuringActiveRestores(logger as Logger) as Boolean {
    var g = new ScreenGrace();
    g.notifyConnectionReady(); g.notifyWorkoutStarted();
    g.pump(0); g.notifyReadComplete(5); g.pump(0); g.notifyWriteComplete(0); // ACTIVE
    g.notifyAborted();                                          // RESTORE_READY
    if (g.pump(5000) != ScreenGrace.ACTION_WRITE_RESTORE) { return false; }
    g.notifyWriteComplete(5000);
    return g.state() == ScreenGrace.STATE_DONE;
}

(:test)
function testScreenGrace_abortBeforeOverrideNoRestore(logger as Logger) as Boolean {
    // READ_PENDING(오버라이드 전, savedHib 없음) 중 종료 → 복원 없음
    var g = new ScreenGrace();
    g.notifyConnectionReady(); g.notifyWorkoutStarted();
    g.pump(0);                                                  // READ_PENDING
    g.notifyAborted();                                          // savedHib==null → DONE
    if (g.pump(0) != ScreenGrace.ACTION_NONE) { return false; }
    return g.state() == ScreenGrace.STATE_DONE;
}

(:test)
function testScreenGrace_abortDuringOverridePendingStillRestores(logger as Logger) as Boolean {
    // 오버라이드 write in-flight 중 종료 → 완료 콜백은 무시되고, 이후 복원
    var g = new ScreenGrace();
    g.notifyConnectionReady(); g.notifyWorkoutStarted();
    g.pump(0); g.notifyReadComplete(5); g.pump(0);              // OVERRIDE_PENDING
    g.notifyAborted();                                          // savedHib=5 → RESTORE_READY
    g.notifyWriteComplete(0);                                   // 오버라이드 완료 콜백: RESTORE_READY라 무시
    if (g.pump(100) != ScreenGrace.ACTION_WRITE_RESTORE) { return false; }
    g.notifyWriteComplete(100);
    return g.state() == ScreenGrace.STATE_DONE;
}

(:test)
function testScreenGrace_abortWhenIdleNoop(logger as Logger) as Boolean {
    var g = new ScreenGrace();
    g.notifyAborted();
    return g.pump(0) == ScreenGrace.ACTION_NONE && g.state() == ScreenGrace.STATE_DONE;
}
```

- [ ] **Step 2: 테스트 실행**

Run: 공통 monkeyc 테스트 빌드 + 실행.
Expected: Task 3의 4개 PASS, 기존 전부 PASS. (실패 시 `notifyAborted` 로직 점검.)

- [ ] **Step 3: 커밋**

```bash
git add source/Tests.mc
git commit -m "test(grace): 조기 종료(abort) 복원 시나리오 테스트"
```

---

## Task 4: 프로파일에 hibernation characteristic 등록 (View)

**Files:**
- Modify: `source/RunVisionIQView.mc` (`getExerciseProfile`, line ~100; `registerProfile` 호출부 line ~162, ~240)

> char 1→2 추가. 등록 한도 초과 시 등록 자체가 실패 → **on-device 1회 확인이 게이트**.

- [ ] **Step 1: getConfigProfile 추가 + 등록**

`source/RunVisionIQView.mc`의 `getExerciseProfile()` 바로 아래에 추가:

```monkeyc
    //! 화면 설정용 Device Config Service(58211c97) 프로파일 (hibernation char).
    private function getConfigProfile() as Lang.Dictionary {
        return {
            :uuid => BluetoothLowEnergy.stringToUuid("58211c97-482a-2808-2d3e-228405f1e749"),
            :characteristics => [
                { :uuid => ILensProtocol.HIBERNATION_TIME_UUID }
            ]
        };
    }
```

`registerProfile(getExerciseProfile())`을 호출하는 **두 곳**(line ~162, ~240) 각각 바로 다음 줄에 추가:

```monkeyc
                BluetoothLowEnergy.registerProfile(getConfigProfile());
```

- [ ] **Step 2: 컴파일 확인**

Run: `"$SDK/monkeyc" -f monkey.jungle -o bin/RunVisionIQ.prg -y "$KEY" -d fr165`
Expected: 빌드 성공.

- [ ] **Step 3: on-device 프로파일 등록 성공 확인 (게이트)**

fr165 실기기 설치 → 글래스 연결. `onProfileRegister` 콜백 status가 두 프로파일 모두 `STATUS_SUCCESS`이고 **기존 메트릭 연결/표시 정상**인지 확인.
- 등록 실패 시 STOP, 사용자 보고.

- [ ] **Step 4: 커밋**

```bash
git add source/RunVisionIQView.mc
git commit -m "feat(grace): Device Config Service hibernation char 프로파일 등록"
```

---

## Task 5: View 이벤트 배선 + compute pump 통합

**Files:**
- Modify: `source/RunVisionIQView.mc`

> 불변식: 화면 경로의 어떤 실패(read/write/char null)도 메트릭 스트리밍을 건드리지 않는다. 모든 화면 BLE 호출은 try/catch로 감싸고 실패 시 그레이스만 포기(`notifyAborted`)한다. 그레이스 BLE op은 메트릭과 동일한 `!_isWriting` 슬롯을 통해서만 나간다.

- [ ] **Step 1: 멤버 추가**

`RunVisionIQView` 멤버 영역(다른 `private var` 근처)에 추가:

```monkeyc
    private var _grace as ScreenGrace = new ScreenGrace();
    private var _hibernationChar as BluetoothLowEnergy.Characteristic or Null = null;
```

- [ ] **Step 2: 연결 시 hibernation char 확보 + 연결준비 통지**

`_exerciseCharacteristic` 확보가 성공하는 지점(서비스 디스커버리 성공 직후) 바로 다음에 추가:

```monkeyc
        // 화면 그레이스용 hibernation char 확보 (실패해도 메트릭엔 영향 없음)
        try {
            _hibernationChar = tryGetServiceCharacteristic(
                ILensProtocol.DEVICE_CONFIG_SERVICE_UUID,
                ILensProtocol.HIBERNATION_TIME_UUID,
                5
            );
        } catch (ex) {
            _hibernationChar = null;
        }
        _grace.notifyConnectionReady();   // 실제 READ는 compute()의 pump 슬롯에서 발생
```

> `ILensProtocol.DEVICE_CONFIG_SERVICE_UUID`는 이미 존재(line ~20).

- [ ] **Step 3: onTimerStart에서 운동시작 통지**

`onTimerStart()`(line ~174)의 `WatchUi.requestUpdate();` 직전에 추가:

```monkeyc
        _grace.notifyWorkoutStarted();    // 실제 op은 pump 슬롯에서
```

- [ ] **Step 4: performGraceBle 헬퍼 추가**

`sendToILens` 인근에 추가:

```monkeyc
    //! pump가 반환한 그레이스 액션을 실제 BLE 호출로 수행. _isWriting을 점유해 메트릭과 직렬화.
    //! 실패 시 _isWriting 해제 + 그레이스 포기(메트릭엔 무영향).
    private function performGraceBle(action as Lang.Number) as Void {
        if (_hibernationChar == null) { _grace.notifyAborted(); return; }
        try {
            _isWriting = true;   // 이 슬롯 점유 (read 완료는 onCharacteristicRead 에서 해제)
            if (action == ScreenGrace.ACTION_READ) {
                _hibernationChar.requestRead();
            } else if (action == ScreenGrace.ACTION_WRITE_OVERRIDE) {
                _hibernationChar.requestWrite(
                    ILensProtocol.buildHibernationValue(ScreenGrace.OVERRIDE_HIB),
                    {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
            } else if (action == ScreenGrace.ACTION_WRITE_RESTORE) {
                var saved = _grace.savedHibernation();
                if (saved == null) { _isWriting = false; return; }
                _hibernationChar.requestWrite(
                    ILensProtocol.buildHibernationValue(saved),
                    {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
            }
        } catch (ex) {
            _isWriting = false;
            _grace.notifyAborted();
        }
    }
```

- [ ] **Step 5: compute()의 송출 슬롯에서 pump 우선 처리**

`source/RunVisionIQView.mc` line 587의 송출 블록을 아래로 교체(그레이스 op이 슬롯을 우선 사용, 없으면 기존 메트릭 송출):

```monkeyc
        if (_isConnected && _exerciseCharacteristic != null && !_isWriting) {
            // 그레이스 BLE op이 이 슬롯을 우선 사용 (메트릭과 직렬화 → 동시 전송 없음)
            var gAct = _grace.pump(System.getTimer());
            if (gAct != ScreenGrace.ACTION_NONE) {
                performGraceBle(gAct);   // 이 tick 메트릭 skip (복원 틱이면 1초 stale — 화면 sleep 전환과 겹쳐 비가시)
            } else {
                try {
                    // MetricValues 채우기 (compute() 내에서 이미 계산된 값들 복사)
                    _metricValues.elapsedSeconds = _elapsedSeconds;
                    _metricValues.paceSeconds = paceSeconds;
                    _metricValues.speedKmh = speedKmh;
                    _metricValues.hr = (hr != null) ? hr : 0;
                    _metricValues.cadence = cadence;
                    _metricValues.distance = (distance != null) ? roundFloat(distance) : 0;
                    _metricValues.altitudeM = (altitude != null) ? roundFloat(altitude) : 0;
                    _metricValues.totalAscent = (info != null && info has :totalAscent && info.totalAscent != null) ? roundFloat(info.totalAscent) : 0;
                    _metricValues.speedValid = speedValid;
                    _metricValues.hrValid = hrValid;
                    _metricValues.cadenceValid = cadenceValid;
                    _metricValues.distanceValid = distanceValid;
                    _metricValues.altitudeValid = (altitude != null);
                    _metricValues.totalAscentValid = (info != null && info has :totalAscent && info.totalAscent != null);
                    var packets = (_strategy as MetricStrategy).buildTickPackets(_metricValues, _computeCount);
                    if (packets.size() > 0) {
                        _writeQueue = packets;
                        processWriteQueue();
                    }
                } catch (ex) {
                    // 송출 에러 무시 (다음 tick 재시도)
                }
            }
        }
```

- [ ] **Step 6: 콜백에서 _isWriting 해제 + 그레이스 notify**

`onCharacteristicRead`(line ~757) 맨 앞에 추가:

```monkeyc
        if (_hibernationChar != null && characteristic.getUuid().equals(ILensProtocol.HIBERNATION_TIME_UUID)) {
            _isWriting = false;   // 슬롯 해제
            _grace.notifyReadComplete(ILensProtocol.parseHibernationValue(value));
            return;
        }
```

`onCharacteristicWrite`(line ~762)는 맨 앞에서 이미 `_isWriting = false`를 한다(line 763). 그 직후에 hibernation 분기 추가:

```monkeyc
        if (_hibernationChar != null && characteristic.getUuid().equals(ILensProtocol.HIBERNATION_TIME_UUID)) {
            _grace.notifyWriteComplete(System.getTimer());
            return;
        }
```

- [ ] **Step 7: 종료/일시정지/끊김에서 abort**

`onTimerStop()`(line ~187), `onTimerPause()`(line ~193), `onConnectedStateChanged`의 **disconnected 분기**(line ~823 부근)에 각각 추가:

```monkeyc
        _grace.notifyAborted();   // 복원은 compute pump가 살아있으면 시도, 아니면 hibernation=30 fail-safe
```

- [ ] **Step 8: 컴파일 확인**

Run: `"$SDK/monkeyc" -f monkey.jungle -o bin/RunVisionIQ.prg -y "$KEY" -d fr165`
Expected: 빌드 성공.

- [ ] **Step 9: 커밋**

```bash
git add source/RunVisionIQView.mc
git commit -m "feat(grace): View 배선 + compute pump 통합 (시작 30초 화면 그레이스)"
```

---

## Task 6: 실기기 게이트 테스트 (fr165)

**Files:** 코드 변경 없음. fr165 + 글래스 필요.

- [ ] **Step 1: 정상 시나리오** — 운동 시작 → 글래스 화면 **30초 연속 켜짐** → 30초 후 설정 모드(달리기 5초 등) 복귀.
- [ ] **Step 2: 메트릭 무회귀** — 그 동안 HR/케이던스/페이스 **끊김·freeze 없음**(a914985 회귀 감시).
- [ ] **Step 3: 조기 종료 fail-safe** — 30초 내 종료 → 화면이 **영구히 켜져 있지 않음**(최대 30초 내 자동 꺼짐).
- [ ] **Step 4: 재연결/페어링 무회귀** — 연결 끊김→재연결, 페어링 흐름 기존과 동일.
- [ ] **Step 5: 회귀 단위 테스트** — 공통 monkeyc 테스트 빌드 + `monkeydo bin/test.prg fr165 -t` → 전체 PASS.

---

## 후속 (이번 스코프 아님)
- Apple Watch(Swift) / Galaxy(Kotlin) 이식 — 동일 fail-safe 설계.
- Task 0에서 hibernation-only가 안 되면 screenOff char 대칭 추가.
- 그레이스 시간(30s) 설정화.

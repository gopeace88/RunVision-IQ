# RunVision-IQ 사이클 모드 설계 (Phase 1: 워치)

> 작성일: 2026-05-15
> 상태: 설계 완료, 구현 대기
> 관련 기획: `Docs/신규기획/2026-05-03-신규기획-검토.md`

---

## 1. 목적과 범위

기존 RunVision-IQ DataField에 **사이클 모드**를 추가한다. 가민 워치의 사이클 액티비티에서 자동 감지되어 rLens HUD에 사이클에 적합한 메트릭을 전송한다.

**핵심 제약**: 러닝 모드 동작에 **사이드이펙트 0**. 기존 사용자가 사이클 모드 추가로 인한 어떠한 동작 변화도 경험해서는 안 된다.

**Phase 1 범위**:
- 가민 워치 (현재 호환 리스트 86개 기기) 자동 분기
- 사이클 액티비티 시 4개 메트릭 슬롯 재매핑

**Phase 1 미포함** (별도 PR):
- Edge 시리즈 (manifest에 추가, 별도 검증 필요)
- 애플워치/갤럭시워치 사이클 모드 (각각 별도 repo, 별도 설계)
- rLens 펌웨어 측 레이블/아이콘 변경 (펌웨어 팀 결정 사항)

---

## 2. 메트릭 매핑

| 슬롯 ID | 러닝 모드 | 사이클 모드 |
|---------|----------|------------|
| `0x03` Sport Time | `elapsedSeconds` | `elapsedSeconds` (동일) |
| `0x06` Distance | `distance` (m) | `distance` (m) (동일) |
| `0x07` Velocity | `paceSeconds` (sec/km) | `speedKmh` (km/h) |
| `0x0B` Heart Rate | `hr` (bpm) | `hr` OR `totalAscent` (m) — 30초 락 |
| `0x0E` Cadence | `cadenceSpm` | `altitudeM` (m) |

**rLens 화면 레이블 제약**: 펌웨어가 슬롯별 단위/아이콘을 고정 표시. 사이클 모드에서도 사용자는 "Pace" 위치에 속도, "Cadence" 위치에 고도 등이 표시됨. 기획문서에서 이미 수용한 제약이며 펌웨어 변경 없이 진행한다.

### Heart Rate 슬롯 30초 락 규칙

사이클 모드에서 `0x0B` 슬롯은 두 가지 의미를 가질 수 있다:
- 워치 내장 광혈류 HR 센서가 정상 동작 → **심박수 (bpm)**
- HR 센서 없음 (Edge 등) 또는 영구 미작동 → **누적 상승고도 (m, totalAscent)**

세션 내 슬롯 의미가 도중에 바뀌면 사용자 혼란이 크므로, **세션 시작 후 30초 시점에 한 번만 결정하고 영구 고정**한다.

```
시작 시: _hrEverSeen=false, _slotLocked=false
매 compute(): hr이 유효(>0)면 _hrEverSeen=true
elapsedSeconds >= 30 시점에 단 한 번:
    _useAscent = !_hrEverSeen
    _slotLocked = true
이후 영구 고정
```

**30초 임계값 근거**: 모던 가민 워치 광혈류 HR이 5-15초, 구형 워치(FR245, Fenix 5 등) 15-30초 워밍업. 30초면 정상 사용 범위 내 모든 워치에 충분.

**워치 HR 일시 드롭아웃 처리**: `_slotLocked=true, _useAscent=false` 상태에서 hr이 일시적으로 null이 되면 0을 전송. 모드 자체는 바뀌지 않는다.

---

## 3. 아키텍처

### Strategy 패턴

```
RunVisionIQView (compute, draw, BLE)
       │
       │ delegates packet building
       ▼
MetricStrategy (duck typing)
   ├── RunningStrategy   ← 기존 동작 이전
   └── CyclingStrategy   ← 신규
```

Monkey C는 인터페이스 키워드가 없지만 duck typing 기반 다형성을 지원한다. 두 strategy가 동일 시그니처 `buildPackets(info, ctx) as Array<ByteArray>` 를 가지면 호출부가 동일하게 처리한다.

### 모드 결정 시점

`compute()` 첫 호출 시 `_strategy == null` 분기에서 단 한 번 결정:

```monkeyc
if (_strategy == null) {
    var profile = Activity.getProfileInfo();
    var sport = (profile != null) ? profile.sport : null;
    _strategy = (sport == Activity.SPORT_CYCLING)
        ? new CyclingStrategy()
        : new RunningStrategy();  // 안전한 기본값
}
```

이후 `_strategy.buildPackets(info, _context)` 호출만 수행. 사용자가 액티비티를 종료하고 다른 종목을 새로 시작하면 onLayout 등에서 strategy를 리셋하는 별도 처리는 필요 없음 (DataField 자체가 새로 init됨).

---

## 4. 컴포넌트 상세

### 새 파일

#### `source/MetricStrategy.mc`

- `class MetricContext` — strategy 간 공유 가변 상태 컨테이너
  - `elapsedSeconds`, `previousAltitude`, `previousDistance`, `userWeight`, `weightInitialized` 등
- `function detectStrategy(info as Activity.Info) as Object` — sport 감지 후 적절 strategy 인스턴스 반환

#### `source/RunningStrategy.mc`

```monkeyc
class RunningStrategy {
    function buildPackets(info as Activity.Info, ctx as MetricContext)
        as Lang.Array<Lang.ByteArray> {
        // 기존 RunVisionIQView.compute() 내 패킷 생성 블록을 그대로 이전:
        // 1. createExerciseTimePacket(ctx.elapsedSeconds)
        // 2. createVelocityPacket(paceSeconds)
        // 3. createHeartRatePacket(hr)
        // 4. createCadencePacket(cadence)
        // 5. createDistancePacket(distance)
    }

    function getDisplayLabels(...) {
        // 워치 화면용 라벨 — 기존 라벨 그대로
    }
}
```

#### `source/CyclingStrategy.mc`

```monkeyc
class CyclingStrategy {
    private var _hrEverSeen as Lang.Boolean = false;
    private var _slotLocked as Lang.Boolean = false;
    private var _useAscent as Lang.Boolean = false;

    function buildPackets(info as Activity.Info, ctx as MetricContext)
        as Lang.Array<Lang.ByteArray> {
        // 1. createExerciseTimePacket(ctx.elapsedSeconds)
        // 2. createVelocityPacket(speedKmh)
        // 3. updateHrLock(hr, ctx.elapsedSeconds)
        //    → _useAscent에 따라 createHeartRatePacket(hr or totalAscent)
        // 4. createCadencePacket(altitudeM)
        // 5. createDistancePacket(distance)
    }

    private function updateHrLock(hr, elapsedSeconds) {
        if (hr != null && hr > 0) { _hrEverSeen = true; }
        if (!_slotLocked && elapsedSeconds >= 30) {
            _useAscent = !_hrEverSeen;
            _slotLocked = true;
        }
    }

    function getDisplayLabels(...) {
        // 워치 화면용 라벨 — speed/altitude 모드
    }
}
```

### 수정 파일

#### `source/RunVisionIQView.mc`

변경 범위 최소화:

1. 멤버 추가: `private var _strategy as Object or Null = null;` `private var _context as MetricContext or Null = null;`
2. `initialize()`: `_context = new MetricContext()`
3. `compute()` 첫 호출 시: `_strategy` null이면 `detectStrategy(info)` 호출
4. 기존 패킷 생성 블록(약 line 597-625)을 `_strategy.buildPackets(info, _context)` 단일 호출로 대체
5. 화면 라벨 갱신 부분: 필요 시 `_strategy.getDisplayLabels()` 활용 (선택 사항, 기존 라벨 코드 그대로 둬도 무방)

**기존 BLE 연결/스캔/재연결 로직, write queue 처리, BleDelegate 콜백 등은 0줄 변경.**

#### `source/Tests.mc`

테스트 추가 (아래 §5 참조).

### 미변경 파일

- `source/ILensProtocol.mc` — 패킷 생성 함수 재사용
- `source/RunVisionIQApp.mc`
- `source/DFLogger.mc`
- `manifest.xml` (Phase 1)
- `resources/`

---

## 5. 테스트 전략

### 단위 테스트 (`Tests.mc` (:test) 어노테이션)

**러닝 모드 회귀 방지 (최우선)**

기존 패킷 바이트와 변경 후 패킷 바이트가 한 비트도 다르지 않음을 보증:

- `testRunningStrategy_VelocityIsPaceSeconds` — paceSeconds=330 → `[0x07, ...]` 페이로드
- `testRunningStrategy_CadenceIsSpm` — cadence=170 → `[0x0E, ...]`
- `testRunningStrategy_HeartRateIsRaw` — hr=150 → `[0x0B, ...]`
- `testRunningStrategy_DistanceIsMeters` — distance=1234 → `[0x06, ...]`
- `testRunningStrategy_SportTimeIsElapsed` — elapsed=600 → `[0x03, ...]`

**사이클 모드 신규 동작**

- `testCyclingStrategy_VelocityIsSpeedKmh` — speedKmh=25 → `0x07` 페이로드에 25
- `testCyclingStrategy_CadenceIsAltitudeM` — altitude=1200 → `0x0E` 페이로드에 1200
- `testCyclingStrategy_HrLockBeforeT30_SendsHr` — elapsed=15, hr=160 → HR 모드 미확정, hr 그대로
- `testCyclingStrategy_HrLockAt30_WithHr_StaysHr` — 30초 이내 hr 한 번 잡힘 → 30초 시점 lock, 이후 hr 전송
- `testCyclingStrategy_HrLockAt30_NoHr_SwitchesAscent` — 30초 동안 hr 항상 null → 30초 시점 lock, 이후 totalAscent
- `testCyclingStrategy_HrComesBackAfterLockedAscent_StaysAscent` — totalAscent 락 후 hr 늦게 잡혀도 totalAscent 유지

**Strategy 선택 로직**

- `testDetectStrategy_RunningSport_ReturnsRunning`
- `testDetectStrategy_CyclingSport_ReturnsCycling`
- `testDetectStrategy_NullProfile_FallbackToRunning` (안전한 기본값)

### 코드 리뷰 체크리스트

PR diff 검토 시:

1. `RunningStrategy.mc`의 `buildPackets()` 본문이 기존 `compute()` 의 패킷 생성 블록과 라인별로 동등한지
2. `RunVisionIQView.mc` 변경이 strategy 초기화 + 디스패치 호출에 한정되는지 (기타 함수 변경 없음)
3. `ILensProtocol.mc` 무수정 확인
4. `manifest.xml` 무수정 확인 (Phase 1)
5. 사이클 전용 상태 변수가 `CyclingStrategy` 내부에만 존재, `RunVisionIQView` 또는 `RunningStrategy`에는 누출 없음

### 시뮬레이터 검증

Connect IQ Simulator (`run-simulator.bat`):

1. **러닝 액티비티**: 변경 전 빌드와 변경 후 빌드의 BLE 패킷 바이트 비교 (DFLogger 출력)
2. **사이클 액티비티 (HR 정상)**: speed/HR/altitude/distance 화면 표시 + BLE 패킷 ID/값 확인
3. **사이클 액티비티 (HR 시뮬레이션 0)**: 30초 후 `0x0B` 페이로드가 totalAscent로 전환되는지 확인
4. **액티비티 전환**: 러닝 종료 → 사이클 시작 시 새 액티비티에서 strategy 재선택되는지

### 실기기 검증

다음 표본 기기로 실 BLE 전송 + rLens 표시 확인:

- FR165 (BLE Central 표준, 일반 워치)
- Fenix 7 (멀티스포츠, sport 감지 정확도 검증)
- FR55 (slow write 경로, 사이클 모드에서도 정상 동작 확인)

각 기기에서 러닝 액티비티와 사이클 액티비티 각각 시작 → rLens 화면 값 검증.

---

## 6. 마이그레이션 및 호환성

- **기존 사용자**: 러닝만 사용하던 사용자는 강제로 어떤 변화도 경험하지 않음. sport != CYCLING이면 기존과 동일한 RunningStrategy 분기.
- **rLens 펌웨어**: 변경 불필요. 기존 메트릭 ID 그대로 사용하며 값의 의미만 워치 앱이 해석 변경.
- **Connect IQ Store 버전**: `manifest.xml` version 1.1.10 → 1.2.0 (마이너 버전 업, 새 기능)

---

## 7. 추후 작업 (Phase 2 이후)

1. **Edge 시리즈 지원**: manifest.xml에 Edge 530/540/830/840/1030/1030plus/1040/1050/explore2 추가. Edge는 핸들바 거치형이므로 사이클 액티비티만 사용 → CyclingStrategy 자동 선택. 별도 검증 PR.
2. **rLens 펌웨어 협업**: 사이클 모드 시 화면 단위/아이콘 동적 변경 검토 요청.
3. **애플워치 / 갤럭시워치 사이클 모드**: 각 repo (`runvision-watchos`, `runvision-wear`) 별도 설계. 워치 앱은 UI에서 모드 토글 필요 (자동감지 API 없음).

---

## 8. 미결 사항

- [ ] `getDisplayLabels()` 워치 화면 표시 — 사이클 모드 라벨을 "Speed/Alt" 형태로 바꿀지, 기존 라벨 그대로 둘지 (구현 단계에서 결정)
- [ ] `MetricContext` 의 정확한 필드 목록 — 구현하면서 strategy가 실제로 필요한 컨텍스트만 식별
- [ ] manifest.xml의 새 버전 번호 1.2.0 vs 1.1.11 — 변경 규모 결정 후 확정

---

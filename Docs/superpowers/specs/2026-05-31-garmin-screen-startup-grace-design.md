# Garmin 운동 시작 시 화면 그레이스(30초 강제 켜짐) — 설계

- 날짜: 2026-05-31
- 레포: `runvision-iq` (Monkey C DataField)
- 상태: 설계 합의됨 → 사용자 스펙 리뷰 대기
- 플랫폼: **Garmin 우선** (검증 후 Apple/Galaxy 이식 — 이번 스코프 아님)

## 목표
운동을 시작하면 글래스 화면 설정(달리기 5초/자전거 10초 등)이 무엇이든, **처음 30초간 화면을 연속으로 켜두어** 사용자가 "데이터가 제대로 뜨는지" 확인할 수 있게 한다. 30초 후에는 원래 설정값으로 복귀한다.

## 배경 — 화면 on/off는 누가 제어하나
- 화면 on/off는 글래스 펌웨어가 **2개 characteristic 값**으로 자율 실행한다:
  - `hibernation`(`f1491672-dd25-4322-b3de-20747ae657c4`): 화면 **켜짐 지속시간**(초). 이 시간이 지나면 잠든다.
  - `screenOff`(`09f8e7d6-c5b4-a392-8170-6f5e4d3c2ba1`): **재깨우기 주기**(초).
  - 둘 다 **Device Config Service**(`58211c97-482a-2808-2d3e-228405f1e749`) 소속.
- 평소엔 **폰 설정앱**(Flutter)이 이 값을 1회 write해 모드를 정한다. 폰이 즉시 반영됨은 **사용자 실기기 검증 완료**.
- **운동 중엔 폰이 아니라 워치가 글래스에 연결**된다. 따라서 화면 그레이스는 **운동을 시작하는 워치 앱**이 구현해야 한다.

## 핵심 설계 결정 — fail-safe `hibernation=30` (NOT 65535)
"항상켜짐(65535)"을 쓰면 **fail-dangerous**: 운동을 30초 내 종료하거나 그레이스 중 연결이 끊겨 복원 write가 누락되면 글래스 화면이 **영구히 켜진 채 방전**된다.

대신 **`hibernation=30`을 write**한다 → **fail-safe**:
- 그레이스 30초는 **펌웨어가 직접** 만든다(30초 뒤 펌웨어가 알아서 잠듦). 워치 타이머는 복원 시점 트리거용일 뿐, 화면 끄기를 책임지지 않는다.
- 복원이 실패해도 최악이 "`hibernation`이 원래값(예: 5) 대신 30으로 남음" — 약간 더 자주/길게 켜질 뿐 **방전 위험 없음**.
- **`screenOff`는 건드리지 않는다** → op이 절반(시작 read 1 + write 1, 복원 write 1).

> 단, "`hibernation`만으로(screenOff 미관여) 화면이 30초 연속 켜졌다 꺼지는가"는 펌웨어 동작이라 **검증 슬라이스(아래)로 먼저 확인**한다. 안 되면 `screenOff`도 30으로 함께 관리(시작 4 op).

## 트리거 시점 — `onTimerStart` AND 연결 준비
연결이 아니라 **운동 시작** 기준이어야 한다(연결을 페어링 단계에서 미리 맺으면 30초가 달리기 전에 소진됨). 두 조건이 모두 충족될 때 1회만 시작:
1. `onTimerStart()` 발생(`_workoutStarted = true`)
2. 연결 준비 완료(`_isConnected` + Exercise characteristic 확보 + 메트릭 write 정상 흐름)

start-before-connect / connect-before-start 양쪽 다 이 AND 조건으로 자연 처리된다.

> ⚠️ **선행조건 확인 필요(체크포인트):** Garmin 앱이 연결 직후 수행하는 critical 초기화(있다면)가 **모두 끝난 뒤에만** 화면 op을 낸다. (CLAUDE.md의 Universal Subscriptions init `[0x10,01/04/03]`은 폰=수신측 기준 — Garmin은 송신측이라 현재 코드에 해당 init이 없어 보이나, 구현 전 1회 확인.) 어떤 critical 초기화든 그것과 **인터리브 금지**.

## 상태 머신 (신규)
```
GRACE_IDLE
  └(trigger: onTimerStart && 연결준비)→ GRACE_READING
GRACE_READING:    requestRead(hibernationChar)
  └onCharacteristicRead→ 원래값 저장 → GRACE_OVERRIDING
GRACE_OVERRIDING: requestWrite(hibernationChar, 30)
  └onCharacteristicWrite→ GRACE_ACTIVE (30초 카운트 시작, 메트릭 재개)
GRACE_ACTIVE:     화면 ON(펌웨어 30초 유지), 메트릭 1/틱 정상
  └(t≈30s, 틱 1개 양보)→ GRACE_RESTORING
GRACE_RESTORING:  requestWrite(hibernationChar, 원래값)
  └onCharacteristicWrite→ GRACE_DONE (이후 그레이스 재실행 안 함)
```

- read/write는 **async 콜백**(`onCharacteristicRead`/`onCharacteristicWrite`), 한 번에 하나(`_isWriting` serialization 재사용).
- 화면 op은 **틱 스케줄러의 한 슬롯을 양보**받아 보낸다 → 어느 틱에도 GATT op은 항상 1개. 메트릭과 동시 전송(느린 기기 분실) 원천 차단.
- 30초 기준: `_elapsedSeconds` 또는 `System.getTimer()` 기반(활동 시작 전에도 동작하는 기존 패턴 재사용).

## 조기 종료/예외 시 복원
`onTimerStop` / `onTimerPause` / 연결 끊김(`onConnectedStateChanged`=disconnected)이 **그레이스 완료 전**에 발생하면, 오버라이드했던 경우 복원 write를 시도한다. 시도조차 못 해도 `hibernation=30` fail-safe가 받쳐준다.

## 사이드이펙트 방어 원칙 (불변식)
1. **화면 경로의 어떤 실패(read/write/프로파일 등록)도 "그레이스 없음"으로만 degrade** — 메트릭 스트리밍은 절대 건드리지 않는다.
2. critical 초기화 완료 후에만 화면 op 실행, 인터리브 금지.
3. fail-safe `hibernation=30`: 복원 누락의 최악이 방전 아닌 "약간 더 켜짐".
4. 그레이스는 **세션당 1회**(`GRACE_DONE` 이후 재실행 안 함).

## BLE 프로파일 변경
`getExerciseProfile()`에 **Device Config Service(`58211c97`) + characteristic 2개**(`hibernation`, `screenOff`)를 추가 등록. (`screenOff`는 검증 결과 hibernation-only로 충분하면 미등록 가능.)
- char 1→3 추가는 거의 확실히 Garmin 등록 한도 내. **실기기 1회 등록 성공 확인**이면 끝(프로파일은 connect 전 정적 구성이라 등록되면 안정적).
- 기존 Exercise char getter `tryGetServiceCharacteristic(service, char, nbRetry)` 재사용해 hibernation char 확보.

## 검증 슬라이스 (구현의 첫 단계 — 우회 아님)
`ble_tool`(`tools/rlens_ble_tool.py`)로 글래스에 직접 쏴서 **"어떤 값을 쓸지"를 확정**한다:
1. **동시성:** 메트릭이 흐르는 중 `hibernation` write가 충돌 없이 적용되고 메트릭이 안 끊기나?
2. **hibernation-only:** `hibernation=30`만(screenOff 미변경) 써도 화면이 **30초 연속 켜졌다 자동으로 꺼지나?** (안 되면 screenOff도 30 관리)
3. **OFF→ON:** 화면이 꺼진 상태에서 `hibernation=30` write 시 **즉시 켜지나?** 아니면 메트릭 write/별도 wake가 필요한가?
4. **op당 지연:** read/write 실측 latency(시작 지연 크기 산정용).

## 테스트/검증
- **컴파일:** 대표 기기 다수 테스트모드 빌드(`-d fr165` 등). 기존 Tests.mc에 상태 전이 단위 테스트 추가(틱 슬롯 양보 로직 등 순수 로직 부분).
- **실기기(게이트, fr165):** ① 운동 시작 → 30초 연속 켜짐 → 자동 복귀 ② 메트릭(HR/케이던스 등) 끊김·freeze 없음(a914985 회귀 감시) ③ 30초 내 조기 종료 시 화면이 영구히 안 켜져 있음(fail-safe) ④ 프로파일 등록 성공(연결 정상).
- **회귀:** 연결/페어링/재연결/메트릭 스트리밍 흐름 불변.

## 후속(이번 스코프 아님)
- Apple Watch(Swift)·Galaxy(Kotlin) 이식. 동일 fail-safe 설계 적용.
- 그레이스 시간(30초)·값을 설정 가능하게 할지(현재는 하드코딩).

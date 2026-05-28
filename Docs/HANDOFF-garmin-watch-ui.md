# Garmin 워치 UI 작업 핸드오프 (WSL 세션 → 맥 세션)

> 다른 머신(WSL)에서 진행하던 작업을 맥 세션이 이어받기 위한 노트.
> Claude 메모리는 머신별이라 맥 세션은 이 컨텍스트를 모름 → 이 문서가 인계서.

## ⛔ 2026-05-28 SUPERSEDED — BLE 전송 결론 정정 (아래 "전송 주기 정책" + fr55 디버깅 #3 폐기)

> **아래의 "글래스가 5초보다 짧게 hold → timeout → 0/frozen", "2초가 균형점", "저속 allowlist 1초 고정" 결론은 전부 틀렸음.** nRF52840 on-air 캡처를 직접 분석해 정정함. (이 문서를 인용한 코드리뷰가 "5초는 너무 느림" 회귀라고 오판하므로 명시.)

**진짜 근본원인 (캡처 확인):**
- fr55 5초 모드는 매 5초 **5개 메트릭을 ~1.6ms 무응답(0x52) burst**로 한꺼번에 송출. 느린 기기 컨트롤러가 burst를 못 삼켜 **HR/cad 가 글래스에 불규칙하게 15~20초 간격으로만 도달** → freeze. (캡처상 HR/cad 는 5초에 **실제 값으로 air 에 나감** — 송출 누락이 아니라 burst 과부하로 인한 불규칙 도달.)
- **글래스/펌웨어 timeout 아님**: PC 도구로 **규칙적 5초** 전송 시 글래스 HR/cad 정상 유지 → 글래스는 규칙적 5초를 견딤. 문제는 워치 burst 의 *불규칙성*이었지 5초라는 *주기*가 아니었음.
- write-type(0x52) 도 원인 아님 (1초·5초 둘 다 0x52, 1초만 동작).

**최종 수정 (페이싱, allowlist·기기판정 전부 폐기):**
- **burst 폐기 → 매 compute(1Hz) 1패킷씩** 전송(`MetricStrategy.buildTickPackets`). burst 과부하 자체가 사라짐 → 전 기기 동일 코드, 기기 판정 불필요.
- **러닝·사이클 동일**: 유효 메트릭 1개/tick 균등 회전 → 각 메트릭 ~(유효 메트릭 수)초(전부 유효 시 ~5초). *규칙적* 도달이라 글래스 정상. 배터리 = 기존 5초모드(1 write/초). burst 없음 = 전 기기 안전.
- **(시도 후 폐기) 사이클 2초 burst**: 사이클을 "시간 매 tick + 나머지 2개씩(각 2초)"로 했더니 **fr55 에서 dist 가 0.6km 에 freeze**. = tick당 3-burst 의 *마지막* 패킷(주로 dist)을 fr55 컨트롤러가 무응답(0x52) air 에서 드롭(워치 dist 는 증가하는데 글래스만 정지로 확인). → **burst 부활 = fr55 드롭 부활.** 그래서 사이클도 1패킷/tick 로 통일. (대가: 사이클 속도도 ~5초. 빠른 기기는 더 빠르게 가능하나 기기 판별이 불가해 통일.)
- **폐기된 접근**: ① 저속 allowlist(part-number 하드코딩, 유지보수 부담) ② backlog/stall 런타임 감지(no-response 드롭은 SW 에 안 보여 미발화) ③ 사이클 2초 burst(위). **느린 기기를 SW 로 신뢰성 있게 판별하는 방법 없음** → burst 안 쓰는 1패킷/tick 통일이 결론.

**검증:** fr55·fr165 **러닝** 실기기 정상. 사이클은 1패킷/tick 통일본으로 재확인 진행 중(2초 burst 본은 fr55 dist freeze 로 폐기).

**관련:** 부모 레포 `Docs/HANDOFF-ble-5sec-hr-cad-capture.md`(캡처 인계서), 캡처 파일 `Docs/garmin log/`·`fr55-5sec.pcapng`.

### 추가 수정 (전략 판정 + 세션 lifecycle) — 2026-05-28 같은 세션
캡처/배포 게이트 리뷰(Codex 2-track)에서 추가로 드러난 결함들을 수정:
- **전략 실시간 판정**: 과거 `_strategy`를 첫 compute 1회만 검출·영구 고정 → fr55 가 레이스로 **러닝에 잠겨** 사이클인데 0x07=페이스·0x0e=cadence(자전거 센서 없음→0) 전송 = 글래스에 페이스/고도0. (fr165 는 레이스를 이겨 가려졌던 기존 버그.) → `compute()` 가 **매 tick `Activity.getProfileInfo().sport` 로 재판정**, 클래스 변경 시에만 인스턴스 교체(HR락 상태 보존). drawMetricGrid 화면 판정과 동일 기준으로 정렬.
- **F1 HR락 분리**: `CyclingStrategy.updateHrLock` 이 `buildPackets`(전송 자격 `!_isWriting` 게이트 안) 에서만 실행돼 write 가 tick 을 물면 HR 관측 누락 위험. → `MetricStrategy.onComputeTick(hr, elapsed)` 추가(base no-op / Cycling=updateHrLock), `compute()` 가 **매 tick 게이트 밖**에서 호출. buildPackets 의 updateHrLock 도 유지(테스트 구동 + idempotent).
- **F2 세션 전략 리셋**: `onTimerReset()` 이 `_strategy`/사이클 HR락/`_computeCount` 미리셋 → 이전 라이드의 ascent/HR 락이 다음 세션 상속(인스턴스 재사용). → `onTimerReset` 에 `_strategy=null; _computeCount=0;` 추가(실시간 판정이 다음 compute 에 새 인스턴스 생성 → 락 재결정).
- **A 세션 write 정리**: `onTimerReset` 이 in-flight write/큐 미정리 → 리셋 중 콜백이 이전 세션 패킷을 새 세션에 전송. → `_writeQueue=[]; _isWriting=false;` 추가(disconnect 경로와 동일, 페이싱이라 큐≤1).
- **C 계약 정정**: `getTransmitIntervalSeconds`(5/2) 는 페이싱 후 **전송에 미사용(dead)** — 주석으로 명시(사이클 2초 burst 폐기 사유 포함).

**(보류) F3 — 세션 리셋 시 글래스 stale**: 리셋 후 valid-skip 으로 새 세션에서 영구 무효인 슬롯은 글래스가 이전 세션 값 유지(예: 새 세션 HR 없음). **표시 전용·자가교정(움직이면 덮어씀)·발동조건 좁음(앱 안 나가고 리셋·재시작)** → 배포 차단 아님. 수정(0 blanking)은 **burst 부활→fr55 재드롭** 등 사이드이펙트가 버그보다 커서 보류. 필요 시 *페이싱된 blanking*으로 별도 구현.

**배포 verdict (1.2.0):** freeze/사이클/lifecycle(전략판정·F1·F2·A) 수정 완료, C 정정. **F3 만 known-deferred.** fr55·fr165 러닝+사이클(속도=km/h·고도 정상) 실기기 확인됨. Tests.mc 는 패킷생성 강커버, 페이싱·전략판정·lifecycle 은 View 레벨이라 미테스트(하네스 부재).

---

## 🔧 2026-05-25 전송 주기 정책 최종 정리 (⛔ 위 2026-05-28 노트로 폐기됨 — 히스토리 보존용)
- **현재 정책**
  - 저속 allowlist 기기: 러닝/사이클 모두 `1초`
  - 그 외 기기: 러닝 `5초`, 사이클 `2초`
- **저속 allowlist 대상**
  - `fr45`
  - `garminswim2`
  - `instinct2s`
  - `fr55`
- **근거**
  - `fr165`: 러닝 `5초`에서도 정상 동작
  - `fr55`: 러닝 `1초` 정상, `2초`는 HR이 거의 멈춤, `3초`는 HR 업데이트 실패, `5초`는 HR/cadence 업데이트 실패
  - 따라서 저속군은 배터리보다 메트릭 생존성을 우선해 `1초` 고정이 안전
- **구현 메모**
  - `RunVisionIQView.mc`에서 `System.getDeviceSettings().partNumber` 기준 allowlist 판정
  - SDK `compiler.json`의 `partNumbers`를 기준으로 매핑
  - adaptive 탐색 로직은 폐기, 단순 allowlist 정책만 유지
- **다음 테스트 후보**
  - `venu` 계열은 아직 미분류. 기본값은 러닝 `5초`, 사이클 `2초`로 두고 실기기로 확인 후 allowlist 편입 여부 결정

## 🔧 2026-05-25 fr55 실기기 디버깅 (WSL 세션 — 맥 검토 요청)
fr55 실기기 테스트에서 3개 이슈를 순차 해결. **맥에서 시뮬레이터 + Tests.mc 전체 회귀 재확인 요망**(WSL은 sim·테스트 실행 불가). 아래 기록은 디버깅 히스토리로 보관하며, 최종 정책은 바로 위 섹션을 따른다.

1. **타겟 불일치 크래시 → 네이밍 B 전환** (`build.sh`, `run-simulator.bat`): `.prg`는 단일-기기 바이너리라 fr165용을 fr55에 올리면 크래시. 이제 `RunVisionIQ-<기기>.prg`로 기기별 출력(혼동 방지). 옛 단일 `RunVisionIQ.prg` 규칙 폐기.

2. **fr55 OOM 크래시(연결 중) → 디버그 로깅 제거** (`RunVisionIQView.mc`, −72줄): fr55 DataField 예산 **32KB**(fr165는 64KB, SDK 확인). 회귀 — 최근 그리드 기능이 footprint를 키워 32KB 천장 초과. 크래시 로그 `Out Of Memory Error` @ line 929(`System.println` 문자열연결)·440. **화면에 안 보이는 write-only 디버그 로깅**(`_bleDebugLogs`/`_txDebugLogs` 2×8 + addBleLog 32회 + addTxLog 5회 + println 12회) 전부 제거 → fr55 크래시 해소(실기기 확인). 코드 ~3KB 감소.
   - ⚠️ 남은 Step 2 후보(미적용): `_avgSpeedLabel`(503)·`_maxHrLabel`(518)이 매초 `.format()` 하는데 어디서도 안 읽힘(write-only, 기존 dead code). 더 줄여야 하면 제거.

3. ⛔ **(2026-05-28 폐기 — 위 SUPERSEDED 노트 참조. "근본원인=전송주기/글래스 timeout" 은 틀렸고 burst 과부하였음.)** 글래스 HR·cadence 0/frozen (페이스·거리 정상) → 러닝 전송 5→2초 (`RunningStrategy.mc` + `Tests.mc`): 회귀. ~~**근본원인 = 전송 주기**~~. v1.1.7(ef8b4e6, 마지막 동작 버전)을 실기기에 돌려보니 **정상** → 그 버전은 `if(_isConnected && char)` 로 **매 compute(1초) 전송**. 현재는 `_computeCount % transmitInterval(5) == 0` 으로 **5초마다**. **글래스는 HR·cadence(순간값)를 5초보다 짧게 hold → 5초 전송 시 사이에 timeout되어 0/frozen.** 시간·페이스·거리(누적/지속값)는 5초에도 글래스가 유지 → 그것만 정상이었음. 실기기로 임계값 측정: **5초=HR·cad 죽음, 3초=cadence 살고 HR 죽음(HR이 가장 짧게 hold), 2초=둘 다 정상.** → 러닝 주기 **2초**(`getTransmitIntervalSeconds` override). 배터리 1초의 1/2. fr55 실기기 검증 완료.
   - **곁가지로 배제됨(중요):** valid-skip(무조건 전송해도 동일), 그리드 렌더링(OFF해도 동일), write-type DEFAULT/무응답(v1.1.7도 DEFAULT인데 정상), prev-compute 캐시 — 전부 원인 아님. **순수하게 전송 빈도**였음.
   - 📌 **미규명**: 1→5초로 바꾼 정확한 커밋/시점은 특정 안 함(Strategy 리팩토링 c6fbac8 05-15 근처 추정). "왜 5초로 했나"는 모름 — 배터리 의도였을 듯. 핵심은 2초가 균형점.
   - 💡 맥 검토 포인트: 사이클(`CyclingStrategy`)은 이미 2초라 동일 안전. fr165는 5초로 재확인 안 했으나(빠른 라디오로 가려졌을 수) 2초 fix는 전 기기 공통 적용이라 무해.


## ✅ 완료 (origin/main에 push됨, `git pull`로 받음)
연결 후 워치 화면에 **메트릭 그리드(1-2-2)** 표시 기능 — commit `9d3777e` 기준.
- 러닝: `TIME` / `PACE`·`CAD` / `DIST`·`HR`
- 사이클: `TIME` / `SPEED`·`ALT` / `DIST`·`HR`  (사이클 판별 = `Activity.getProfileInfo().sport == SPORT_CYCLING`, BLE 무관)
- 값 `FONT_LARGE`, 라벨 `FONT_XTINY`, 여백 분리(구분선·연결점 없음 — 사용자 결정).
- **연결 전** → 상태화면(로고+상태+버전), **연결 후** → 그리드 (`_isConnected` 분기). 끊김 시 상태화면 복귀는 의도된 동작(가민은 자동 모드선택이라 연결화면이 Galaxy/Apple의 홈 역할).
- **fr165 실기기 검증 완료**: 러닝/사이클 라벨 전환, 겹침·클리핑·OOM 없음.

**코드 위치:**
- `source/RunVisionIQView.mc` — `onUpdate`(연결 분기), `drawStatusScreen`, `drawMetricGrid`, `drawCell`
- `source/MetricStrategy.mc` — `metricGridLayout(width,height,isRound)` 반응형 좌표 (행 0.14/0.36/0.58, inset 둥근 0.30 / 사각 0.25)
- `source/Tests.mc` — `testMetricGridLayout_*`, `testMetricPresent_*`

## ✅ #3 작은 기기 폰트 fit — 완료 (맥 sim 검증)
- **반응형 값 폰트**: `drawMetricGrid`이 행 간격에 `값+라벨+숨구멍(gap)`이 맞는 가장 큰 폰트(LARGE→MEDIUM→SMALL) 선택. 라벨은 `FONT_XTINY`(시스템 최소) 유지 + 라벨/다음 행 사이 `gap=labelH/2`로 구분.
- **가장 작은 기기만 RV**: `gridFitsScreen(width)` = `width≥170`. instinct2s(156)만 "RV", 나머지는 그리드.
- **instinct 보조창 대응**: `metricGridLayout`이 `width<200`(instinct 추정)이면 행을 아래로(timeY 0.20/0.45/0.70) → 상단 클리핑 + 우상단 보조창 충돌 회피. 그 외는 위로(0.14/0.36/0.58).
  - ⚠️ **함정(2회 실수)**: instinct은 `screenShape`를 ROUND로 보고하지 **않음**(`round=false`). 그래서 `isRound` 조건 쓰지 말 것 — **폭만으로** 판별. println(`dc=176x176 round=false`)로 확정. 회귀 테스트 `testMetricGridLayout_narrowDeviceRowsLower`로 잠금.
- **맥 sim 검증**: instinct2s(RV) / instinct2(낮은 그리드) / fr55·fr165(높은 그리드) / venusq2m(rect 그리드) 전부 확인. 42 테스트 통과.
- 참고: `venusq2m`(360×320)은 **직사각** — `metricGridLayout`의 `isRound=false`(rect inset) 경로가 실제로 쓰임.

## ⚠️ 함정 / 환경 노트 (꼭 읽을 것)
- **시뮬레이터는 맥 네이티브로.** WSL2/Hyper-V에선 monkeydo↔sim 연결이 구조적으로 깨짐(포트 42877/1234 + interop). Ubuntu 24.04 Linux SDK도 옛 libwebkit2gtk-4.0 부재로 막힘(CIQ 8.4.1 기준 미해결). → **맥/Windows 네이티브만 깨끗.**
- **빌드 산출물 네이밍 = `RunVisionIQ-<기기>.prg`** (2026-05-25 변경). `./build.sh fr165`→`bin/RunVisionIQ-fr165.prg`, `./build.sh fr55`→`bin/RunVisionIQ-fr55.prg`. **`.prg`는 단일-기기 바이너리**라 fr165용을 fr55에 올리면 크래시 → 기기별 파일을 공존시켜 타겟 혼동을 막음(옛 단일 `RunVisionIQ.prg` 규칙 폐기). `build.sh`가 표준 진입점(manifest 버전→`AppVersion.mc` 동기화, 증가 안 함). 전 기기 묶음은 `./build.sh iq`(=`RunVisionIQ-<ver>.iq`, 스토어용).
- **버전 정책: 빌드 ≠ 버전업.** 명시적 배포 시에만, 직전 배포 버전(`Docs/애플스토어/APP-STORE-SUBMISSION-LOG.md`) 확인 후 사용자 승인. versionCode는 스토어 요구로 확인 후 +1.
- **Codex 어드버서리얼 리뷰 종결:**
  - #2 **주석 stale** — ✅ 해결: `drawMetricGrid` 헤더 주석을 실제 배치 `PACE·CAD / DIST·HR`(사이클 `SPEED·ALT / DIST·HR`)로 갱신. (design.md 스펙은 옛 배치라 코드가 신뢰원 — 아래 참고.)
  - #3 = 위 작은기기 fit — ✅ 완료.
  - #1(끊김 시 상태화면)은 "정당"으로 종결(수정 안 함).
- 설계/계획: `Docs/superpowers/specs/2026-05-24-garmin-watch-metric-display-design.md`, `Docs/superpowers/plans/2026-05-24-garmin-watch-metric-display.md` (단 스펙은 옛 PACE·HR 배치 — 코드가 최신 기준).

## 맥 셋업 체크리스트
1. CIQ SDK Manager(맥) + 기기 이미지(fr55/fr165/instinct2s 등) 다운로드.
2. VS Code + Monkey C 확장 — `settings.json`의 SDK/key/jungle 경로를 **맥 경로**로 (현재 값은 Windows `C:\`·`D:\` stale).
3. `runvision-iq` repo `git pull`. `developer_key.der` 확보.
4. `Monkey C: Run App` → 기기 선택(fr55) → sim에서 그리드 확인 → #3 진행.

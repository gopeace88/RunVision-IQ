# Garmin 워치 UI 작업 핸드오프 (WSL 세션 → 맥 세션)

> 다른 머신(WSL)에서 진행하던 작업을 맥 세션이 이어받기 위한 노트.
> Claude 메모리는 머신별이라 맥 세션은 이 컨텍스트를 모름 → 이 문서가 인계서.

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
- **빌드 산출물 네이밍 = `RunVisionIQ.prg`** (버전/기기 접미사 금지 — 사용자 규칙). `build.sh`가 표준 진입점(manifest 버전→`AppVersion.mc` 동기화, 증가 안 함).
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

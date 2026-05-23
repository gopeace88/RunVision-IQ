# Garmin 워치 데이터필드 메트릭 표시 — 설계

- 날짜: 2026-05-24
- 레포: `runvision-iq` (Monkey C DataField)
- 상태: 설계 합의됨 → 사용자 스펙 리뷰 대기

## 목표
RunVision-IQ 데이터필드가 **BLE 연결 후** 워치 화면에 핵심 5개 메트릭을 그리드로 표시한다. (현재는 로고+상태+버전만.) 메트릭 값은 rLens 글래스로도 전송되지만, 워치에서도 확인 가능하게 한다. 글래스가 본체라는 제품 철학은 유지 — 워치 표시는 보조/안심용.

## 스코프
- **포함:** 현재 manifest 87개 기기(대부분 둥근 워치 + Instinct 계열) 대상 **반응형** 메트릭 표시. `screenShape=RECTANGLE` 분기를 넣어 **Edge-ready**하게 설계.
- **제외(후속 작업):** Edge **실제 지원**(manifest product ID 추가, 가로 직사각 레이아웃 튜닝, cycling-computer UX, 실기기 테스트). 총상승(ASCENT) 미사용.

## ⚠️ 위험/주의 — 큰 변화
- `onUpdate`(렌더 경로)를 수정한다. **직전에 OOM "IQ!" 크래시가 난 바로 그곳**이다.
- **메모리 불변식: 그리드는 텍스트(drawText)만. 비트맵·새 폰트 리소스 추가 금지.** 로고는 연결 전 상태화면에서만 쓰고 이미 캐시됨([[feedback_garmin_datafield_memory]]).
- 87개 기기 반응형 → 일부 기기에서 레이아웃 깨질 위험. 대표 기기 다수로 검증.
- **점진적·롤백 용이:** 연결 전 상태화면 로직은 건드리지 않고, 연결 후 그리드만 새로 추가. 문제 시 그리드만 제거하면 원복.

## 화면 상태 (2개, `_isConnected` 분기)
1. **연결 전** (INIT / SCANNING / PAIRING / CONN_ERR): 현재 화면(로고 + 상태 텍스트 + 버전) **그대로 유지** — 페어링 피드백 보존.
2. **연결됨**: 메트릭 그리드(1-2-2) + 작은 **초록** 연결점.

## 레이아웃: 1-2-2 그리드, 반응형
- 모든 위치를 `dc.getWidth()/getHeight()` **비율** 기반으로 계산(고정 픽셀 금지).
- `System.getDeviceSettings().screenShape` 분기:
  - `ROUND`/`SEMI_ROUND`: 좌우 컬럼을 폭 ~28% / ~72% 지점, 상하 inset 크게 → 둥근 베젤 클리핑 방지.
  - `RECTANGLE`(Edge-ready): inset 작게, 가로폭 더 활용.
- 행 구성: 상단 `TIME` / 중단 좌·우 / 하단 좌·우. 각 셀 = 값(큰 폰트) + 라벨(`FONT_XTINY` 회색, 값 아래).
- 폰트: 셀 크기에 맞춰 선택(`FONT_NUMBER_MILD/MEDIUM` 등), `dc.getFontHeight`로 겹침 방지(버전 위치 수정과 동일 기법).

```
        12:34          TIME
   5:30        152      (러닝) PACE / HR   |  (사이클) SPEED / HR
   170        2.45      (러닝) CAD  / DIST  |  (사이클) ALT   / DIST
```

## 메트릭 셋 (Strategy 분기 — 이미 존재)
- **러닝:** TIME, PACE, HR, CAD, DIST.
- **사이클:** TIME, SPEED(km/h), HR, **ALT(현재 고도 m)**, DIST. (PACE→SPEED, CAD→ALT.)
- 값 문자열은 `compute()`가 이미 갱신: `_timeLabel / _paceLabel / _speedLabel / _hrLabel / _cadenceLabel / _distanceLabel`.
  - **확인 필요:** 사이클 현재고도 표시 문자열이 멤버로 있는지. 없으면 compute()에 라벨 1개 추가(값은 이미 계산됨).

## 연결 표시
- 연결됨: 상단 TIME 근처 작은 **초록 점**.
- 끊김: 그리드는 유지(마지막 값 표시), 연결점만 숨김/흐리게(사용자는 초록만 지정 — 끊김 색은 구현 시 최소 처리).

## 구현 개요
- `onUpdate(dc)`: `_isConnected ? drawMetricGrid(dc) : drawStatusScreen(dc)`.
- `drawStatusScreen(dc)`: 현재 onUpdate의 로고+상태+버전 로직을 그대로 분리(동작 불변).
- `drawMetricGrid(dc)`: `screenShape` + `getWidth/Height`로 좌표 계산 → `_strategy`(러닝/사이클)로 메트릭 셋 분기 → 라벨 문자열 `drawText`. **비트맵 없음.**

## 테스트/검증 (큰 변화라 강화)
- **컴파일:** 대표 기기 다수 테스트모드 빌드(`-d fr165`, fenix 계열, instinct, venu 등).
- **시뮬레이터:** 둥근/Instinct/(가능 시 rectangle) 레이아웃 육안 확인.
- **실기기(게이트):** fr165 연결 → 그리드 표시, **OOM 크래시 없음**, 러닝·사이클 각 모드.
- **회귀:** 연결 전 상태화면·페어링·재연결 흐름 불변 확인.

## 후속(이번 스코프 아님)
- Edge 실제 지원: manifest product ID + 가로 레이아웃 + 실기기.
- Instinct(저해상도·제한 색상)가 현재 기기 중 최대 시험대 — 반응형으로 우선 대응, 안 되면 그 기기만 맞춤.

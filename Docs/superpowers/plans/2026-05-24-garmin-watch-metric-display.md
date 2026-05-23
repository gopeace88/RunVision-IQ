# Garmin 워치 데이터필드 메트릭 표시 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RunVision-IQ 데이터필드가 BLE 연결 후 워치 화면에 5개 메트릭(1-2-2 그리드)을 반응형으로 표시한다.

**Architecture:** onUpdate를 `drawStatusScreen`(연결 전, 기존 동작) / `drawMetricGrid`(연결 후, 신규)로 분기. 그리드 좌표는 순수 함수 `metricGridLayout(w,h,isRound)`로 계산(테스트 가능). 메트릭 값은 compute()가 이미 갱신하는 라벨 문자열을 drawText만 함 — **비트맵 0(OOM 재발 방지)**.

**Tech Stack:** Monkey C (Connect IQ), DataField, Toybox.Graphics/System/WatchUi. 빌드: `./build.sh` (WSL→powershell monkeyc). 테스트: `(:test)` 함수 (테스트모드 컴파일 검증 + 시뮬레이터 실행).

> ⚠️ 큰 변화 — 직전 OOM 크래시가 난 onUpdate를 만진다. 그리드는 텍스트만. 연결 전 화면은 불변(롤백 용이). 각 task 후 컴파일, 마지막에 실기기 게이트.

---

### Task 1: 사이클 현재고도 라벨 추가

**Files:**
- Modify: `source/RunVisionIQView.mc` (라벨 멤버 + compute 포맷 + reset)

- [ ] **Step 1: 라벨 멤버 추가** — `_paceLabel` 선언(53행 부근) 아래에:

```monkeyc
    private var _paceLabel as Lang.String = "--:--";
    private var _altitudeLabel as Lang.String = "---";  // 사이클 현재 고도(m) 표시용
```

- [ ] **Step 2: compute()에서 고도 포맷** — `var altitude = info != null && info has :altitude ? info.altitude : null;`(576행 부근) 바로 다음 줄에 추가. **글래스 전송값(`_metricValues.altitudeM = roundFloat(altitude)`, 643행, cadence 슬롯 0x0E로 전송)과 동일한 `roundFloat` 반올림을 써서 워치=글래스 숫자 일치**:

```monkeyc
        if (altitude != null) { _altitudeLabel = roundFloat(altitude).format("%d"); } else { _altitudeLabel = "---"; }
```
(Float 직접 `.format("%d")` 금지 — `roundFloat`가 Number 반환, 다른 라벨과 동일 패턴.)

- [ ] **Step 3: reset 시 초기화** — `_cadenceLabel = "---";`(269행, onTimerReset류) 부근에 추가:

```monkeyc
        _altitudeLabel = "---";
```

- [ ] **Step 4: 컴파일 검증**

Run: `./build.sh`
Expected: `[build] 완료.` exit 0 (BUILD SUCCESSFUL)

- [ ] **Step 5: 커밋**

```bash
git add source/RunVisionIQView.mc
git commit -m "feat(garmin/watch): 사이클 현재고도 라벨(_altitudeLabel) 추가"
```

---

### Task 2: 반응형 그리드 레이아웃 순수 함수 + 테스트 (TDD)

**Files:**
- Modify: `source/MetricStrategy.mc` (모듈 함수 추가)
- Test: `source/Tests.mc`

- [ ] **Step 1: 실패 테스트 작성** — `Tests.mc`의 `// === RunningStrategy regression tests ===` 앞에 추가:

```monkeyc
// === metricGridLayout: 반응형 그리드 좌표 ===
(:test)
function testMetricGridLayout_roundInsetsMoreThanRect(logger as Logger) as Boolean {
    var r = metricGridLayout(416, 416, true);
    var q = metricGridLayout(416, 416, false);
    // 둥근 화면은 좌우 컬럼을 더 안쪽으로(클리핑 방지) → round leftX > rect leftX
    return (r[:leftX] as Lang.Number) > (q[:leftX] as Lang.Number);
}

(:test)
function testMetricGridLayout_withinBounds(logger as Logger) as Boolean {
    var L = metricGridLayout(416, 416, true);
    var lx = L[:leftX] as Lang.Number;
    var rx = L[:rightX] as Lang.Number;
    var ty = L[:timeY] as Lang.Number;
    var r2 = L[:row2Y] as Lang.Number;
    return lx > 0 && rx < 416 && lx < rx && ty > 0 && r2 < 416;
}
```

- [ ] **Step 2: RED 확인 (테스트모드 컴파일 실패)**

Run: `powershell.exe -NoProfile -Command "& 'C:\Users\jinhee\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.4.0-2025-12-03-5122605dc\bin\monkeyc.bat' -t -o '$(wslpath -w "$(pwd)")\bin\test.prg' -f '$(wslpath -w "$(pwd)")\monkey.jungle' -y '$(wslpath -w "$(pwd)")\developer_key.der' -d fr165"`
Expected: FAIL — `Undefined symbol ':metricGridLayout'`

- [ ] **Step 3: 함수 구현** — `MetricStrategy.mc`의 `function metricPresent(...)` 위 또는 아래에 추가:

```monkeyc
//! 메트릭 그리드(1-2-2) 좌표를 화면 크기·형태 기반으로 계산(반응형). 픽셀 고정 금지.
//! isRound=true 면 좌우 컬럼을 더 안쪽으로 inset 해 둥근 베젤 클리핑을 막는다.
function metricGridLayout(width as Lang.Number, height as Lang.Number, isRound as Lang.Boolean) as Lang.Dictionary {
    var inset = isRound ? 0.30 : 0.25;
    return {
        :centerX => width / 2,
        :leftX  => (width * inset).toNumber(),
        :rightX => (width * (1.0 - inset)).toNumber(),
        :timeY  => (height * 0.20).toNumber(),
        :row1Y  => (height * 0.44).toNumber(),
        :row2Y  => (height * 0.66).toNumber()
    };
}
```

- [ ] **Step 4: GREEN 확인 (테스트모드 컴파일 성공)**

Run: (Step 2와 동일 명령)
Expected: `BUILD SUCCESSFUL`. (실제 PASS는 시뮬레이터 실행으로 확인 — 헤드리스 제약.)

- [ ] **Step 5: 커밋**

```bash
git add source/MetricStrategy.mc source/Tests.mc
git commit -m "feat(garmin/watch): 반응형 그리드 레이아웃 metricGridLayout + 테스트"
```

---

### Task 3: onUpdate → drawStatusScreen 분리 (동작 불변 리팩토링)

**Files:**
- Modify: `source/RunVisionIQView.mc` (onUpdate 본문을 함수로 추출)

- [ ] **Step 1: drawStatusScreen 추출** — 현재 `onUpdate(dc)`의 try 본문(clear/getWidth/Height/로고/상태/버전)을 새 private 함수로 옮기고, onUpdate는 호출만:

```monkeyc
    function onUpdate(dc as Graphics.Dc) as Void {
        try {
            drawStatusScreen(dc);
        } catch (ex) {
            try { dc.drawText(120, 50, Graphics.FONT_SMALL, "ERR", Graphics.TEXT_JUSTIFY_CENTER); } catch (ex2) {}
        }
    }

    //! 연결 전 화면: 로고 + 상태 + 버전 (기존 동작 그대로)
    private function drawStatusScreen(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var centerY = height / 2;
        if (_logoCache == null) {
            _logoCache = WatchUi.loadResource(Rez.Drawables.RunVisionLogo);
        }
        dc.drawBitmap(centerX - 88, centerY - 40, _logoCache);
        var statusText = _isConnected ? "Connected" : _scanStatus;
        var statusY = centerY + 10;
        dc.drawText(centerX, statusY, Graphics.FONT_SMALL, statusText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var versionY = statusY + dc.getFontHeight(Graphics.FONT_SMALL) + 4;
        dc.drawText(centerX, versionY, Graphics.FONT_XTINY, "v" + AppVersion.VALUE, Graphics.TEXT_JUSTIFY_CENTER);
    }
```

- [ ] **Step 2: 컴파일 검증**

Run: `./build.sh`
Expected: `[build] 완료.` exit 0

- [ ] **Step 3: 시뮬레이터 동작 불변 확인 (사용자)**

시뮬레이터 재로드 → 연결 전 화면이 리팩토링 전과 **동일**(로고+상태+버전)한지 육안 확인.

- [ ] **Step 4: 커밋**

```bash
git add source/RunVisionIQView.mc
git commit -m "refactor(garmin/watch): onUpdate 본문을 drawStatusScreen으로 분리 (동작 불변)"
```

---

### Task 4: drawMetricGrid + 연결 분기 + 초록 연결점

**Files:**
- Modify: `source/RunVisionIQView.mc` (onUpdate 분기 + drawMetricGrid/drawCell 추가)

- [ ] **Step 1: onUpdate를 연결 상태로 분기**

```monkeyc
    function onUpdate(dc as Graphics.Dc) as Void {
        try {
            if (_isConnected) {
                drawMetricGrid(dc);
            } else {
                drawStatusScreen(dc);
            }
        } catch (ex) {
            try { dc.drawText(120, 50, Graphics.FONT_SMALL, "ERR", Graphics.TEXT_JUSTIFY_CENTER); } catch (ex2) {}
        }
    }
```

- [ ] **Step 2: drawMetricGrid + drawCell 추가** — `drawStatusScreen` 아래에:

```monkeyc
    //! 연결 후 화면: 5개 메트릭 1-2-2 그리드 (반응형, 텍스트만 — 비트맵 없음)
    private function drawMetricGrid(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var shape = System.getDeviceSettings().screenShape;
        var isRound = (shape == System.SCREEN_SHAPE_ROUND) || (shape == System.SCREEN_SHAPE_SEMI_ROUND);
        var L = metricGridLayout(w, h, isRound);
        var isCycling = _strategy instanceof CyclingStrategy;

        // 초록 연결점 (상단)
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(L[:centerX] as Lang.Number, (h * 0.08).toNumber(), 5);

        // TIME (상단)
        drawCell(dc, L[:centerX] as Lang.Number, L[:timeY] as Lang.Number, _timeLabel, "TIME");
        // row1: 좌=PACE/SPEED, 우=HR
        drawCell(dc, L[:leftX] as Lang.Number, L[:row1Y] as Lang.Number, isCycling ? _speedLabel : _paceLabel, isCycling ? "SPEED" : "PACE");
        drawCell(dc, L[:rightX] as Lang.Number, L[:row1Y] as Lang.Number, _hrLabel, "HR");
        // row2: 좌=CAD/ALT, 우=DIST
        drawCell(dc, L[:leftX] as Lang.Number, L[:row2Y] as Lang.Number, isCycling ? _altitudeLabel : _cadenceLabel, isCycling ? "ALT" : "CAD");
        drawCell(dc, L[:rightX] as Lang.Number, L[:row2Y] as Lang.Number, _distanceLabel, "DIST");
    }

    //! 셀 1개: 값(큰 폰트) + 그 아래 라벨(작은 회색). x,y 는 값의 중앙 정렬 기준점.
    private function drawCell(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, value as Lang.String, label as Lang.String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_NUMBER_MILD, value, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + dc.getFontHeight(Graphics.FONT_NUMBER_MILD), Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }
```

- [ ] **Step 3: 컴파일 검증**

Run: `./build.sh`
Expected: `[build] 완료.` exit 0. (`instanceof CyclingStrategy`, `System.SCREEN_SHAPE_*`, `FONT_NUMBER_MILD` 컴파일 통과 확인.)

- [ ] **Step 4: 시뮬레이터 확인 (사용자)** — 시뮬레이터에서 BLE 연결 시뮬레이트(또는 `_isConnected` 강제) 시 그리드가 겹침 없이 표시되는지.

- [ ] **Step 5: 커밋**

```bash
git add source/RunVisionIQView.mc
git commit -m "feat(garmin/watch): 연결 후 메트릭 그리드(1-2-2) 표시 + 초록 연결점"
```

---

### Task 5: 다중 기기 컴파일 + 실기기 검증 (게이트)

**Files:** (코드 변경 없음 — 검증 전용)

- [ ] **Step 1: 대표 기기 테스트모드 컴파일** — 화면 형태 다양성 커버:

```bash
for d in fr165 fr955 fenix7 venu3 instinct2 instinct3amoled45mm; do
  echo "=== $d ==="
  powershell.exe -NoProfile -Command "& 'C:\Users\jinhee\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.4.0-2025-12-03-5122605dc\bin\monkeyc.bat' -o '$(wslpath -w "$(pwd)")\bin\RunVisionIQ.prg' -f '$(wslpath -w "$(pwd)")\monkey.jungle' -y '$(wslpath -w "$(pwd)")\developer_key.der' -d $d -w" 2>&1 | grep -E "BUILD|ERROR"
done
```
Expected: 각 기기 `BUILD SUCCESSFUL`. (Instinct 계열에서 FONT_NUMBER_MILD가 너무 크면 레이아웃 조정 필요 — 발견 시 Task 추가.)

- [ ] **Step 2: 실기기(fr165) 설치 + 러닝 모드** — 연결 → 그리드(TIME/PACE/HR/CAD/DIST) 겹침 없이 표시, **IQ! 크래시 없음**(메모리), 연결점 초록.

- [ ] **Step 3: 실기기 사이클 모드** — SPEED/ALT로 바뀌어 표시되는지.

- [ ] **Step 4: 회귀 확인** — 연결 전 상태화면(로고+상태+버전)·페어링·재연결 흐름 불변.

- [ ] **Step 5: 최종 릴리즈 빌드(원할 때, 배포 정책 따름)** — `./build.sh iq` (자동증가 아님, manifest 버전 사용). 배포는 별도 사용자 승인.

---

## 메모
- 사이클 vs 러닝 판별은 `_strategy instanceof CyclingStrategy` (이미 존재하는 클래스).
- 폰트: 값=`FONT_NUMBER_MILD`, 라벨=`FONT_XTINY`. 작은 화면(Instinct)에서 큰 number 폰트가 넘치면 Task 5 Step 1에서 드러남 → 그때 폰트/위치 조정 task 추가.
- 끊김 시: 그리드 유지(마지막 값), 연결점은 초록만 구현(끊김 색 처리는 후속 — 사용자 지정 범위 밖).

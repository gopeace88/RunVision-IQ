using Toybox.Lang;
using Toybox.Activity;

//! Base type for metric strategies (RunningStrategy, CyclingStrategy).
//! Enables static type checking on _strategy.buildPackets() dispatch.
//! Subclasses must implement: buildPackets(values as MetricValues) as Array<ByteArray>
class MetricStrategy {
    function initialize() {
    }

    //! BLE 전송 주기 (초). 기본 5초, 서브클래스가 오버라이드 가능.
    //! 사이클 모드는 빠른 속도 변화 → 2초.
    function getTransmitIntervalSeconds() as Lang.Number {
        return 5;
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        // Subclasses override. Default returns empty array.
        return [] as Lang.Array<Lang.ByteArray>;
    }
}

//! Per-compute metric values container.
//! 매 compute() 호출마다 새로 채워지며 strategy 에 전달된다.
//! 누적 상태(예: HR 30초 락) 는 strategy 가 자체 보유한다.
//!
//! *Valid 플래그: 해당 메트릭이 실제 센서값인지(true) 또는 fallback 0인지(false).
//! Strategy.buildPackets() 가 이 플래그를 보고 stale 0 패킷을 iLens 로 보내지 않는다.
//! 기본값 false = "안 보내는 게 안전" (재연결 직후 0 패킷이 last value 를 덮어쓰는 결함 방지).
class MetricValues {
    public var elapsedSeconds as Lang.Number = 0;
    public var distance as Lang.Number = 0;        // meters
    public var paceSeconds as Lang.Number = 0;     // running only (sec/km)
    public var speedKmh as Lang.Float = 0.0;       // cycling only (km/h, Float for decimal precision)
    public var hr as Lang.Number = 0;              // 0 if unavailable
    public var cadence as Lang.Number = 0;         // running only (spm)
    public var altitudeM as Lang.Number = 0;       // cycling only (meters)
    public var totalAscent as Lang.Number = 0;     // cycling only (meters)

    public var speedValid as Lang.Boolean = false;
    public var hrValid as Lang.Boolean = false;
    public var cadenceValid as Lang.Boolean = false;
    public var distanceValid as Lang.Boolean = false;
    public var altitudeValid as Lang.Boolean = false;
    public var totalAscentValid as Lang.Boolean = false;

    function initialize() {
    }

    //! 테스트 헬퍼: 모든 valid 플래그를 true 로. 기존 인코딩 회귀 테스트가 한 줄로 새 API 에 적응.
    function setAllValid() as Void {
        speedValid = true;
        hrValid = true;
        cadenceValid = true;
        distanceValid = true;
        altitudeValid = true;
        totalAscentValid = true;
    }
}

//! 메트릭 전송 가능 여부: 센서가 값을 제공하면(0 포함) true; null/미존재만 false.
//! 정지(실제 0)는 전송 → rLens 가 0 표시 + velocity 패킷 연속성 유지(끊김 후 펌웨어 latch 방지).
//! null(재연결/no-data)만 skip → 직전 유효값 보존(50844a5 의도). 과잉 `> 0` 조건 제거가 핵심:
//! 기존 `!= null && > 0` 은 "데이터 없음"과 "실제 0(정지)"을 한 덩어리로 묶어 정지까지 skip 했음.
function metricPresent(value as Lang.Number or Lang.Float or Null) as Lang.Boolean {
    return value != null;
}

//! 메트릭 그리드(1-2-2) 좌표를 화면 크기·형태 기반으로 계산(반응형). 픽셀 고정 금지.
//! isRound=true 면 좌우 컬럼을 더 안쪽으로 inset 해 둥근 베젤 클리핑을 막는다.
//! 행 간격 균등(0.20/0.45/0.70)로 깔끔한 세로 리듬. 값은 컬럼 중앙 정렬 기준점.
function metricGridLayout(width as Lang.Number, height as Lang.Number, isRound as Lang.Boolean) as Lang.Dictionary {
    var inset = isRound ? 0.30 : 0.25;
    return {
        :centerX => width / 2,
        :leftX  => (width * inset).toNumber(),
        :rightX => (width * (1.0 - inset)).toNumber(),
        :timeY  => (height * 0.14).toNumber(),
        :row1Y  => (height * 0.36).toNumber(),
        :row2Y  => (height * 0.58).toNumber()
    };
}

//! sport 정수값으로부터 strategy 선택. 테스트 가능한 진입점.
//! Activity.SPORT_CYCLING → CyclingStrategy
//! 그 외 (RUNNING/GENERIC/null/unknown) → RunningStrategy (안전한 기본값)
function detectStrategyForSport(sportValue as Lang.Number or Null) as MetricStrategy {
    if (sportValue != null && sportValue == Activity.SPORT_CYCLING) {
        return new CyclingStrategy();
    }
    return new RunningStrategy();
}

//! Activity.Info 로부터 strategy 선택. compute() 첫 호출에서 사용.
function detectStrategy(info as Activity.Info or Null) as MetricStrategy {
    if (info == null) {
        return new RunningStrategy();
    }
    var profile = Activity.getProfileInfo();
    var sportValue = (profile != null) ? profile.sport : null;
    return detectStrategyForSport(sportValue);
}

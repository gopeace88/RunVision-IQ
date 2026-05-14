using Toybox.Lang;
using Toybox.Activity;

//! Base type for metric strategies (RunningStrategy, CyclingStrategy).
//! Enables static type checking on _strategy.buildPackets() dispatch.
//! Subclasses must implement: buildPackets(values as MetricValues) as Array<ByteArray>
class MetricStrategy {
    function initialize() {
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        // Subclasses override. Default returns empty array.
        return [] as Lang.Array<Lang.ByteArray>;
    }
}

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

import Toybox.Test;
import Toybox.Lang;
using Toybox.Activity;

// RunVision-IQ Unit Tests
// TDD를 위한 테스트 모듈

(:test)
function testILensProtocolPaceEncoding(logger as Logger) as Boolean {
    // 페이스 인코딩 테스트: 5:30/km = 330초
    var paceSeconds = 330;
    var expectedMinutes = 5;
    var expectedSeconds = 30;

    var minutes = paceSeconds / 60;
    var seconds = paceSeconds % 60;

    logger.debug("Pace: " + minutes + ":" + seconds + "/km");

    return (minutes == expectedMinutes && seconds == expectedSeconds);
}

(:test)
function testILensProtocolSpeedConversion(logger as Logger) as Boolean {
    // 속도 변환 테스트: m/s -> km/h
    // 10 km/h = 2.778 m/s
    var speedMps = 2.778f;
    var expectedKmh = 10.0f;

    var speedKmh = speedMps * 3.6f;

    logger.debug("Speed: " + speedKmh + " km/h");

    // 오차 범위 0.1 이내
    var diff = (speedKmh - expectedKmh).abs();
    return (diff < 0.1f);
}

(:test)
function testILensProtocolDistanceConversion(logger as Logger) as Boolean {
    // 거리 변환 테스트: m -> km
    var distanceMeters = 5000.0f;
    var expectedKm = 5.0f;

    var distanceKm = distanceMeters / 1000.0f;

    logger.debug("Distance: " + distanceKm + " km");

    return (distanceKm == expectedKm);
}

(:test)
function testHeartRateZoneCalculation(logger as Logger) as Boolean {
    // 심박수 존 계산 테스트
    // Zone 2: 60-70% of max HR
    // Max HR (age 30) = 220 - 30 = 190
    var maxHr = 190;
    var currentHr = 133; // 70% of 190

    var hrPercent = (currentHr * 100) / maxHr;

    logger.debug("HR Zone: " + hrPercent + "% of max");

    // Zone 2 범위 내인지 확인
    return (hrPercent >= 60 && hrPercent <= 70);
}

(:test)
function testCadenceNormalization(logger as Logger) as Boolean {
    // 케이던스 정규화 테스트
    // Running cadence: typically 160-180 spm
    var rawCadence = 85; // 한쪽 발 기준
    var expectedSpm = 170; // 양발 기준

    var normalizedCadence = rawCadence * 2;

    logger.debug("Cadence: " + normalizedCadence + " spm");

    return (normalizedCadence == expectedSpm);
}

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

// === metricPresent: 정지 시 0 전송 회귀 가드 ===
// 회귀: valid 도출이 `!= null && > 0` 라서 정지(실제 0)까지 skip → rLens 직전값 고착.
// 수정 의도: 센서가 값을 주면(0 포함) 전송, null(no-data/재연결)만 skip(50844a5 보존).

(:test)
function testMetricPresent_zeroIsSendable(logger as Logger) as Boolean {
    // 정지 시 실제 0(Number)은 전송돼야 한다 (skip 아님).
    return metricPresent(0) == true;
}

(:test)
function testMetricPresent_zeroFloatIsSendable(logger as Logger) as Boolean {
    // 속도(Float) 0.0(정지)도 전송돼야 한다.
    return metricPresent(0.0) == true;
}

(:test)
function testMetricPresent_nullIsSkipped(logger as Logger) as Boolean {
    // 데이터 없음(null)만 skip → 직전값 보존 (50844a5 의도).
    return metricPresent(null) == false;
}

(:test)
function testMetricPresent_positiveIsSendable(logger as Logger) as Boolean {
    return metricPresent(170) == true;
}

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

(:test)
function testMetricGridLayout_narrowDeviceRowsLower(logger as Logger) as Boolean {
    // instinct 계열(폭<200, 보조창)은 행을 아래로(timeY 0.20), 그 외는 위로 펼침(timeY 0.10).
    // screenShape가 ROUND로 안 잡히는 instinct 때문에 isRound 무관하게 폭만으로 판별해야 함(회귀 방지).
    var narrow = metricGridLayout(176, 176, false);   // instinct2 (round=false 보고)
    var wide   = metricGridLayout(208, 208, true);    // fr55
    return (narrow[:timeY] as Lang.Number) == (176 * 0.20).toNumber()   // 35
        && (wide[:timeY]   as Lang.Number) == (208 * 0.10).toNumber()   // 20
        && (metricGridLayout(199, 199, true)[:timeY] as Lang.Number) == (199 * 0.20).toNumber()   // 경계: <200 → 낮게
        && (metricGridLayout(200, 200, false)[:timeY] as Lang.Number) == (200 * 0.10).toNumber(); // 경계: ≥200 → 높게(펼침)
}

(:test)
function testMetricGridLayout_tallPortraitSpreadsRows(logger as Logger) as Boolean {
    // 세로로 긴 화면(Edge1040 282x470, h/w=1.66>1.38)은 행을 더 펼침(timeY 0.08 / row2Y 0.72)
    // → 큰 숫자 폰트 수용 + 하단 채움. edge540(322/246=1.30)·venusq2m(360/320=1.125)는 미해당(0.10/0.67).
    var tall = metricGridLayout(282, 470, false);   // edge1040
    var mid  = metricGridLayout(246, 322, false);   // edge540 (비-세로형)
    return (tall[:timeY] as Lang.Number) == (470 * 0.08).toNumber()
        && (tall[:row2Y] as Lang.Number) == (470 * 0.72).toNumber()
        && (mid[:timeY]  as Lang.Number) == (322 * 0.10).toNumber()   // 일반 배치
        && (mid[:row2Y]  as Lang.Number) == (322 * 0.67).toNumber();
}

(:test)
function testGridFitsScreen_onlySmallestShowsRV(logger as Logger) as Boolean {
    // 가장 작은 기기(instinct2s 156)만 "RV", 나머지(instinct2 176↑·fr55 208↑)는 그리드. 경계 170.
    return gridFitsScreen(156) == false      // instinct2s → RV
        && gridFitsScreen(169) == false      // 경계 직전
        && gridFitsScreen(170) == true       // 경계
        && gridFitsScreen(176) == true       // instinct2 → 그리드
        && gridFitsScreen(208) == true       // fr55 → 그리드
        && gridFitsScreen(390) == true;      // fr165 → 그리드
}

// === RunningStrategy regression tests ===
// 이 테스트들은 기존 러닝 모드 패킷이 한 비트도 안 바뀌었음을 보증한다.

(:test)
function testRunningStrategy_SportTimePacket(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
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
    values.setAllValid();
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
    values.setAllValid();
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
    values.setAllValid();
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
    values.setAllValid();
    values.distance = 1234;
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // 0x06, 1234 = 0x4D2 = LE [0xD2, 0x04, 0x00, 0x00]
    var expected = [0x06, 0xD2, 0x04, 0x00, 0x00]b;
    return findAndCompare(packets, 0x06, expected, logger);
}

// === CyclingStrategy basic packet tests ===

(:test)
function testCyclingStrategy_VelocityIsSpeedKmh(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
    values.speedKmh = 25.0;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 0x07, 25 × 60 = 1500 = 0x5DC = LE [0xDC, 0x05, 0x00, 0x00]
    // rLens가 ÷60 후 "25" 표시.
    var expected = [0x07, 0xDC, 0x05, 0x00, 0x00]b;
    return findAndCompare(packets, 0x07, expected, logger);
}

(:test)
function testCyclingStrategy_VelocityPreservesDecimal(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
    values.speedKmh = 25.55;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 25.55 × 60 = 1533 (반올림) = 0x5FD = LE [0xFD, 0x05, 0x00, 0x00]
    // rLens가 ÷60 후 25.55 표시 → 소수점 보존 확인.
    var expected = [0x07, 0xFD, 0x05, 0x00, 0x00]b;
    return findAndCompare(packets, 0x07, expected, logger);
}

(:test)
function testCyclingStrategy_CadenceIsAltitudeM(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
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
    values.setAllValid();
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
    values.setAllValid();
    values.elapsedSeconds = 1800;  // 30:00
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    // 0x03, 1800 = 0x708 = LE [0x08, 0x07, 0x00, 0x00]
    var expected = [0x03, 0x08, 0x07, 0x00, 0x00]b;
    return findAndCompare(packets, 0x03, expected, logger);
}

// === CyclingStrategy HR lock state machine tests ===

(:test)
function testCyclingStrategy_HrLockBeforeT30_SendsHr(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
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
    values.setAllValid();

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
    values.setAllValid();
    values.hrValid = false;  // 시나리오: HR 스트랩 없음

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
    values.setAllValid();
    values.hrValid = false;  // 초기 30초간 HR 없음

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
    values.hrValid = true;
    values.totalAscent = 200;
    var packets = strategy.buildPackets(values);

    // 여전히 totalAscent 전송 (HR 무시)
    var expected = [0x0B, 0xC8, 0x00, 0x00, 0x00]b;  // 200
    return findAndCompare(packets, 0x0B, expected, logger);
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

// === Transmit interval tests ===

(:test)
function testRunningStrategy_TransmitInterval_Is5(logger as Logger) as Boolean {
    var strategy = new RunningStrategy();
    return strategy.getTransmitIntervalSeconds() == 5;
}

(:test)
function testCyclingStrategy_TransmitInterval_Is2(logger as Logger) as Boolean {
    var strategy = new CyclingStrategy();
    return strategy.getTransmitIntervalSeconds() == 2;
}

// === Packet-level skip tests (결함 A 수정: stale 0 패킷을 iLens 로 안 보냄) ===
// 활동 미시작 / GPS 미수신 / 센서 dropout 시 invalid 메트릭 패킷을 생성하지 않아
// iLens 가 직전 유효값을 유지하도록 한다.

(:test)
function testMetricValues_DefaultsAreInvalid(logger as Logger) as Boolean {
    var values = new MetricValues();
    logger.debug("MetricValues *Valid defaults");
    return !values.speedValid
        && !values.hrValid
        && !values.cadenceValid
        && !values.distanceValid
        && !values.altitudeValid
        && !values.totalAscentValid;
}

(:test)
function testMetricValues_SetAllValid_TogglesEverythingTrue(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
    return values.speedValid
        && values.hrValid
        && values.cadenceValid
        && values.distanceValid
        && values.altitudeValid
        && values.totalAscentValid;
}

(:test)
function testRunningStrategy_AllInvalid_OnlyTimerPacket(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.elapsedSeconds = 100;
    // 모든 *Valid = false (기본값)
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    logger.debug("Packet count when all invalid: " + packets.size());
    // timer 1개만 (garmin timer 는 항상 정확)
    return packets.size() == 1 && packets[0][0] == 0x03;
}

(:test)
function testRunningStrategy_OnlyHrValid_TimerAndHrOnly(logger as Logger) as Boolean {
    // 시나리오: 활동 중 GPS 미수신, HR 스트랩만 작동
    var values = new MetricValues();
    values.elapsedSeconds = 100;
    values.hr = 150;
    values.hrValid = true;
    // speed/cadence/distance 모두 invalid
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    logger.debug("Packet count when only HR valid: " + packets.size());
    return packets.size() == 2;
}

(:test)
function testRunningStrategy_AllValid_FivePackets(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.setAllValid();
    values.elapsedSeconds = 100;
    values.paceSeconds = 300;
    values.hr = 150;
    values.cadence = 180;
    values.distance = 1000;
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    logger.debug("Packet count when all valid: " + packets.size());
    return packets.size() == 5;
}

(:test)
function testCyclingStrategy_AllInvalid_OnlyTimerPacket(logger as Logger) as Boolean {
    var values = new MetricValues();
    values.elapsedSeconds = 100;
    var strategy = new CyclingStrategy();
    var packets = strategy.buildPackets(values);
    logger.debug("Cycling all-invalid packet count: " + packets.size());
    return packets.size() == 1 && packets[0][0] == 0x03;
}

(:test)
function testCyclingStrategy_HrModeButHrInvalid_NoHrSlotPacket(logger as Logger) as Boolean {
    // 시나리오: HR 모드 락 후 센서 dropout → HR slot 패킷 안 보냄
    var strategy = new CyclingStrategy();
    var values = new MetricValues();
    values.setAllValid();

    // 0~29초 hr 잡힘 → HR 모드 락
    values.hr = 150;
    for (var t = 0; t < 30; t++) {
        values.elapsedSeconds = t;
        strategy.buildPackets(values);
    }
    // 락 발동
    values.elapsedSeconds = 30;
    strategy.buildPackets(values);

    // 60초 — HR 센서 dropout
    values.elapsedSeconds = 60;
    values.hr = 0;
    values.hrValid = false;
    var packets = strategy.buildPackets(values);

    // HR slot (0x0B) 패킷이 없어야 함
    for (var i = 0; i < packets.size(); i++) {
        if (packets[i][0] == 0x0B) {
            logger.debug("HR slot packet leaked when hrValid=false");
            return false;
        }
    }
    return true;
}

(:test)
function testCyclingStrategy_AscentModeButAscentInvalid_NoHrSlotPacket(logger as Logger) as Boolean {
    // 시나리오: Ascent 모드 락 후 totalAscent invalid → HR slot 패킷 안 보냄
    var strategy = new CyclingStrategy();
    var values = new MetricValues();
    values.setAllValid();
    values.hrValid = false;  // HR 없는 시나리오

    // 0~29초 hr=0 → Ascent 모드 락
    values.hr = 0;
    for (var t = 0; t < 30; t++) {
        values.elapsedSeconds = t;
        strategy.buildPackets(values);
    }
    // 락 발동
    values.elapsedSeconds = 30;
    values.totalAscent = 500;
    strategy.buildPackets(values);

    // 60초 — totalAscent 센서 일시 무효 (예: 활동 재시작 직후)
    values.elapsedSeconds = 60;
    values.totalAscent = 0;
    values.totalAscentValid = false;
    var packets = strategy.buildPackets(values);

    for (var i = 0; i < packets.size(); i++) {
        if (packets[i][0] == 0x0B) {
            logger.debug("HR slot packet leaked when totalAscentValid=false");
            return false;
        }
    }
    return true;
}

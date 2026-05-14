import Toybox.Test;
import Toybox.Lang;

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

// === RunningStrategy regression tests ===
// 이 테스트들은 기존 러닝 모드 패킷이 한 비트도 안 바뀌었음을 보증한다.

(:test)
function testRunningStrategy_SportTimePacket(logger as Logger) as Boolean {
    var values = new MetricValues();
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
    values.distance = 1234;
    var strategy = new RunningStrategy();
    var packets = strategy.buildPackets(values);
    // 0x06, 1234 = 0x4D2 = LE [0xD2, 0x04, 0x00, 0x00]
    var expected = [0x06, 0xD2, 0x04, 0x00, 0x00]b;
    return findAndCompare(packets, 0x06, expected, logger);
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

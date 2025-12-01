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

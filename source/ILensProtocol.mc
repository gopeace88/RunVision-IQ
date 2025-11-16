using Toybox.Lang;
using Toybox.BluetoothLowEnergy;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.System;

//! iLens BLE Protocol Implementation
//! Based on iLens BLE V1.0.10 Specification
//!
//! Packet Structure: [Metric_ID(1 byte)] [Value(4 bytes, Little-Endian UINT32)]
//!
//! Exercise Data Service UUID: 4b329cf2-3816-498c-8453-ee8798502a08
//! Exercise Data Characteristic UUID: c259c1bd-18d3-c348-b88d-5447aea1b615
//! Device Configuration Service UUID: 58211c97-482a-2808-2d3e-228405f1e749
//! Current Time Characteristic UUID: 54ac7f82-eb87-aa4e-0154-a71d80471e6e
module ILensProtocol {

    // Service UUIDs
    const EXERCISE_SERVICE_UUID = BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08");
    const DEVICE_CONFIG_SERVICE_UUID = BluetoothLowEnergy.stringToUuid("58211c97-482a-2808-2d3e-228405f1e749");

    // Characteristic UUIDs
    const EXERCISE_DATA_UUID = BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615");
    const CURRENT_TIME_UUID = BluetoothLowEnergy.stringToUuid("54ac7f82-eb87-aa4e-0154-a71d80471e6e");

    // Metric IDs
    enum MetricID {
        RECORD_STATUS = 0x01,        // 0: Start, 1: Pause, 2: End
        HEAT_DISSIPATION = 0x02,     // kcal
        EXERCISE_TIME = 0x03,        // seconds
        TOTAL_TIME = 0x04,           // seconds
        PAUSE_TIME = 0x05,           // seconds
        DISTANCE = 0x06,             // meters ⭐
        VELOCITY = 0x07,             // km/h ⭐
        AVG_MOVEMENT_SPEED = 0x08,   // km/h
        AVG_SPEED = 0x09,            // km/h
        MAX_SPEED = 0x0A,            // km/h
        HEART_RATE = 0x0B,           // bpm ⭐
        AVG_HEART_RATE = 0x0C,       // bpm
        MAX_HEART_RATE = 0x0D,       // bpm
        CADENCE = 0x0E,              // spm ⭐
        MAX_CADENCE = 0x0F,          // spm
        AVG_CADENCE = 0x10,          // spm
        POWER = 0x11,                // watts
        MAX_POWER = 0x12,            // watts
        AVG_POWER = 0x13             // watts
    }

    //! Encode UINT32 value to 4-byte Little-Endian byte array
    //! Flutter 방식: value.round().clamp() → UINT32 인코딩
    //! @param value Number value (Float/Double/Integer)
    //! @return ByteArray 4-byte array [LSB, ..., MSB]
    function encodeUINT32(value as Lang.Number) as Lang.ByteArray {
        // ✅ CRITICAL: Float/Double을 정수로 변환 (Flutter Line 777 참조)
        // round() 후 clamp(0, 4294967295) 처리
        var intValue;

        // ⚠️ Monkey C에는 Math.round()가 없음!
        // Workaround: value + 0.5 후 toNumber() (반올림 효과)
        if (value >= 0) {
            intValue = (value + 0.5).toNumber();  // 양수 반올림
        } else {
            intValue = (value - 0.5).toNumber();  // 음수 반올림 (거의 없지만 안전)
        }

        // Clamp to safe range [0, 2147483647]
        // ⚠️ Monkey C는 32-bit SIGNED integer만 지원 (최대값 0x7FFFFFFF)
        if (intValue < 0) {
            intValue = 0;
        } else if (intValue > 2147483647) {
            intValue = 2147483647;  // Max signed int32
        }

        // ✅ 이제 intValue는 정수이므로 bitwise operation 안전
        var bytes = []b;
        bytes.add((intValue & 0xFF) as Lang.Number);              // Byte 0 (LSB)
        bytes.add(((intValue >> 8) & 0xFF) as Lang.Number);       // Byte 1
        bytes.add(((intValue >> 16) & 0xFF) as Lang.Number);      // Byte 2
        bytes.add(((intValue >> 24) & 0xFF) as Lang.Number);      // Byte 3 (MSB)

        return bytes;
    }

    //! Create iLens metric packet
    //! @param metricId Metric ID (see MetricID enum)
    //! @param value UINT32 value
    //! @return ByteArray 5-byte packet [ID(1), Value(4)]
    function createMetricPacket(metricId as Lang.Number, value as Lang.Number) as Lang.ByteArray {
        var packet = [metricId as Lang.Number]b;
        packet.addAll(encodeUINT32(value));
        return packet;
    }

    //! Create Velocity packet (km/h)
    //! @param speedKmh Speed in km/h (UINT32)
    //! @return ByteArray 5-byte packet
    function createVelocityPacket(speedKmh as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(VELOCITY, speedKmh);
    }

    //! Create Distance packet (meters)
    //! @param distanceMeters Distance in meters (UINT32)
    //! @return ByteArray 5-byte packet
    function createDistancePacket(distanceMeters as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(DISTANCE, distanceMeters);
    }

    //! Create Heart Rate packet (bpm)
    //! @param heartRateBpm Heart rate in bpm (UINT32)
    //! @return ByteArray 5-byte packet
    function createHeartRatePacket(heartRateBpm as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(HEART_RATE, heartRateBpm);
    }

    //! Create Cadence packet (spm)
    //! @param cadenceSpm Cadence in spm (UINT32)
    //! @return ByteArray 5-byte packet
    function createCadencePacket(cadenceSpm as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(CADENCE, cadenceSpm);
    }

    //! Create Power packet (watts)
    //! @param powerWatts Power in watts (UINT32)
    //! @return ByteArray 5-byte packet
    function createPowerPacket(powerWatts as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(POWER, powerWatts);
    }

    //! Create Record Status packet (Start/Pause/End)
    //! @param status 0: Start, 1: Pause, 2: End
    //! @return ByteArray 5-byte packet
    function createRecordStatusPacket(status as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(RECORD_STATUS, status);
    }

    //! Create Exercise Time packet (seconds)
    //! @param timeSeconds Time in seconds (UINT32)
    //! @return ByteArray 5-byte packet
    function createExerciseTimePacket(timeSeconds as Lang.Number) as Lang.ByteArray {
        return createMetricPacket(EXERCISE_TIME, timeSeconds);
    }

    //! Create Current Time packet (iLens BLE V1.0.10 Section 3.3)
    //!
    //! Packet Structure (10 bytes):
    //!   [0-1]  year (UINT16, little-endian)
    //!   [2]    month (UINT8, 1-12)
    //!   [3]    day (UINT8, 1-31)
    //!   [4]    hour (UINT8, 0-23, LOCAL time)
    //!   [5]    minute (UINT8, 0-59)
    //!   [6]    second (UINT8, 0-59)
    //!   [7]    dayOfWeek (UINT8, 1=Mon...7=Sun)
    //!   [8]    fraction256 (UINT8, 1/256 second, usually 0)
    //!   [9]    reason (UINT8, 0x02=External Reference, 0x03=Timezone Change)
    //!
    //! @param reason Adjust Reason code (0x02 or 0x03)
    //! @return ByteArray 10-byte packet
    function createCurrentTimePacket(reason as Lang.Number) as Lang.ByteArray {
        // Get current time
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);

        var bytes = []b;

        // Year (UINT16, little-endian)
        var year = info.year;
        bytes.add((year & 0xFF) as Lang.Number);          // Low byte
        bytes.add(((year >> 8) & 0xFF) as Lang.Number);   // High byte

        // Month (1-12)
        bytes.add(info.month as Lang.Number);

        // Day (1-31)
        bytes.add(info.day as Lang.Number);

        // Hour (0-23, LOCAL time)
        bytes.add(info.hour as Lang.Number);

        // Minute (0-59)
        bytes.add(info.min as Lang.Number);

        // Second (0-59)
        bytes.add(info.sec as Lang.Number);

        // DayOfWeek (1=Mon, 2=Tue, ..., 7=Sun)
        // Gregorian.info().day_of_week: 1=Sunday, 7=Saturday
        // iLens expects: 1=Monday, 7=Sunday
        // Conversion: (day_of_week + 5) % 7 + 1
        var garminDow = info.day_of_week;  // 1=Sun, 2=Mon, ..., 7=Sat
        var iLensDow = ((garminDow + 5) % 7) + 1;  // 1=Mon, ..., 7=Sun
        bytes.add(iLensDow as Lang.Number);

        // Fraction256 (1/256 second, set to 0)
        bytes.add(0x00 as Lang.Number);

        // Reason (0x02 or 0x03)
        bytes.add(reason as Lang.Number);

        return bytes;
    }

}

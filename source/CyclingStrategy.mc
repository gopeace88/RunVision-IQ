using Toybox.Lang;
using ILensProtocol;

//! Cycling mode metric strategy.
//! 슬롯 매핑:
//!   0x07: paceSeconds → speedKmh × 60 (rLens 가 ÷60 해서 표시 → 원래 km/h 복원, 소수점 보존)
//!   0x0E: cadence → altitudeM
//!   0x0B: hr OR totalAscent (30초 시점에 결정, 이후 영구 고정)
class CyclingStrategy extends MetricStrategy {

    private const HR_LOCK_THRESHOLD_SEC = 30;

    private var _hrEverSeen as Lang.Boolean = false;
    private var _slotLocked as Lang.Boolean = false;
    private var _useAscent as Lang.Boolean = false;

    function initialize() {
        MetricStrategy.initialize();
    }

    //! ⚠️ 페이싱 도입 후 전송에 미사용(dead): 사이클도 base 의 1패킷/tick 회전을 그대로 씀.
    //! 과거엔 사이클을 2초 burst 로 보냈으나, burst 의 마지막 패킷이 느린기기(FR55)에서 air 드롭돼
    //! dist freeze 가 발생 → burst 폐기·1패킷/tick 통일(각 메트릭 ~유효수초). 이 값은 참고용으로만 유지.
    function getTransmitIntervalSeconds() as Lang.Number {
        return 2;
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        updateHrLock(values.hr, values.elapsedSeconds);

        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));

        if (values.speedValid) {
            // rLens 0x07 슬롯은 값을 60으로 나눠 표시 (페이스 sec→min 변환용).
            // speedKmh × 60 보내면 rLens 가 ÷60 해도 원래 km/h 표시. 소수점도 보존됨.
            // 예: 25.55 km/h × 60 = 1533 → 1533/60 = 25.55 표시.
            var velocityScaled = (values.speedKmh * 60 + 0.5).toNumber();
            packets.add(ILensProtocol.createVelocityPacket(velocityScaled));
        }

        // HR 슬롯: 락 결과에 따라 hr 또는 totalAscent. 해당 메트릭이 valid 일 때만 전송.
        if (_useAscent) {
            if (values.totalAscentValid) {
                packets.add(ILensProtocol.createHeartRatePacket(values.totalAscent));
            }
        } else {
            if (values.hrValid) {
                packets.add(ILensProtocol.createHeartRatePacket(values.hr));
            }
        }

        // Cadence 슬롯 = altitudeM (사이클 모드 슬롯 재매핑)
        if (values.altitudeValid) {
            packets.add(ILensProtocol.createCadencePacket(values.altitudeM));
        }

        if (values.distanceValid) {
            packets.add(ILensProtocol.createDistancePacket(values.distance));
        }
        return packets;
    }

    // 페이싱: 사이클도 base 의 1패킷/tick 균등 회전을 그대로 사용(override 안 함).
    //   2개씩 분할(burst)은 느린 기기(FR55)에서 burst 마지막 패킷(주로 dist)이 air 에 드롭돼 freeze →
    //   burst 자체를 없애 모든 기기에서 안전. 대가: 각 메트릭 ~(유효 메트릭 수)초.
    //   (updateHrLock 은 base.buildTickPackets 가 buildPackets 를 호출하므로 계속 동작.)

    //! 매 compute 호출 — HR 30초 락을 BLE 전송 자격과 무관하게 갱신.
    //! (write 가 compute tick 을 물어 전송이 skip 돼도 HR 관측이 누락되지 않도록. buildPackets 안에서도
    //!  호출하지만 idempotent 라 중복 안전 — 테스트는 buildPackets 경로로 락을 구동.)
    function onComputeTick(hr as Lang.Number, elapsedSeconds as Lang.Number) as Void {
        updateHrLock(hr, elapsedSeconds);
    }

    //! 30초까지 hr 가 한 번이라도 유효(>0)했으면 HR 모드, 아니면 totalAscent 모드.
    //! 30초 시점에 단 한 번 결정 후 영구 고정. 이후 hr 가 늦게 들어와도 모드 안 바뀜.
    private function updateHrLock(hr as Lang.Number, elapsedSeconds as Lang.Number) as Void {
        if (hr != null && hr > 0) {
            _hrEverSeen = true;
        }
        if (!_slotLocked && elapsedSeconds >= HR_LOCK_THRESHOLD_SEC) {
            _useAscent = !_hrEverSeen;
            _slotLocked = true;
        }
    }
}

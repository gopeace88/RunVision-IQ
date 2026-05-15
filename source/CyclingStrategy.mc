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

    //! 사이클은 빠른 속도 변화 → 2초마다 BLE 전송.
    //! (러닝: 5초. 25km/h 사이클은 5초에 35m 이동하므로 더 빈번한 갱신이 필요.)
    function getTransmitIntervalSeconds() as Lang.Number {
        return 2;
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        updateHrLock(values.hr, values.elapsedSeconds);

        var hrSlotValue = _useAscent ? values.totalAscent : values.hr;

        // rLens 0x07 슬롯은 값을 60으로 나눠 표시 (페이스 sec→min 변환용).
        // speedKmh × 60 보내면 rLens 가 ÷60 해도 원래 km/h 표시. 소수점도 보존됨.
        // 예: 25.55 km/h × 60 = 1533 → 1533/60 = 25.55 표시.
        var velocityScaled = (values.speedKmh * 60 + 0.5).toNumber();

        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(velocityScaled));
        packets.add(ILensProtocol.createHeartRatePacket(hrSlotValue));
        packets.add(ILensProtocol.createCadencePacket(values.altitudeM));
        packets.add(ILensProtocol.createDistancePacket(values.distance));
        return packets;
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

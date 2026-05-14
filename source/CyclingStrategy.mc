using Toybox.Lang;
using ILensProtocol;

//! Cycling mode metric strategy.
//! 슬롯 매핑:
//!   0x07: paceSeconds → speedKmh
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

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        updateHrLock(values.hr, values.elapsedSeconds);

        var hrSlotValue = _useAscent ? values.totalAscent : values.hr;

        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(values.speedKmh));
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

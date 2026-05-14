using Toybox.Lang;
using ILensProtocol;

//! Cycling mode metric strategy.
//! 0x07: paceSeconds → speedKmh
//! 0x0E: cadence → altitudeM
//! 0x0B: hr (Task 4 에서 30초 락 로직 추가)
class CyclingStrategy {

    function initialize() {
    }

    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(values.speedKmh));
        packets.add(ILensProtocol.createHeartRatePacket(values.hr));
        packets.add(ILensProtocol.createCadencePacket(values.altitudeM));
        packets.add(ILensProtocol.createDistancePacket(values.distance));
        return packets;
    }
}

using Toybox.Lang;
using ILensProtocol;

//! Running mode metric strategy.
//! 기존 RunVisionIQView.compute() 의 패킷 생성 로직을 그대로 이전.
//! 변경 시 testRunningStrategy_* 테스트가 회귀를 잡아낸다.
class RunningStrategy {

    function initialize() {
    }

    //! 5개 메트릭 패킷을 순서대로 생성 (기존 line 608-612 와 동등)
    //! Sport Time → Velocity(pace) → Heart Rate → Cadence → Distance
    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        packets.add(ILensProtocol.createVelocityPacket(values.paceSeconds));
        packets.add(ILensProtocol.createHeartRatePacket(values.hr));
        packets.add(ILensProtocol.createCadencePacket(values.cadence));
        packets.add(ILensProtocol.createDistancePacket(values.distance));
        return packets;
    }
}

using Toybox.Lang;
using ILensProtocol;

//! Running mode metric strategy.
//! 기존 RunVisionIQView.compute() 의 패킷 생성 로직을 그대로 이전.
//! 변경 시 testRunningStrategy_* 테스트가 회귀를 잡아낸다.
class RunningStrategy extends MetricStrategy {

    function initialize() {
        MetricStrategy.initialize();
    }

    //! 메트릭 패킷을 순서대로 생성. valid 플래그가 false 인 메트릭은 패킷을 만들지 않는다.
    //! → iLens 가 stale 0 으로 갱신되지 않고 직전 유효값 유지.
    //! Sport Time 은 garmin timer 가 항상 정확하므로 무조건 전송.
    function buildPackets(values as MetricValues) as Lang.Array<Lang.ByteArray> {
        var packets = [] as Lang.Array<Lang.ByteArray>;
        packets.add(ILensProtocol.createExerciseTimePacket(values.elapsedSeconds));
        if (values.speedValid) {
            packets.add(ILensProtocol.createVelocityPacket(values.paceSeconds));
        }
        if (values.hrValid) {
            packets.add(ILensProtocol.createHeartRatePacket(values.hr));
        }
        if (values.cadenceValid) {
            packets.add(ILensProtocol.createCadencePacket(values.cadence));
        }
        if (values.distanceValid) {
            packets.add(ILensProtocol.createDistancePacket(values.distance));
        }
        return packets;
    }
}

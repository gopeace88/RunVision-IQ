using Toybox.Application;
using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.BluetoothLowEnergy;
using Toybox.Time;
using Toybox.Time.Gregorian;

using ILensBLE;
using ILensProtocol;
using DFLogger;

//! iLens BLE Profiles (ActiveLook 참조)
//! Exercise Data Service
const ILENS_EXERCISE_PROFILE = {
    :uuid => BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08"),
    :characteristics => [
        { :uuid => BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615") }  // Exercise Data
    ]
};

//! Device Configuration Service
const ILENS_CONFIG_PROFILE = {
    :uuid => BluetoothLowEnergy.stringToUuid("58211c97-482a-2808-2d3e-228405f1e749"),
    :characteristics => [
        { :uuid => BluetoothLowEnergy.stringToUuid("54ac7f82-eb87-aa4e-0154-a71d80471e6e") }   // Current Time
    ]
};

//! RunVision-IQ DataField - Garmin to iLens AR Bridge
//! Hybrid: Passive Connection 우선, 없으면 registerProfile() (ActiveLook 참조)
class RunVisionIQView extends WatchUi.DataField {

    // BleDelegate 메서드들을 직접 구현

    // iLens BLE instance (legacy, null 상태 유지)
    private var _ilens as ILensBLE.ILens or Null;

    // BLE Scanner 방식: 직접 관리
    private var _connectedDevice as BluetoothLowEnergy.Device or Null;
    private var _exerciseCharacteristic as BluetoothLowEnergy.Characteristic or Null;
    private var _currentTimeCharacteristic as BluetoothLowEnergy.Characteristic or Null;
    private var _deviceName as Lang.String = "UNKNOWN";  // Manufacturer Data에서 파싱한 이름
    private var _isConnected as Lang.Boolean = false;
    private var _scanStatus as Lang.String = "INIT";
    private var _devicesFound as Lang.Number = 0;
    private var _timeSyncDone as Lang.Boolean = false;  // Current Time 동기화 완료 플래그
    private var _timeCharRetryCount as Lang.Number = 0;  // Current Time Char 검색 재시도 횟수

    // Debug logs - BLE와 TX 분리 (각 4줄)
    private var _bleDebugLogs as Lang.Array<Lang.String> = ["", "", "", ""];
    private var _txDebugLogs as Lang.Array<Lang.String> = ["", "", "", ""];
    private var _bleLogIndex as Lang.Number = 0;
    private var _txLogIndex as Lang.Number = 0;

    // Display labels
    private var _speedLabel as Lang.String = "---";
    private var _hrLabel as Lang.String = "---";
    private var _cadenceLabel as Lang.String = "---";
    private var _distanceLabel as Lang.String = "0.00";
    private var _timeLabel as Lang.String = "0:00";
    private var _paceLabel as Lang.String = "--:--";

    // Statistics tracking
    private var _totalSpeed as Lang.Float = 0.0;
    private var _speedSamples as Lang.Number = 0;
    private var _avgSpeedLabel as Lang.String = "---";
    private var _maxHeartRate as Lang.Number = 0;
    private var _maxHrLabel as Lang.String = "---";

    // Profile registration tracking (ActiveLook 방식)
    private var _profileRegistered as Lang.Boolean = false;

    // ✅ 자체 경과 시간 카운터 (Flutter 방식)
    // DataField의 :timerTime이 제공되지 않으므로 자체 구현
    private var _elapsedSeconds as Lang.Number = 0;
    private var _connectionStartTime as Lang.Number = 0;  // 연결 시작 시간 (Service Discovery 대기용)

    // Write Queue (Flutter 방식: 1초마다 모든 메트릭 순차 전송)
    // iLens는 WRITE_WITH_RESPONSE만 지원 → 순차 전송 필요
    private var _writeQueue as Lang.Array<Lang.ByteArray> = [] as Lang.Array<Lang.ByteArray>;
    private var _isWriting as Lang.Boolean = false;  // Write 진행 중 플래그

    //! Constructor
    function initialize() {
        DataField.initialize();

        // BLE Delegate 설정 (별도 클래스 필요 - DataField는 BleDelegate 상속 불가)
        try {
            var delegate = new $.RunVisionBleDelegate(self);
            BluetoothLowEnergy.setDelegate(delegate);
            _scanStatus = "INIT_OK";
            addBleLog("init:ok");
            addBleLog("BLE:ready");
        } catch (ex) {
            _scanStatus = "INIT_ERR";
            addBleLog("init:error");
        }
    }

    //! Check for already paired devices (Passive Connection)
    //! 없으면 registerProfile() 호출 (ActiveLook 방식)
    private function checkPairedDevices() as Void {
        try {
            var pairedDevices = BluetoothLowEnergy.getPairedDevices();
            var device = pairedDevices.next() as BluetoothLowEnergy.Device;

            if (device != null) {
                // ✅ Passive Connection 존재 (ActiveLook 방식)
                addBleLog("paired:found");
                System.println("Passive connection exist");

                _connectedDevice = device;
                _profileRegistered = true;  // ← Profile 등록됨으로 표시 (스캔 불필요)
                _isConnected = false;  // ← 아직 연결 안 됨! onConnectedStateChanged() 대기
                _scanStatus = "PASSIVE";
                addBleLog("passive:wait");
                // Garmin이 자동으로 연결 시도 → onConnectedStateChanged() 콜백 대기
            } else {
                // Passive Connection 없음 → Active Pairing 시작
                addBleLog("no:paired");
                addBleLog("prof:reg");

                // registerProfile() 호출 (ActiveLook 방식)
                // Exercise Service만 등록 (Device Config Service는 연결 후 직접 찾음)
                try {
                    BluetoothLowEnergy.registerProfile(ILENS_EXERCISE_PROFILE);
                    _scanStatus = "PROF_REG";
                    addBleLog("prof:wait");
                } catch (ex) {
                    addBleLog("prof:err");
                    _scanStatus = "PROF_ERR";
                }
            }
        } catch (ex) {
            addBleLog("paired:err");
            _scanStatus = "PAIR_ERR";
        }
    }

    //! Add BLE debug log (최대 4줄, 순환)
    private function addBleLog(msg as Lang.String) as Void {
        _bleDebugLogs[_bleLogIndex] = msg;
        _bleLogIndex = (_bleLogIndex + 1) % 4;
        try {
            WatchUi.requestUpdate();
        } catch (e) {
            // UI가 아직 준비되지 않았을 수 있음
        }
    }

    //! Add TX debug log (최대 4줄, 순환)
    private function addTxLog(msg as Lang.String) as Void {
        _txDebugLogs[_txLogIndex] = msg;
        _txLogIndex = (_txLogIndex + 1) % 4;
        try {
            WatchUi.requestUpdate();
        } catch (e) {
            // UI가 아직 준비되지 않았을 수 있음
        }
    }

    //! Called when activity is started
    function onTimerStart() as Void {
        // 파일 로그 초기화
        DFLogger.reset();
        DFLogger.log("=== Activity Started ===");

        addBleLog("timer:start");

        // Passive Connection: 페어링된 기기 확인
        if (!_isConnected) {
            checkPairedDevices();
        }

        WatchUi.requestUpdate();
    }

    //! Called when activity is stopped
    function onTimerStop() as Void {
        // Stop scanning (BLE Scanner 방식)
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        addBleLog("timer:stop");
    }

    //! Called when activity is paused
    function onTimerPause() as Void {
        // Timer paused
    }

    //! Called when activity is resumed
    function onTimerResume() as Void {
        // Timer resumed
    }

    //! Called when lap button is pressed
    function onTimerLap() as Void {
        // Lap recorded
    }

    //! Called when activity is reset
    function onTimerReset() as Void {
        // Reset statistics
        _totalSpeed = 0.0;
        _speedSamples = 0;
        _maxHeartRate = 0;
        _avgSpeedLabel = "---";
        _maxHrLabel = "---";
        _paceLabel = "--:--";
        _distanceLabel = "0.00";
        _timeLabel = "0:00";
        _speedLabel = "---";
        _hrLabel = "---";
        _cadenceLabel = "---";
        _devicesFound = 0;
        _elapsedSeconds = 0;  // ✅ 경과 시간 초기화
    }

    //! Called each second to compute and display values (DataField)
    //! @param info Activity.Info object
    function compute(info as Activity.Info) as Void {
        // ✅ Lazy Loading: Characteristic 필요할 때 획득 (ActiveLook 방식)
        if (_isConnected && _connectedDevice != null && _exerciseCharacteristic == null) {
            try {
                _exerciseCharacteristic = tryGetServiceCharacteristic(
                    ILensProtocol.EXERCISE_SERVICE_UUID,
                    ILensProtocol.EXERCISE_DATA_UUID,
                    5  // ← 5번 재시도
                );
                addBleLog("char:ok");
                _scanStatus = "READY";
                DFLogger.logBle("CHAR_FOUND", "Exercise Data Characteristic discovered");
            } catch (ex) {
                // 다음 compute에서 재시도
                addBleLog("char:retry");
            }
        }

        // ✅ Current Time Characteristic 획득 (다른 Service에 있음!)
        // Flutter 방식: 연결 후 2초 대기 (Service Discovery 완료)
        var timeSinceConnection = _elapsedSeconds - _connectionStartTime;
        if (_isConnected && _connectedDevice != null && _exerciseCharacteristic != null &&
            _currentTimeCharacteristic == null && timeSinceConnection >= 2 && _timeCharRetryCount < 5) {

            _timeCharRetryCount++;
            DFLogger.logBle("TIME_CHAR_SEARCH", "Searching Current Time Characteristic (retry=" + _timeCharRetryCount + ")");

            try {
                _currentTimeCharacteristic = tryGetServiceCharacteristic(
                    ILensProtocol.DEVICE_CONFIG_SERVICE_UUID,
                    ILensProtocol.CURRENT_TIME_UUID,
                    5  // ← 5번 재시도
                );
                addBleLog("time:ok");
                DFLogger.logBle("TIME_CHAR_FOUND", "Current Time Characteristic discovered");

                // ✅ CRITICAL: Single-Stage Time Sync (Flutter 방식)
                // reason=0x03 (RTC sync)만 전송
                // reason=0x02 (UI update)는 건너뜀 (부팅 속도 향상)
                _timeSyncDone = false;
                try {
                    var timePacket = ILensProtocol.createCurrentTimePacket(0x03);
                    _currentTimeCharacteristic.requestWrite(timePacket, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
                    addBleLog("time:rtc");
                    DFLogger.logBle("TIME_SYNC", "Sending RTC sync (reason=0x03)");
                } catch (ex2) {
                    addBleLog("time:fail");
                    DFLogger.logError("TIME_SYNC", "Write failed: " + ex2.getErrorMessage());
                }
            } catch (ex) {
                // 최대 5회까지만 재시도
                if (_timeCharRetryCount >= 5) {
                    addBleLog("time:skip");
                    DFLogger.logError("TIME_CHAR_SEARCH", "Max retries (5) reached, skipping RTC sync");
                } else {
                    addBleLog("time:retry");
                    DFLogger.logError("TIME_CHAR_SEARCH", "Failed (retry=" + _timeCharRetryCount + "): " + ex.getErrorMessage());
                }
            }
        }

        // ========== 데이터 수집 (라벨 업데이트) ==========
        // ActiveLook 패턴: has 체크 + false 체크

        // Get current speed (m/s -> km/h)
        var speedMs = info != null && info has :currentSpeed ? info.currentSpeed : null;
        var speedKmh = 0;
        var paceSeconds = 0;  // ← Pace를 초 단위로 저장 (iLens 전송용)
        var speedValid = speedMs != null && speedMs > 0;

        if (speedValid) {
            speedKmh = ((speedMs * 3.6) + 0.5).toNumber();  // ✅ 반올림
            _speedLabel = speedKmh.format("%d");

            // Calculate pace (min/km) - 러너들은 Pace에 익숙
            var paceMinPerKm = 60.0 / (speedMs * 3.6);
            var paceMin = paceMinPerKm.toNumber();
            var paceSec = ((paceMinPerKm - paceMin) * 60).toNumber();
            _paceLabel = paceMin.format("%d") + ":" + paceSec.format("%02d");

            // iLens 전송용: Pace를 분.초 형식으로 인코딩 (예: 5:50 → 550)
            // 분*100 + 초 = iLens는 100으로 나누면 5.50으로 표시
            paceSeconds = paceMin * 100 + paceSec;

            // Update average speed
            _totalSpeed += speedMs * 3.6;
            _speedSamples++;
            var avgSpeed = (_totalSpeed / _speedSamples).toNumber();
            _avgSpeedLabel = avgSpeed.format("%d");
        } else {
            _speedLabel = "0";
            _paceLabel = "--:--";
        }

        // Get current heart rate (ActiveLook 패턴)
        var hr = info != null && info has :currentHeartRate ? info.currentHeartRate : null;
        var hrValid = hr != null && hr > 0;
        if (hrValid) {
            _hrLabel = hr.format("%d");

            // Track max heart rate
            if (hr > _maxHeartRate) {
                _maxHeartRate = hr;
                _maxHrLabel = hr.format("%d");
            }
        } else {
            _hrLabel = "---";
            hr = 0;
        }

        // Get current cadence (ActiveLook 패턴)
        var cadence = info != null && info has :currentCadence ? info.currentCadence : null;
        var cadenceValid = cadence != null && cadence > 0;
        if (cadenceValid) {
            _cadenceLabel = cadence.format("%d");
        } else {
            _cadenceLabel = "---";
            cadence = 0;
        }

        // Get current power (ActiveLook 패턴)
        var power = info != null && info has :currentPower ? info.currentPower : null;
        var powerValid = power != null && power > 0;
        if (!powerValid) {
            power = 0;  // Power Meter 없으면 0 전송
        }

        // Get elapsed distance (meters) (ActiveLook 패턴)
        var distance = info != null && info has :elapsedDistance ? info.elapsedDistance : null;
        var distanceValid = distance != null && distance > 0;
        if (distanceValid) {
            var distanceKm = distance / 1000.0;
            _distanceLabel = distanceKm.format("%.2f");
        } else {
            _distanceLabel = "0.00";
            distance = 0;
        }

        // ✅ 자체 경과 시간 카운터 (Flutter 방식)
        // DataField의 compute()는 1초마다 호출됨 → 매 호출마다 +1
        _elapsedSeconds += 1;
        var minutes = _elapsedSeconds / 60;
        var secs = _elapsedSeconds % 60;
        _timeLabel = minutes.format("%d") + ":" + secs.format("%02d");

        // ========== iLens 전송: Queue 방식 (Flutter와 동일) ==========
        // 1초마다 모든 메트릭을 queue에 추가 → 순차 전송
        // iLens는 WRITE_WITH_RESPONSE만 지원 → onCharacteristicWrite() callback에서 다음 패킷 전송
        if (_isConnected && _exerciseCharacteristic != null) {
            try {
                // 1. Write 진행 중이 아닐 때만 queue 초기화
                if (!_isWriting) {
                    _writeQueue = [] as Lang.Array<Lang.ByteArray>;

                    // 2. 모든 메트릭을 queue에 추가 (0이어도 전송 - iLens 초기화)
                    // ✅ 2-Stage Time Strategy (Flutter 방식):
                    //    1) 연결 시: RTC 동기화 (Current Time Characteristic) → 절대 시간 설정
                    //    2) 운동 중: Exercise Time 전송 (Exercise Data Characteristic) → 경과 시간 표시
                    // ✅ VELOCITY 필드: Pace를 분.초 형식으로 전송 (러너들은 Pace에 익숙)
                    //    - Garmin: Pace 5:50 → 550 전송 (분*100 + 초)
                    //    - iLens: 550 ÷ 100 = 5.50 표시
                    _writeQueue.add(ILensProtocol.createVelocityPacket(paceSeconds));
                    _writeQueue.add(ILensProtocol.createHeartRatePacket(hr));
                    _writeQueue.add(ILensProtocol.createCadencePacket(cadence));
                    _writeQueue.add(ILensProtocol.createPowerPacket(power));  // ← Power (Power Meter 필요)
                    _writeQueue.add(ILensProtocol.createDistancePacket(distance != null ? distance : 0));  // ✅ Float 그대로 → encodeUINT32에서 반올림
                    _writeQueue.add(ILensProtocol.createExerciseTimePacket(_elapsedSeconds));  // ← 운동 경과 시간

                    DFLogger.log("[TX] QUEUE: pace=" + paceSeconds + "(÷100=" + (paceSeconds/100.0).format("%.2f") + ") hr=" + hr + " cad=" + cadence + " pwr=" + power + " dist=" + (distance != null ? distance.toNumber() : 0) + " time=" + _elapsedSeconds);
                    addTxLog("q:" + _writeQueue.size());  // 화면 로그: queue 크기

                    // 3. Queue 전송 시작 (첫 패킷만 전송, 나머지는 callback에서 처리)
                    processWriteQueue();
                }
            } catch (ex) {
                addTxLog("q:err");
                DFLogger.logError("QUEUE", "Queue error: " + ex.getErrorMessage());
            }
        }
    }

    //! Draw the data field
    //! @param dc Device context
    function onUpdate(dc as Graphics.Dc) as Void {
        // Set background color
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        // Set text color
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        try {
            // Get dimensions
            var width = dc.getWidth();
            var height = dc.getHeight();
            var centerX = width / 2;
            var centerY = height / 2;

            // ✅ 디버그 로그 우선 - 시간/날짜 표시 제거
            // CURRENT TIME DEBUG는 DFLogger로 확인 가능

            var y = 5;  // 화면 최상단부터 시작

            // BLE status
            var statusText = _isConnected ? "iLens:OK" : "SCAN:" + _scanStatus;
            dc.drawText(centerX, y, Graphics.FONT_XTINY, statusText, Graphics.TEXT_JUSTIFY_CENTER);
            y += 20;

            // BLE Debug Logs (4줄)
            dc.drawText(centerX, y, Graphics.FONT_XTINY, "[BLE]", Graphics.TEXT_JUSTIFY_CENTER);
            y += 15;
            for (var i = 0; i < 4; i++) {
                if (_bleDebugLogs[i] != null && !_bleDebugLogs[i].equals("")) {
                    dc.drawText(centerX, y, Graphics.FONT_XTINY, _bleDebugLogs[i], Graphics.TEXT_JUSTIFY_CENTER);
                }
                y += 15;
            }

            // TX Debug Logs (4줄)
            dc.drawText(centerX, y, Graphics.FONT_XTINY, "[TX]", Graphics.TEXT_JUSTIFY_CENTER);
            y += 15;
            for (var i = 0; i < 4; i++) {
                if (_txDebugLogs[i] != null && !_txDebugLogs[i].equals("")) {
                    dc.drawText(centerX, y, Graphics.FONT_XTINY, _txDebugLogs[i], Graphics.TEXT_JUSTIFY_CENTER);
                }
                y += 15;
            }
            y += 10;

            // Speed and Pace
            dc.drawText(centerX - 50, y, Graphics.FONT_XTINY, "Spd", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX - 50, y + 32, Graphics.FONT_TINY, _speedLabel, Graphics.TEXT_JUSTIFY_CENTER);

            dc.drawText(centerX + 50, y, Graphics.FONT_XTINY, "Pace", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX + 50, y + 32, Graphics.FONT_TINY, _paceLabel, Graphics.TEXT_JUSTIFY_CENTER);
            y += 60;

            // Heart Rate and Cadence
            dc.drawText(centerX - 50, y, Graphics.FONT_XTINY, "HR", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX - 50, y + 32, Graphics.FONT_TINY, _hrLabel, Graphics.TEXT_JUSTIFY_CENTER);

            dc.drawText(centerX + 50, y, Graphics.FONT_XTINY, "Cad", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX + 50, y + 32, Graphics.FONT_TINY, _cadenceLabel, Graphics.TEXT_JUSTIFY_CENTER);
            y += 60;

            // Distance and Time
            dc.drawText(centerX - 50, y, Graphics.FONT_XTINY, "Dist", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX - 50, y + 32, Graphics.FONT_TINY, _distanceLabel, Graphics.TEXT_JUSTIFY_CENTER);

            dc.drawText(centerX + 50, y, Graphics.FONT_XTINY, "Time", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX + 50, y + 32, Graphics.FONT_TINY, _timeLabel, Graphics.TEXT_JUSTIFY_CENTER);
            y += 60;

            // Average Speed and Max HR
            dc.drawText(centerX - 50, y, Graphics.FONT_XTINY, "Avg", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX - 50, y + 32, Graphics.FONT_TINY, _avgSpeedLabel, Graphics.TEXT_JUSTIFY_CENTER);

            dc.drawText(centerX + 50, y, Graphics.FONT_XTINY, "Max", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(centerX + 50, y + 32, Graphics.FONT_TINY, _maxHrLabel, Graphics.TEXT_JUSTIFY_CENTER);

        } catch (ex) {
            dc.drawText(dc.getWidth() / 2, 50, Graphics.FONT_SMALL, "ERROR", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //
    // ILensDelegate interface implementation
    //

    //! Called when characteristic value changes (NOTIFY)
    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        // Not used for iLens (write-only)
    }

    //! Called when characteristic read completes
    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        // Not used for iLens
    }

    //! Called when characteristic write completes (WRITE_WITH_RESPONSE)
    //! Flutter의 await 역할: write 완료 후 다음 패킷 전송
    function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        _isWriting = false;  // Write 완료

        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            addTxLog("wr:fail");
            _scanStatus = "WRITE_ERR";
            _writeQueue = [] as Lang.Array<Lang.ByteArray>;  // Queue 초기화 (실패 시 중단)
            DFLogger.logError("WRITE", "Write failed, status=" + status);
            return;
        }

        // ✅ CRITICAL: Single-Stage Time Sync (Current Time Characteristic)
        // reason=0x03 (RTC sync) 완료 확인
        if (characteristic == _currentTimeCharacteristic && !_timeSyncDone) {
            _timeSyncDone = true;
            addBleLog("time:done");
            DFLogger.logBle("TIME_SYNC_DONE", "RTC sync completed successfully");
            return;  // Time sync는 queue와 별개로 처리
        }

        // ✅ Exercise Data Write 성공 → 다음 패킷 전송 (Flutter의 await 효과)
        addTxLog("wr:ok");
        DFLogger.log("[TX] WRITE_OK: Packet sent, queue remaining=" + _writeQueue.size());
        processWriteQueue();
    }

    //! Process write queue (순차 전송)
    //! Flutter의 await chain과 동일한 동작
    private function processWriteQueue() as Void {
        // 이미 write 진행 중이면 skip (callback에서 다시 호출됨)
        if (_isWriting) {
            addTxLog("proc:busy");
            return;
        }

        // Queue가 비었으면 종료
        if (_writeQueue.size() == 0) {
            addTxLog("proc:done");
            return;
        }

        // Queue에서 첫 패킷 꺼내기
        var packet = _writeQueue[0];
        _writeQueue = _writeQueue.slice(1, null) as Lang.Array<Lang.ByteArray>;  // Remove first element

        addTxLog("send:" + _writeQueue.size());

        // Write 시작
        _isWriting = true;
        sendToILens(packet);
    }

    //! Called when connection state changes (BLE API 콜백 - DataField 방식)
    //! ActiveLook 방식: 연결 시 디바이스만 저장, Service Discovery는 나중에
    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _isConnected = true;
            _connectedDevice = device;
            _connectionStartTime = _elapsedSeconds;  // ✅ 연결 시작 시간 기록
            _timeCharRetryCount = 0;  // 재시도 카운터 리셋
            _scanStatus = "CONNECTED";
            addBleLog("conn:ok");

            DFLogger.logBle("CONNECTED", "Device connected, waiting 2s for Service Discovery");

            // ✅ Service Discovery 즉시 안 함! (ActiveLook 패턴)
            // compute()에서 Lazy Loading으로 처리 (2초 대기 후)
        } else {
            _isConnected = false;
            _connectedDevice = null;
            _exerciseCharacteristic = null;
            _currentTimeCharacteristic = null;
            _timeSyncDone = false;
            _connectionStartTime = 0;
            _timeCharRetryCount = 0;  // 재시도 카운터 리셋
            _scanStatus = "DISCONN";
            addBleLog("conn:lost");

            DFLogger.logBle("DISCONNECTED", "Connection lost");
        }

        WatchUi.requestUpdate();
    }

    //! Try and retry to get a characteristic from a service (ActiveLook 패턴 완전 복제)
    //! @param serviceUuid Service UUID
    //! @param characteristicUuid Characteristic UUID
    //! @param nbRetry Number of retries (권장: 5)
    //! @return Characteristic
    //! @throws InvalidValueException if not found after retries
    private function tryGetServiceCharacteristic(
        serviceUuid as BluetoothLowEnergy.Uuid,
        characteristicUuid as BluetoothLowEnergy.Uuid,
        nbRetry as Lang.Number
    ) as BluetoothLowEnergy.Characteristic {
        if (_connectedDevice == null) {
            throw new Lang.InvalidValueException("(E) Not connected");
        }

        var dev = _connectedDevice as BluetoothLowEnergy.Device;
        var service = dev.getService(serviceUuid);

        // ✅ RETRY PATTERN: nbRetry번 재시도 (ActiveLook 방식)
        for (var i = 0; i < nbRetry; i++) {
            if (service == null) {
                service = dev.getService(serviceUuid);  // ← Service 재시도
                if (service == null) {
                    System.println("[RETRY " + i + "] Service still null");
                } else {
                    System.println("[RETRY " + i + "] Service found!");
                }
            } else {
                var characteristic = service.getCharacteristic(characteristicUuid);
                if (characteristic != null) {
                    // ✅ 성공 시 즉시 리턴
                    System.println("tryGetServiceCharacteristic: success at retry " + i);
                    return characteristic;
                } else {
                    System.println("[RETRY " + i + "] Service OK but Char null");
                }
            }
        }

        // ✅ nbRetry번 실패 시 예외 발생
        if (service == null) {
            System.println("FINAL: Service is NULL");
            throw new Lang.InvalidValueException(
                "(E) Could not get service after " + nbRetry + " retries"
            );
        }
        System.println("FINAL: Service OK but Characteristic is NULL");
        throw new Lang.InvalidValueException(
            "(E) Could not get characteristic after " + nbRetry + " retries"
        );
    }

    //! Send data to iLens
    //! iLens는 WRITE_WITHOUT_RESPONSE 지원 안 함 (Flutter 코드 Line 398-399 참조)
    //! 반드시 WRITE_WITH_RESPONSE 사용해야 함!
    private function sendToILens(packet as Lang.ByteArray) as Void {
        if (_exerciseCharacteristic == null) {
            addTxLog("nochar");
            _isWriting = false;  // Reset
            return;
        }

        try {
            addTxLog("req");

            // ✅ iLens requirement: WRITE_WITH_RESPONSE only!
            _exerciseCharacteristic.requestWrite(packet, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
        } catch (ex) {
            addTxLog("err");
            _isWriting = false;  // Reset on error
        }
    }

    //! Called when descriptor read completes
    function onDescriptorRead(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        // Not used
    }

    //! Called when descriptor write completes
    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        // Not used
    }

    //! Called when profile registration completes (ActiveLook 방식)
    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        addBleLog("prof:reg");

        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileRegistered = true;
            addBleLog("prof:ok");
            _scanStatus = "PROF_OK";

            // ✅ Profile 등록 성공 → 스캔 시작 (ActiveLook 방식)
            try {
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
                addBleLog("scan:start");
            } catch (ex) {
                addBleLog("scan:err");
                _scanStatus = "SCAN_ERR";
            }
        } else {
            addBleLog("prof:fail");
            _scanStatus = "PROF_FAIL";
        }

        WatchUi.requestUpdate();
    }

    //! Called when a device is found during scanning
    function onScanResult(scanResult as BluetoothLowEnergy.ScanResult) as Void {
        // Parse device name from Manufacturer Data (BLE Scanner 방식)
        var deviceName = "UNKNOWN";
        var raw = scanResult.getRawData();
        if (raw != null && raw.size() >= 16 && raw[7] == 0xFF) {
            deviceName = "";
            for (var i = 8; i < 16 && i < raw.size(); i++) {
                var c = raw[i];
                if (c >= 0x20 && c <= 0x7E) {  // Printable ASCII
                    deviceName += c.toChar();
                }
            }
        }

        // Device name 저장 (연결 시 표시용)
        _deviceName = deviceName;

        addBleLog("found:" + deviceName);
        System.println("iLens found: " + deviceName + " RSSI=" + scanResult.getRssi());

        // Auto-connect to first iLens device found (BLE Scanner 방식)
        if (!_isConnected && _connectedDevice == null) {
            _devicesFound++;
            _scanStatus = deviceName;  // 상태에 기기 이름 표시

            // 스캔 중지
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            addBleLog("scan:stop");

            // 직접 페어링 시작 (BLE Scanner 방식 - 반환값 저장 중요!)
            addBleLog("pair:" + deviceName);
            _connectedDevice = BluetoothLowEnergy.pairDevice(scanResult);

            if (_connectedDevice == null) {
                addBleLog("pair:fail");
                _scanStatus = "PAIR_FAIL";
            } else {
                addBleLog("pair:wait");
                _scanStatus = "PAIRING";
            }
        }

        WatchUi.requestUpdate();
    }

    //! Called when scan state changes
    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        var statusStr = status == BluetoothLowEnergy.STATUS_SUCCESS ? "OK" : 
                       status == BluetoothLowEnergy.STATUS_NOT_ENOUGH_RESOURCES ? "NO_RES" :
                       status == BluetoothLowEnergy.STATUS_WRITE_FAIL ? "WRITE_FAIL" : "ERR";
        addBleLog("scan:" + statusStr);

        if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
            if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
                _scanStatus = "SCANNING";
                addBleLog("scan:ok");
            } else {
                _scanStatus = "SCAN_ERR";
                // Show specific error code
                if (status == BluetoothLowEnergy.STATUS_NOT_ENOUGH_RESOURCES) {
                    addBleLog("err:no_prof");
                } else {
                    addBleLog("err:" + status);
                }
            }
        } else if (scanState == BluetoothLowEnergy.SCAN_STATE_OFF) {
            _scanStatus = "SCAN_OFF";
            addBleLog("scan:off");
        }

        WatchUi.requestUpdate();
    }

    //! Called when there's a passive connection (already paired)
    function onPassiveConnection(device as BluetoothLowEnergy.Device) as Void {
        _isConnected = true;
        _scanStatus = "PASSIVE";
        addBleLog("passive:conn");
        WatchUi.requestUpdate();
    }

    //! Legacy callbacks for ILens.mc compatibility (not used in Passive Connection)
    function profileRegistrationStart() as Void {}
    function profileRegistrationComplete() as Void {}
    function onBleError(exception as Lang.Exception) as Void {}

}

//! BLE Delegate - 별도 클래스 (DataField는 다중 상속 불가)
class RunVisionBleDelegate extends BluetoothLowEnergy.BleDelegate {
    private var _view;

    function initialize(view) {
        BleDelegate.initialize();
        _view = view;
        System.println("RunVisionBleDelegate initialized");
    }

    function onScanResults(results as BluetoothLowEnergy.Iterator) as Void {
        System.println("onScanResults called");
        var r = results.next() as BluetoothLowEnergy.ScanResult;
        while (r != null) {
            var raw = r.getRawData();
            if (raw != null && raw.size() >= 16 && raw[7] == 0xFF) {
                var deviceName = "";
                for (var i = 8; i < 16 && i < raw.size(); i++) {
                    var c = raw[i];
                    if (c >= 0x20 && c <= 0x7E) {
                        deviceName += c.toChar();
                    }
                }

                if (deviceName.toLower().find("ilens") != null) {
                    System.println("Found iLens: " + deviceName);
                    _view.onScanResult(r);
                }
            }
            r = results.next() as BluetoothLowEnergy.ScanResult;
        }
    }

    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        System.println("onScanStateChange: state=" + scanState + " status=" + status);
        _view.onScanStateChange(scanState, status);
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        System.println("onConnectedStateChanged: state=" + state);
        _view.onConnectedStateChanged(device, state);
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        System.println("onProfileRegister: status=" + status);
        _view.onProfileRegister(uuid, status);
    }

    //! ✅ CRITICAL FIX: Characteristic Write 콜백 추가
    //! 이 메서드가 없어서 콜백이 손실되고 _isWriting 플래그가 영구 true로 고정됨!
    function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        System.println("onCharacteristicWrite: status=" + status);
        _view.onCharacteristicWrite(characteristic, status);
    }

    //! Characteristic Changed 콜백 (NOTIFY용, iLens는 미사용)
    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        _view.onCharacteristicChanged(characteristic, value);
    }

    //! Characteristic Read 콜백 (iLens는 미사용)
    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        _view.onCharacteristicRead(characteristic, status, value);
    }

    //! Descriptor Read 콜백 (iLens는 미사용)
    function onDescriptorRead(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        _view.onDescriptorRead(descriptor, status, value);
    }

    //! Descriptor Write 콜백 (iLens는 미사용)
    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        _view.onDescriptorWrite(descriptor, status);
    }
}

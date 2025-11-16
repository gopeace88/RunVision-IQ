using Toybox.BluetoothLowEnergy;
using Toybox.Lang;
using Toybox.System;

//! iLens Custom Service (Exercise Data) - Main Service
//! Flutter 앱과 동일한 UUID (iLens-3265 실제 기기)
const BLE_SERV_ILENS               as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08");
//! iLens Main Characteristic (Config + Data 공용)
const BLE_CHAR_EXERCISE_DATA       as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615");

//! Device Information Service (Standard BLE Service 0x180A)
const BLE_SERV_DEVICE_INFORMATION  as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x0000180A00001000l, 0x800000805F9B34FBl);
//! Device Information Service Characteristics
const BLE_CHAR_MANUFACTURER_NAME   as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A2900001000l, 0x800000805F9B34FBl);
const BLE_CHAR_MODEL_NUMBER        as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A2400001000l, 0x800000805F9B34FBl);
const BLE_CHAR_SERIAL_NUMBER       as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A2500001000l, 0x800000805F9B34FBl);
const BLE_CHAR_HARDWARE_VERSION    as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A2700001000l, 0x800000805F9B34FBl);
const BLE_CHAR_FIRMWARE_VERSION    as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A2600001000l, 0x800000805F9B34FBl);
const BLE_CHAR_SOFTWARE_VERSION    as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A2800001000l, 0x800000805F9B34FBl);

//! Battery Service (Standard BLE Service 0x180F)
const BLE_SERV_BATTERY             as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x0000180F00001000l, 0x800000805F9B34FBl);
//! Battery Service Characteristics
const BLE_CHAR_BATTERY_LEVEL       as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A1900001000l, 0x800000805F9B34FBl);

//! Generic Access Service (Standard BLE Service 0x1800) - ALL BLE devices advertise this
const BLE_SERV_GENERIC_ACCESS      as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x0000180000001000l, 0x800000805F9B34FBl);
const BLE_CHAR_DEVICE_NAME         as Toybox.BluetoothLowEnergy.Uuid = Toybox.BluetoothLowEnergy.longToUuid(0x00002A0000001000l, 0x800000805F9B34FBl);

const PROFILE_GENERIC_ACCESS = ({
    :uuid => BLE_SERV_GENERIC_ACCESS,
    :characteristics => [
        { :uuid => BLE_CHAR_DEVICE_NAME },
    ]
}) as ILensBLE.ILens.BleProfile;

const PROFILE_ILENS = ({
    :uuid => BLE_SERV_ILENS,
    :characteristics => [
        { :uuid => BLE_CHAR_EXERCISE_DATA },  // WRITE characteristic for sending metrics
    ]
}) as ILensBLE.ILens.BleProfile;

const PROFILE_DEVICE_INFO = ({
    :uuid => BLE_SERV_DEVICE_INFORMATION,
    :characteristics => [
        { :uuid => BLE_CHAR_MANUFACTURER_NAME },
        { :uuid => BLE_CHAR_MODEL_NUMBER },
        { :uuid => BLE_CHAR_SERIAL_NUMBER },
        { :uuid => BLE_CHAR_HARDWARE_VERSION },
        { :uuid => BLE_CHAR_FIRMWARE_VERSION },
        { :uuid => BLE_CHAR_SOFTWARE_VERSION },
    ]
}) as ILensBLE.ILens.BleProfile;

const PROFILE_BATTERY_INFO = ({
    :uuid => BLE_SERV_BATTERY,
    :characteristics => [
        { :uuid => BLE_CHAR_BATTERY_LEVEL, :descriptors => [Toybox.BluetoothLowEnergy.cccdUuid()] },
    ]
}) as ILensBLE.ILens.BleProfile;

// CRITICAL: Generic Access (0x1800) MUST be first - it's advertised by ALL BLE devices
// iLens doesn't advertise its custom service UUID, so we use Generic Access for scanning
const ILENS_PROFILES = [{:profile => PROFILE_GENERIC_ACCESS, :label => "Generic Access service"},
                        {:profile => PROFILE_ILENS, :label => "iLens service"},
                        {:profile => PROFILE_DEVICE_INFO, :label => "Device info service"}];


//! This module provides all the functionalities to handle
//! the iLens AR Glasses as Bluetooth Low Energy objects.
//! Based on ActiveLook BLE implementation with iLens protocol.
module ILensBLE {

    //! The BLE Delegate class for iLens. It relies on a single instance which is
    //! built with the <code>setUp</code> static class method.
    class ILens extends Toybox.BluetoothLowEnergy.BleDelegate {

        //! Private logger enabled in debug and disabled in release mode
        (:release) private static function _log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {}
        (:debug)   private static function _log(msg as Toybox.Lang.String, data as Toybox.Lang.Object or Null) as Void {
            if ($ has :log) { $.log(Toybox.Lang.format("[ILensBLE] $1$", [msg]), data); }
        }

        //! Interface for delegate
        typedef ILensDelegate as interface {
            function onCharacteristicChanged(characteristic as Toybox.BluetoothLowEnergy.Characteristic, value as Toybox.Lang.ByteArray) as Void;
            function onCharacteristicRead(characteristic as Toybox.BluetoothLowEnergy.Characteristic, status as Toybox.BluetoothLowEnergy.Status, value as Toybox.Lang.ByteArray) as Void;
            function onCharacteristicWrite(characteristic as Toybox.BluetoothLowEnergy.Characteristic, status as Toybox.BluetoothLowEnergy.Status) as Void;
            function onConnectedStateChanged(device as Toybox.BluetoothLowEnergy.Device, state as Toybox.BluetoothLowEnergy.ConnectionState) as Void;
            function onDescriptorRead(descriptor as Toybox.BluetoothLowEnergy.Descriptor, status as Toybox.BluetoothLowEnergy.Status, value as Toybox.Lang.ByteArray) as Void;
            function onDescriptorWrite(descriptor as Toybox.BluetoothLowEnergy.Descriptor, status as Toybox.BluetoothLowEnergy.Status) as Void;
            function onScanResult(scanResult as Toybox.BluetoothLowEnergy.ScanResult) as Void;
            function onScanStateChange(scanState as Toybox.BluetoothLowEnergy.ScanState, status as Toybox.BluetoothLowEnergy.Status) as Void;
            function onPassiveConnection(device as Toybox.BluetoothLowEnergy.Device) as Void;
            function profileRegistrationStart() as Void;
            function profileRegistrationComplete() as Void;
            function onBleError(exception as Toybox.Lang.Exception) as Void;
        };

        //! Type for registering profile
        typedef BleProfile as {
            :uuid as Toybox.BluetoothLowEnergy.Uuid,
            :characteristics as Toybox.Lang.Array<{
                :uuid as Toybox.BluetoothLowEnergy.Uuid,
                :descriptors as Toybox.Lang.Array<Toybox.BluetoothLowEnergy.Uuid>
            }>,
        };

        //! Private instance variable
        private var _delegate as ILensBLE.ILens.ILensDelegate;

        //! Private constructor to make it impossible to instantiate this class without calling setUp.
        //!
        //! @param delegate The object that will be responsible for handling events.
        private function initialize(delegate as ILensBLE.ILens.ILensDelegate) {
            Toybox.BluetoothLowEnergy.BleDelegate.initialize();
            _log("initialize", []);
            _delegate = delegate;
            Toybox.BluetoothLowEnergy.setDelegate(self);
        }

        //! Private static BLE shared state.
        private static var _ilens                        as ILensBLE.ILens
                                                         or Null
                                                         = null;
        private static var _registeredProfile            as Toybox.Lang.Array<Toybox.BluetoothLowEnergy.Uuid>
                                                         = [] as Toybox.Lang.Array<Toybox.BluetoothLowEnergy.Uuid>;
        private static var _currentScanState             as Toybox.BluetoothLowEnergy.ScanState
                                                         = Toybox.BluetoothLowEnergy.SCAN_STATE_OFF;
        private static var _desiredScanState             as Toybox.BluetoothLowEnergy.ScanState
                                                         = Toybox.BluetoothLowEnergy.SCAN_STATE_OFF;
        private static var _fixScanStateNbSwitch         as Toybox.Lang.Number
                                                         = 0;
        private static var _autoDevice                   as Toybox.BluetoothLowEnergy.Device
                                                         or Null
                                                         = null;
        private static var _device                       as Toybox.BluetoothLowEnergy.Device
                                                         or Null
                                                         = null;
        private static var _profileIndexToRegister       as Toybox.Lang.Number
                                                         = 0;

        //! Static setUp function that must be called at least once for registering the 3 necessary profiles
        //! for playing with the iLens AR Glasses. It will register those profiles only once.
        //! All subsequent calls will replace the delegate in the class single instance.
        //!
        //! @param delegate The object that will be responsible for handling events.
        //!
        //! @return         The iLens object to use for handling Bluetooth operations.
        static function setUp(delegate as ILensBLE.ILens.ILensDelegate) as ILensBLE.ILens {
            _log("setUp", [_ilens, delegate]);
            var skipRegister = _ilens != null ? true : false;
            _ilens = new ILens(delegate);
            if (skipRegister) { return _ilens as ILensBLE.ILens; }

            // Check if there is a passive connection to the device exists
            // we do not want to register profiles/scan/connect to device
            var dev = BluetoothLowEnergy.getPairedDevices().next() as Toybox.BluetoothLowEnergy.Device;

            if (dev != null) {
                _device = dev;
                _log("setUp", "Passive connection exist");
                _registeredProfile.add(ILENS_PROFILES[0][:profile][:uuid] as Toybox.BluetoothLowEnergy.Uuid);
                _registeredProfile.add(ILENS_PROFILES[1][:profile][:uuid] as Toybox.BluetoothLowEnergy.Uuid);
                _registeredProfile.add(ILENS_PROFILES[2][:profile][:uuid] as Toybox.BluetoothLowEnergy.Uuid);
                delegate.onPassiveConnection(_device as Toybox.BluetoothLowEnergy.Device);
                return _ilens as ILensBLE.ILens;
            }

            // Register the profiles sequentially, one after other, when onProfileRegister() callback
            // is called for previous profile registration success
            if (_profileIndexToRegister < ILENS_PROFILES.size()) {
                delegate.profileRegistrationStart();
                Toybox.BluetoothLowEnergy.registerProfile(ILENS_PROFILES[_profileIndexToRegister][:profile] as ILensBLE.ILens.BleProfile);
                _log("setUp", [ILENS_PROFILES[_profileIndexToRegister][:label] + " registered"]);
                _profileIndexToRegister++;
            }
            // No more profile as specified here:
            // https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html#registerProfile-instance_function
            // Registration can fail if too many profiles are registered, the current limit is 3.
            return _ilens as ILensBLE.ILens;
        }

        //! Request to enter in the desired scan state.
        //! Depending on the current state, it will either switch current scan state
        //! or keep current state.
        //!
        //! @param state The requested scan state. It can be
        //!              <code>false</code> to disable scanning or
        //!              <code>true</code> to enable scanning.
        (:typecheck(false))
        static function requestScanning(state as Toybox.Lang.Boolean) as Void {
            _log("requestScanning", [state]);
            if   (state == false) { _desiredScanState = Toybox.BluetoothLowEnergy.SCAN_STATE_OFF; }
            else                  { _desiredScanState = Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING; }
            _fixScanStateNbSwitch = 0;
            if (_currentScanState == _desiredScanState) {
                if (_ilens != null) {
                    _ilens.onScanStateChange(_currentScanState, -1 as Toybox.BluetoothLowEnergy.Status);
                }
            } else {
                Toybox.BluetoothLowEnergy.setScanState(_desiredScanState);
            }
        }

        //! Try to fix the scan state if it was in error.
        //! For example, if the scan state has been set to
        //! Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING
        //! but the profiles have not been properly registered,
        //! it will try to switch to Toybox.BluetoothLowEnergy.SCAN_STATE_OFF
        //! and a second call will switch back to Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING
        //!
        //! You should call this function periodically if you didn't get a success in onScanStateChange.
        //! Call it periodically with some interval to let the bluetooth work properly.
        //!
        //! @return True if we tried to fix an error and false if there was no error to fix.
        static function fixScanState() as Toybox.Lang.Boolean {
            _log("fixScanState", [_fixScanStateNbSwitch, _currentScanState, _desiredScanState]);
            if (_fixScanStateNbSwitch > 0) {
                if (_currentScanState == Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING) {
                    Toybox.BluetoothLowEnergy.setScanState(Toybox.BluetoothLowEnergy.SCAN_STATE_OFF);
                } else {
                    Toybox.BluetoothLowEnergy.setScanState(Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING);
                }
                return true;
            }
            return false;
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onCharacteristicChanged
        function onCharacteristicChanged(characteristic as Toybox.BluetoothLowEnergy.Characteristic, value as Toybox.Lang.ByteArray) as Void {
            _log("onCharacteristicChanged", [characteristic, value]);
            _delegate.onCharacteristicChanged(characteristic, value);
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onCharacteristicRead
        function onCharacteristicRead(characteristic as Toybox.BluetoothLowEnergy.Characteristic, status as Toybox.BluetoothLowEnergy.Status, value as Toybox.Lang.ByteArray) as Void {
            _log("onCharacteristicRead", [characteristic, status, value]);
            _delegate.onCharacteristicRead(characteristic, status, value);
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onCharacteristicWrite
        function onCharacteristicWrite(characteristic as Toybox.BluetoothLowEnergy.Characteristic, status as Toybox.BluetoothLowEnergy.Status) as Void {
            _log("onCharacteristicWrite", [characteristic.getUuid(), status]);
            _delegate.onCharacteristicWrite(characteristic, status);
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onConnectedStateChanged
        function onConnectedStateChanged(device as Toybox.BluetoothLowEnergy.Device, state as Toybox.BluetoothLowEnergy.ConnectionState) as Void {
            _log("onConnectedStateChanged", [device, state]);
            if (state == Toybox.BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                _device = device;
            } else {
                _device = null;
            }
            _delegate.onConnectedStateChanged(device, state);
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onDescriptorRead
        function onDescriptorRead(descriptor as Toybox.BluetoothLowEnergy.Descriptor, status as Toybox.BluetoothLowEnergy.Status, value as Toybox.Lang.ByteArray) as Void {
            _log("onDescriptorRead", [descriptor, status, value]);
            _delegate.onDescriptorRead(descriptor, status, value);
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onDescriptorWrite
        function onDescriptorWrite(descriptor as Toybox.BluetoothLowEnergy.Descriptor, status as Toybox.BluetoothLowEnergy.Status) as Void {
            _log("onDescriptorWrite", [descriptor, status]);
            _delegate.onDescriptorWrite(descriptor, status);
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onProfileRegister
        function onProfileRegister(uuid as Toybox.BluetoothLowEnergy.Uuid, status as Toybox.BluetoothLowEnergy.Status) as Void {
            _log("onProfileRegister", [uuid, status, _registeredProfile.size()]);
            if (status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
                if (_registeredProfile.indexOf(uuid) == -1) {
                    _registeredProfile.add(uuid);
                    _log("onProfileRegister", ["+1", uuid, status, _registeredProfile.size()]);
                }
                if (_profileIndexToRegister == ILENS_PROFILES.size()) {
                    _delegate.profileRegistrationComplete();
                }
                if (_profileIndexToRegister < ILENS_PROFILES.size()) {
                    Toybox.BluetoothLowEnergy.registerProfile(ILENS_PROFILES[_profileIndexToRegister][:profile] as ILensBLE.ILens.BleProfile);
                    _log("onProfileRegister", [ILENS_PROFILES[_profileIndexToRegister][:label] + " registered"]);
                    _profileIndexToRegister++;
                }
            } else {
                // 프로필 등록 실패 처리
                _log("onProfileRegister", ["FAILED", uuid, status]);
                // Exception 없이 delegate에 직접 알림 (Exception 생성은 복잡할 수 있음)
                // 대신 로그만 남기고 계속 진행 (프로필 등록 실패는 치명적이지 않을 수 있음)
            }
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onScanResults
        //! CRITICAL: iLens does NOT advertise service UUID!
        //! CRITICAL: getDeviceName() returns NULL!
        //! Parse device name from Manufacturer Data (Position 8-15)
        function onScanResults(scanResults as Toybox.BluetoothLowEnergy.Iterator) as Void {
            _log("onScanResults", [scanResults]);
            if (_registeredProfile.size() < 3) {
                _log("onScanResults", ["Profile not registered yet", _registeredProfile.size()]);
                return;
            }

            for (var device = scanResults.next() as Toybox.BluetoothLowEnergy.ScanResult; device != null; device = scanResults.next()) {
                _log("onScanResults", ["rssi", device.getRssi()]);

                // Parse Manufacturer Data from Raw Data
                var raw = device.getRawData();
                if (raw == null || raw.size() < 16) {
                    _log("onScanResults", ["Raw data too short or null", raw != null ? raw.size() : 0]);
                    continue;
                }

                // Check if Position 7 is Type 0xFF (Manufacturer Data)
                if (raw[7] != 0xFF) {
                    _log("onScanResults", ["Not Manufacturer Data", raw[7]]);
                    continue;
                }

                // Parse device name from Position 8-15 (Manufacturer Data)
                var deviceName = "";
                for (var i = 8; i < 16 && i < raw.size(); i++) {
                    var c = raw[i];
                    if (c >= 0x20 && c <= 0x7E) {  // Printable ASCII
                        deviceName += c.toChar();
                    }
                }

                _log("onScanResults", ["Parsed device name", deviceName]);

                // iLens filtering: Device name format is "iLens-XXXX" or "iLens-sw"
                var isILens = false;
                if (deviceName.length() > 0) {
                    var nameLower = deviceName.toLower();
                    if (nameLower.find("ilens") != null) {
                        isILens = true;
                    }
                }

                if (isILens) {
                    _log("onScanResults", ["iLens device found!", deviceName]);
                    _delegate.onScanResult(device);
                } else {
                    _log("onScanResults", ["Not iLens, skipped", deviceName]);
                }
            }
        }

        //! Override Toybox.BluetoothLowEnergy.BleDelegate.onScanStateChange
        function onScanStateChange(scanState as Toybox.BluetoothLowEnergy.ScanState, status as Toybox.BluetoothLowEnergy.Status) as Void {
            _log("onScanStateChange", [scanState, status]);
            _fixScanStateNbSwitch = 0;
            _currentScanState = scanState;
            var profileSize = _registeredProfile.size();
            if (_currentScanState != _desiredScanState) {
                _log("onScanStateChange", [scanState, status, "Could not set desired state", profileSize]);
                if (status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
                    status = Toybox.BluetoothLowEnergy.STATUS_WRITE_FAIL;
                }
                _fixScanStateNbSwitch = 1;
            } else if (profileSize < 3) {
                _log("onScanStateChange", [scanState, "STATUS_NOT_ENOUGH_RESOURCES", profileSize]);
                status = Toybox.BluetoothLowEnergy.STATUS_NOT_ENOUGH_RESOURCES;
                if (_currentScanState == Toybox.BluetoothLowEnergy.SCAN_STATE_SCANNING) {
                    _fixScanStateNbSwitch = 2;
                }
            } else if (profileSize > 3) {
                _log("onScanStateChange", [scanState, status, "Profile registered more than expected", profileSize]);
            }
            _delegate.onScanStateChange(scanState, status);
        }

        //! Try and retry to get a characteristic from a service.
        //! Throw an exception if not possible.
        //!
        //! @param serviceUuid        The service uuid.
        //! @param characteristicUuid The characteristic uuid.
        //! @param nbRetry            The number of retry.
        //!
        //! @return                   The Bluetooth characteristic.
        //! @throws                   Toybox.Lang.InvalidValueException
        //!                           if the characteristic could not be
        //!                           retrieved after the number of retry.
        private function tryGetServiceCharacteristic(
            serviceUuid        as Toybox.BluetoothLowEnergy.Uuid,
            characteristicUuid as Toybox.BluetoothLowEnergy.Uuid,
            nbRetry            as Toybox.Lang.Number
        ) as Toybox.BluetoothLowEnergy.Characteristic {
            if (_device == null) { throw new Toybox.Lang.InvalidValueException("(E) Not connected"); }
            var dev = _device as Toybox.BluetoothLowEnergy.Device;
            var service = dev.getService(serviceUuid);
            for (var i = 0; i < nbRetry; i++) {
                if (service == null) {
                    service = dev.getService(serviceUuid);
                } else {
                    var characteristic = service.getCharacteristic(characteristicUuid);
                    if (characteristic != null) {
                        _log("tryGetServiceCharacteristic", [serviceUuid, characteristicUuid, nbRetry, i]);
                        return characteristic;
                    }
                }
            }
            if (service == null) {
                throw new Toybox.Lang.InvalidValueException(
                    Toybox.Lang.format("(E) Could not get service $1$", [serviceUuid])
                );
            }
            throw new Toybox.Lang.InvalidValueException(
                Toybox.Lang.format("(E) Could not get characteristic $1$", [characteristicUuid])
            );
        }

        //! Try 5 times to get the Exercise Data characteristic
        //! from the iLens service.
        //!
        //! @return The Bluetooth characteristic.
        //! @throws A <code>Toybox.Lang.InvalidValueException</code>
        //!         if the characteristic could not be retrieved after 5 attempts.
        function getBleCharacteristicExerciseData() as Toybox.BluetoothLowEnergy.Characteristic {
            _log("getBleCharacteristicExerciseData", []);
            return tryGetServiceCharacteristic(BLE_SERV_ILENS, BLE_CHAR_EXERCISE_DATA, 5);
        }

        //! Try 5 times to get the <code>BLE_CHAR_FIRMWARE_VERSION</code> characteristic
        //! from the <code>BLE_SERV_DEVICE_INFORMATION</code> service.
        //!
        //! @return The Bluetooth characteristic.
        //! @throws A <code>Toybox.Lang.InvalidValueException</code>
        //!         if the characteristic could not be retrieved after 5 attempts.
        function getBleCharacteristicFirmwareVersion() as Toybox.BluetoothLowEnergy.Characteristic {
            _log("getBleCharacteristicFirmwareVersion", []);
            return tryGetServiceCharacteristic(BLE_SERV_DEVICE_INFORMATION, BLE_CHAR_FIRMWARE_VERSION, 5);
        }

        //! Try 5 times to get the <code>BLE_CHAR_BATTERY_LEVEL</code> characteristic
        //! from the <code>BLE_SERV_BATTERY</code> service.
        //!
        //! @return The Bluetooth characteristic.
        //! @throws A <code>Toybox.Lang.InvalidValueException</code>
        //!         if the characteristic could not be retrieved after 5 attempts.
        function getBleCharacteristicBatteryLevel() as Toybox.BluetoothLowEnergy.Characteristic {
            _log("getBleCharacteristicBatteryLevel", []);
            return tryGetServiceCharacteristic(BLE_SERV_BATTERY, BLE_CHAR_BATTERY_LEVEL, 5);
        }

        //! Disconnect and unpair from all paired devices. Normally, there should always be at most one
        //! but to be sure to disconnect from any devices, we unpair every paired devices.
        //!
        //! @return <code>false</code> if there was no device to unpaired, <code>true</code> otherwise.
        function disconnect() as Toybox.Lang.Boolean {
            _log("disconnect", []);
            _autoDevice = null;
            var autoDevices = Toybox.BluetoothLowEnergy.getPairedDevices();
            var count = 0;
            for (var autoDevice = autoDevices.next() as Toybox.BluetoothLowEnergy.Device; autoDevice != null; autoDevice = autoDevices.next()) {
                Toybox.BluetoothLowEnergy.unpairDevice(autoDevice);
                count += 1;
            }
            return count != 0;
        }

        //! Connect and pair to a scanned device. It will first turn off scanning and
        //! disconnect from other device. This is for consistency since we don't allow
        //! multiple device to be connected at once.
        //! Then it tries to pair with the device.
        //! On error, it will call the delegate <code>onError</code> method with
        //! the caught exception from the pairing operation or with a
        //! <code>Toybox.System.PreviousOperationNotCompleteException</code> if the pairing could
        //! not be completed for unknown reason.
        //!
        //! @param scanResult The scan result from onScanResult.
        //!
        //! @return           <code>true</code> if the operation was successful, <code>false</code> otherwise.
        function connect(scanResult as Toybox.BluetoothLowEnergy.ScanResult) as Toybox.Lang.Boolean {
            _log("connect", [scanResult]);
            requestScanning(false);
            disconnect();
            try {
                _autoDevice = BluetoothLowEnergy.pairDevice(scanResult);
                if (_autoDevice != null) { return true; }
                _delegate.onBleError(new Toybox.System.PreviousOperationNotCompleteException("The device could not be paired."));
            } catch (e) {
                _delegate.onBleError(e);
            }
            return false;
        }

        //! Write metric data to iLens using ILensProtocol
        //! This is the key method for sending exercise data to iLens AR glasses.
        //!
        //! @param packet 5-byte packet from ILensProtocol (Metric_ID + Value)
        //!
        //! @return <code>true</code> if write was successful, <code>false</code> otherwise.
        function writeMetric(packet as Toybox.Lang.ByteArray) as Toybox.Lang.Boolean {
            _log("writeMetric", [packet]);
            if (_device == null) {
                _log("writeMetric", "Not connected");
                return false;
            }

            try {
                var char = getBleCharacteristicExerciseData();
                char.requestWrite(packet, {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
                return true;
            } catch (e) {
                _log("writeMetric failed", e);
                _delegate.onBleError(e);
                return false;
            }
        }

    }

}

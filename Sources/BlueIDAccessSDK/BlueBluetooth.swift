import Foundation
import CoreBluetooth
import CBlueIDAccess

internal let blueServiceUUID = CBUUID(string: String(format: "%04X", BLUE_BLE_SERVICE_UUID))

private var blueBluetoothIsActive = false
private var blueCentralManager: CBCentralManager? = nil
private var blueCentralManagerListener: BlueCentralManagerListener? = nil

private final class BlueCentralManagerListener: NSObject, CBCentralManagerDelegate {
    //
    // Delegate method implementations for CBCentralManagerDelegate
    //
    
    public func centralManagerDidUpdateState(_ centralManager: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        switch centralManager.state {
            case .poweredOn:
                blueFireListeners(fireEvent: .bluetoothStateChanged, data: true)
                break
                
            case .poweredOff:
                blueFireListeners(fireEvent: .bluetoothStateChanged, data: false)
                break
                
            default:
                break
        }
        
        blueUpdateBluetoothScanning()
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        let deviceID = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        
        guard let deviceID = deviceID, !deviceID.isEmpty else {
            return
        }
        
        var isNew = false
        
        let device: BlueDevice? = blueGetDevice(deviceID)
        var bleDevice: BlueDeviceBluetooth? = nil
        
        if let device = device {
            guard let device = device as? BlueDeviceBluetooth else {
                blueLogError("Device with id \(deviceID) expected to be a bluetooth device but it is not")
                return
            }
            
            bleDevice = device
        } else {
            bleDevice = BlueDeviceBluetooth(peripheral: peripheral, deviceID: deviceID)
            isNew = true
        }
        
        if let bleDevice = bleDevice {
            bleDevice.updateRssi(RSSI.doubleValue)
            
            do {
                try bleDevice.updateFromAdvertisementData(advertisementData: advertisementData)
            } catch let error {
                blueLogError("Error on updating advertisement data from device \(deviceID): \(error.localizedDescription)")
            }
            
            if (isNew) {
                // Add device which will do the notification
                blueAddDevice(bleDevice)
            } else {
                // Nothing to do, just fire the update listeners
                blueNotifyUpdatedDevice(bleDevice)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueSignalSuccess(group: "bleCentral", name: "didConnect")
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        if let error = error {
            blueSignalFailure(group: "bleCentral", name: "didDisconnectPeripheral", error: error)
        } else {
            //
            // We'll try to find the device that is connected and notify it about the disconnect so it can handle it itself
            //
            if let deviceID = peripheral.name {
                if let device = blueGetDevice(deviceID) as? BlueDeviceBluetooth {
                    device.notifyDisconnected()
                }
            }
            
            blueSignalSuccess(group: "bleCentral", name: "didDisconnectPeripheral")
        }
    }
}

private func blueUpdateBluetoothScanning() {
    if let blueCentralManager = blueCentralManager {
        if (blueCentralManager.isScanning) {
            blueCentralManager.stopScan()
            blueLogDebug("Stopped bluetooth scanning")
        }
        
        if (blueBluetoothIsActive) {
            if blueCentralManager.state == .poweredOn {
                blueCentralManager.scanForPeripherals(withServices: [blueServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                blueLogDebug("Started bluetooth scanning")
            }
        }
    }
}

internal func blueConnectBluetoothPeripheral(_ peripheral: CBPeripheral) throws {
    dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
    
    guard let blueCentralManager = blueCentralManager else {
        throw BlueError(.invalidState)
    }
    
    if peripheral.state == .connected {
        // Assume this is fine
        blueLogWarn("Try to connect an already connected peripheral")
        return
    }
    
    guard peripheral.state == .disconnected else {
        throw BlueError(.unavailable)
    }
    
    blueCentralManager.stopScan()
    
    try blueAddSignal(group: "bleCentral", name: "didConnect")
    
    defer { blueRemoveSignal(group: "bleCentral", name: "didConnect") }
    
    blueCentralManager.connect(peripheral)
    
    _ = try blueWaitSignal(group: "bleCentral", name: "didConnect")
    
    if (peripheral.state != .connected) {
        blueLogError("Peripheral was expected to be connected at this point")
        throw BlueError(.invalidState)
    }
}

internal func blueDisconnectBluetoothPeripheral(_ peripheral: CBPeripheral) throws {
    dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
    
    guard let blueCentralManager = blueCentralManager else {
        throw BlueError(.invalidState)
    }
    
    defer {
        // Always re-activate scanning when leaving this function
        blueUpdateBluetoothScanning()
    }
    
    if peripheral.state == .disconnected {
        // Assume this is fine
        blueLogWarn("Try to disconnect an already disconnected peripheral")
        return
    }
    
    guard peripheral.state == .connected || peripheral.state == .connecting else {
        throw BlueError(.unavailable)
    }
    
    // Remove all signals in case of disconnection, as some of them may not have been properly removed in the event of an abnormal disconnection, such as a timeout.
    blueSignalAbort(group: "bleCentral")
    
    try blueAddSignal(group: "bleCentral", name: "didDisconnectPeripheral")
    
    defer { blueRemoveSignal(group: "bleCentral", name: "didDisconnectPeripheral") }
    
    blueCentralManager.cancelPeripheralConnection(peripheral)
    
    _ = try blueWaitSignal(group: "bleCentral", name: "didDisconnectPeripheral")
    
    if (peripheral.state != .disconnected) {
        blueLogError("Peripheral was expected to be disconnected at this point")
        throw BlueError(.invalidState)
    }
}

public struct BlueBluetoothActivate: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        try run(
            maxDeviceAgeSeconds: try blueCastArg(Double.self, arg0)
        )
        
        return nil
    }
    
    /// Starts scanning for BLE peripherals.
    ///
    /// - parameter maxDeviceAgeSeconds: Represents the maximum time duration, in seconds, for which a device is considered valid or relevant. In the event that the device does not advertise within this period, it will be removed.
    /// - throws: Throws an error of type `BlueError(.invalidState)` if the scanning is already activated.
    public func run(maxDeviceAgeSeconds: Double? = nil) throws -> Void {
        dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
        
        guard !blueBluetoothIsActive else {
            throw BlueError(.invalidState)
        }
        
        if blueCentralManager == nil {
            blueCentralManagerListener = BlueCentralManagerListener()
            blueCentralManager = CBCentralManager(delegate: blueCentralManagerListener, queue: blueDeviceQueue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        }
        
        if let blueCentralManager = blueCentralManager {
            if (blueCentralManager.state == .unsupported || blueCentralManager.state == .unauthorized) {
                throw BlueError(.invalidState)
            }
            
            if let maxDeviceAgeSeconds = maxDeviceAgeSeconds {
                blueSetMaxDeviceAgeSeconds(maxDeviceAgeSeconds)
            }
            
            blueBluetoothIsActive = true
            
            bluePurgeDevicesByType(.bluetoothDevice)
            
            blueAddDeviceScanner()
            
            blueUpdateBluetoothScanning()
        }
    }
}

public struct BlueBluetoothDeactivate: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        try run()
        return nil
    }
    
    public func run() throws -> Void {
        dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
        
        guard blueBluetoothIsActive else {
            throw BlueError(.invalidState)
        }
        
        blueBluetoothIsActive = false
        
        bluePurgeDevicesByType(.bluetoothDevice)
        
        blueClearDeviceScanner()
        
        blueUpdateBluetoothScanning()
    }
}

public struct BlueIsBluetoothActiveCommand: BlueCommand {
    internal func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any? {
        return run()
    }
    
    public func run() -> Bool {
        return blueBluetoothIsActive
    }
}

public struct BlueCheckBluetoothPermissionCommand: BlueCommand {
    internal func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any? {
        return run()
    }
    
    public func run() -> String {
        if #available(macOS 10.15, *) {
            switch(CBCentralManager.authorization) {
                case .notDetermined:
                    return "notDetermined"
                    
                case .restricted, .denied:
                    return "denied"
                    
                case .allowedAlways:
                    return "granted"
                    
                @unknown default:
                    return "notDetermined"
            }
        }
        
        return "notDetermined"
    }
}

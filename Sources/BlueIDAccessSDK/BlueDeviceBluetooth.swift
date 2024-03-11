import Foundation
import CoreBluetooth
import CBlueIDAccess

typealias BlueFunBleDeviceReadManufacturerDataRaw = @convention(c) (UnsafePointer<UInt8>?, UInt8, UnsafeMutablePointer<UInt8>?, UInt32) -> Int32

internal let blueCharacteristic_RX_UUID = CBUUID(string: BLUE_BLE_RX_CHARACTERISTIC_UUID)
internal let blueCharacteristic_TX_UUID = CBUUID(string: BLUE_BLE_TX_CHARACTERISTIC_UUID)
internal let blueCharacteristic_MF_UUID = CBUUID(string: BLUE_BLE_MF_CHARACTERISTIC_UUID)

internal class BlueDeviceBluetooth: BlueDevice, CBPeripheralDelegate {
    internal static var maxRssiAgeInSeconds = 60.0
    internal static var maxAdvertisementDataAgeSeconds = 120.0
    internal static var writeWithoutResponse = true
    internal static var readManufacturerInfoFromCharacteristic = true
    
    internal override var isConnected: Bool {
        get {
            return peripheral.state == .connected
        }
    }
    
    private let peripheral: CBPeripheral
    
    private var rxCharacteristic: CBCharacteristic? = nil
    private var txCharacteristic: CBCharacteristic? = nil
    private var mfCharacteristic: CBCharacteristic? = nil
    
    private var mtuSize: UInt  = 0
    private var lastFullAdvertisementDataReadAt: Date? = nil
    private var rssiValues: [(rssi: Double, scannedAt: Date)] = []
    
    internal init(peripheral: CBPeripheral, deviceID: String) {
        self.peripheral = peripheral
        
        super.init()
        
        info.deviceType = .bluetoothDevice
        info.deviceID = deviceID
        info.distanceMeters = 0
        info.bluetooth = BlueDeviceDetailsBluetooth()
        info.bluetooth.rssi = 0
        info.bluetooth.txPower = 0
        info.bluetooth.isIbeacon = false
        
        self.peripheral.delegate = self
    }
    
    internal override func connect() throws {
        dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
        
        if (peripheral.state == .connected) {
            // Nothing to do
            blueLogWarn("Try to connect an already connected device")
            return
        }
        
        do {
            blueLogDebug("Try to connect")
            
            try blueConnectBluetoothPeripheral(peripheral)
            
            //
            // Assign mtu size after connection to our transport. Note that we use .withoutResponse
            // here as otherwise CoreBluetooth always returns 512 and does the queuing itself which
            // we don't want. Also note this is the actual MTU and NOT the ATT MTU size so no need
            // to remove the ATT header size from it
            //
            var mtuSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
            if (mtuSize <= 0) {
                mtuSize = 20 // set minimum size
            }
            
            self.mtuSize = UInt(mtuSize)
            
            blueLogDebug("Connected, negotiated MTU-Size of \(mtuSize) bytes")
            
            //
            // Discover our blue service
            //
            blueLogDebug("Try to discover blue service")
            
            try blueAddSignal(group: "blePeripheral", name: "didDiscoverServices")
            
            defer { blueRemoveSignal(group: "blePeripheral", name: "didDiscoverServices") }
            
            peripheral.discoverServices([blueServiceUUID])
            
            _ = try blueWaitSignal(group: "blePeripheral", name: "didDiscoverServices")
            
            guard let blueService: CBService = peripheral.services?.first (where: { $0.uuid == blueServiceUUID }) else {
                blueLogDebug("Unable to find Blue-Service with UUID \(blueServiceUUID.uuidString)")
                throw BlueError(.bleServiceNotFound)
            }
            
            //
            // Discover our required characteristics
            //
            
            blueLogDebug("Try to discover characteristics")
            
            try blueAddSignal(group: "blePeripheral", name: "didDiscoverCharacteristicsFor")
            
            defer { blueRemoveSignal(group: "blePeripheral", name: "didDiscoverCharacteristicsFor") }
            
            peripheral.discoverCharacteristics([blueCharacteristic_RX_UUID, blueCharacteristic_TX_UUID, blueCharacteristic_MF_UUID], for: blueService)
            
            _ = try blueWaitSignal(group: "blePeripheral", name: "didDiscoverCharacteristicsFor")
            
            guard let rxCharacteristic: CBCharacteristic = blueService.characteristics?.first (where: { $0.uuid == blueCharacteristic_RX_UUID }) else {
                blueLogDebug("Unable to find Blue-Service Rx Characteristic with UUID \(blueCharacteristic_RX_UUID.uuidString)")
                throw BlueError(.bleCharacteristicNotFound)
            }
            
            guard let txCharacteristic: CBCharacteristic = blueService.characteristics?.first (where: { $0.uuid == blueCharacteristic_TX_UUID }) else {
                blueLogDebug("Unable to find Blue-Service Tx Characteristic with UUID \(blueCharacteristic_TX_UUID.uuidString)")
                throw BlueError(.bleCharacteristicNotFound)
            }
            
            guard let mfCharacteristic: CBCharacteristic = blueService.characteristics?.first (where: { $0.uuid == blueCharacteristic_MF_UUID }) else {
                blueLogDebug("Unable to find Blue-Service Mf Characteristic with UUID \(blueCharacteristic_MF_UUID.uuidString)")
                throw BlueError(.bleCharacteristicNotFound)
            }
            
            //
            // Enable notification on the Tx characteristic of the peripheral
            //
            
            try blueAddSignal(group: "blePeripheral", name: "didUpdateNotificationStateFor")
            
            defer { blueRemoveSignal(group: "blePeripheral", name: "didUpdateNotificationStateFor") }
            
            peripheral.setNotifyValue(true, for: txCharacteristic)
            
            _ = try blueWaitSignal(group: "blePeripheral", name: "didUpdateNotificationStateFor")
            
            if (!txCharacteristic.isNotifying) {
                blueLogError("Expected notify to be enabled on Tx Characteristic")
                throw BlueError(.bleFailSetCharacteristicNotify)
            }
            
            //
            // Assign characteristics
            //
            self.rxCharacteristic = rxCharacteristic
            self.txCharacteristic = txCharacteristic
            self.mfCharacteristic = mfCharacteristic
            
            try maybeUpdateManufacturerInfoFromCharacteristic()
            
            blueNotifyUpdatedDevice(self)
        } catch {
            do {
                try disconnect()
            } catch {
                // -- Ignored
            }
            
            throw error
        }
    }
    
    internal func notifyDisconnected() {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueSignalFailureGroup(group: "blePeripheral", error: BlueError(.disconnected))
        
        blueNotifyUpdatedDevice(self)
    }
    
    internal func updateRssi(_ rssi: Double) {
        rssiValues.append((rssi: rssi, scannedAt: Date()))
        
        // Purge old rssi values first
        let now = Date()
        
        for index in stride(from: rssiValues.count - 1, through: 0, by: -1) {
            let item = rssiValues[index]
            if now.timeIntervalSince(item.scannedAt) >= BlueDeviceBluetooth.maxRssiAgeInSeconds {
                rssiValues.remove(at: index)
            }
        }
        
        // Remove oldest entry if our array becomes too large
        if (rssiValues.count > 10) {
            rssiValues.removeFirst()
        }
        
        info.bluetooth.rssi = Int32(rssi)
        
        if (rssiValues.count > 1) {
            // Calculate the average rssi
            let sum = rssiValues.reduce(0.0) { $0 + $1.rssi }
            let averageRssi = sum / Double(rssiValues.count)
            
            // Calculate the standard deviation
            let variance = rssiValues.reduce(0, { $0 + pow($1.rssi - averageRssi, 2.0) }) / Double(rssiValues.count)
            let standardDeviation = sqrt(variance)
            
            // Filter out any rssi values that are more than one standard deviation away from the average
            let filteredRssiValues = rssiValues.filter { abs($0.rssi - averageRssi) <= standardDeviation }
            
            // Recalculate the average rssi with the filtered values
            let filteredSum = filteredRssiValues.reduce(0.0) { $0 + $1.rssi }
            
            // Finally assign the "real" average rssi
            info.bluetooth.rssi = Int32(filteredSum / Double(filteredRssiValues.count))
        }
        
        // Calculate our distance from the rssi now
        info.distanceMeters = 0
        
        if (info.bluetooth.txPower != 0 && info.bluetooth.rssi != 0) {
            let ratio = Float(info.bluetooth.rssi) / Float(info.bluetooth.txPower)
            if (ratio < 1.0) {
                info.distanceMeters = pow(ratio, 10)
            }
            else {
                info.distanceMeters = (0.89976) * pow(ratio, 7.7095) + 0.111
            }
        }
    }
    
    internal func updateFromAdvertisementData(advertisementData: [String : Any]) throws {
        lastSeenAt = Date()
        
        // Only refresh reading advertisement data on certain cicles otherwise
        // we'd end up reading the same data every few ms over and over again
        
        if let lastFullAdvertisementDataReadAt = lastFullAdvertisementDataReadAt {
            if (Date().timeIntervalSince(lastFullAdvertisementDataReadAt) < BlueDeviceBluetooth.maxAdvertisementDataAgeSeconds) {
                return
            }
        }
        
        //
        // Read tx-power
        //
        
        let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber
        
        if let txPower = txPower {
            self.info.bluetooth.txPower = txPower.int32Value
        }
        
        // Ignore reading adv data if not timed out
        if let lastFullAdvertisementDataReadAt = self.lastFullAdvertisementDataReadAt {
            if Date().timeIntervalSince(lastFullAdvertisementDataReadAt) < BlueDeviceBluetooth.maxAdvertisementDataAgeSeconds {
                return
            }
        }
        
        let mfData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        
        if let mfData = mfData, !mfData.isEmpty {
            if (mfData.count == BLUE_BLE_MANUFACTURER_DATA_IBEACON_SIZE + BLUE_BLE_MANUFACTURER_DATA_SIZE) {
                info.bluetooth.isIbeacon = Array(mfData.prefix(4)) == [0x4C, 0x00, 0x02, 0x15]
                
                // Extract the tx-power from the iBeacon data if none yet
                if (info.bluetooth.isIbeacon && info.bluetooth.txPower == 0) {
                    let txPowerI8 = Int(mfData[Int(BLUE_BLE_MANUFACTURER_DATA_IBEACON_SIZE - 1)]) - 256;
                    info.bluetooth.txPower = Int32(txPowerI8)
                }
                
                try updateFromManufacturerData(mfData.suffix(Int(BLUE_BLE_MANUFACTURER_DATA_SIZE)))
                
                lastFullAdvertisementDataReadAt = Date()
            } else if (mfData.count == BLUE_BLE_MANUFACTURER_DATA_INITIAL_SIZE + BLUE_BLE_MANUFACTURER_DATA_SIZE - BLUE_BLE_COMPANY_IDENTIFIER_SIZE) {
                info.bluetooth.isIbeacon = false
                
                //
                // CoreBluetooth actually returns our manufacturer data from adv and scan response packet
                // and combines them into one. However it seems to also trim away the company identifier from
                // the scan response packet when it equals the one from the adv packet. So we re-combine
                // both packet data into one valid, readable mf data data structure again
                //
                
                var tmpData = Data()
                
                // Company identifier from first packet
                tmpData.append(mfData.prefix(2))
                
                // Rest of scan response mf data
                tmpData.append(mfData.suffix(Int(BLUE_BLE_MANUFACTURER_DATA_SIZE - BLUE_BLE_COMPANY_IDENTIFIER_SIZE)))
                
                try updateFromManufacturerData(tmpData)
                
                lastFullAdvertisementDataReadAt = Date()
            }
        } else {
            // No data means we're sending as iBeacon so mark ourself
            info.bluetooth.isIbeacon = true
            lastFullAdvertisementDataReadAt = Date()
        }
    }
    
    private func maybeUpdateManufacturerInfoFromCharacteristic() throws {
        guard !info.hasManufacturerInfo, BlueDeviceBluetooth.readManufacturerInfoFromCharacteristic else {
            return
        }
        
        if let mfCharacteristic = self.mfCharacteristic {
            try blueAddSignal(group: "blePeripheral", name: "didUpdateValueFor")
            
            defer { blueRemoveSignal(group: "blePeripheral", name: "didUpdateValueFor") }
            
            peripheral.readValue(for: mfCharacteristic)
            
            if let mfData = try blueWaitSignal(group: "blePeripheral", name: "didUpdateValueFor", signalFromHistory: true) as? Data {
                try updateFromManufacturerData(mfData)
            }
        }
    }
    
    private func updateFromManufacturerData(_ mfData: Data) throws {
        guard !mfData.isEmpty else {
            return
        }
        
        var error: Error? = nil
        
        mfData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
            let mfDataPtr = bytes.bindMemory(to: UInt8.self).baseAddress
            
            do {
                self.info.manufacturerInfo = try blueClibFunctionOut({ (dataPtr, dataSize) in
                    return blueBle_ReadManufacturerData_Ext(mfDataPtr, UInt8(mfData.count), true, dataPtr, dataSize)
                })
                
                /*
                 if let hardwareType = manufacturerInfo?.hardwareType {
                 // TODO : Read additional advertisement info if any for specific hardware
                 }
                 */
                
                blueNotifyUpdatedDevice(self)
            } catch let e {
                error = e
            }
        }
        
        if let error = error {
            throw error
        }
    }
    
    internal override func disconnect() throws {
        dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
        
        blueLogDebug("Try to disconnect")
        
        try blueDisconnectBluetoothPeripheral(peripheral)
        
        // Remove all signals in case of disconnection, as some of them may not have been properly removed in the event of an abnormal disconnection, such as a timeout.
        if (peripheral.state == .disconnected) {
            blueRemoveSignal(group: "blePeripheral", name: "didUpdateValueFor")
            blueRemoveSignal(group: "blePeripheral", name: "didWriteValueFor")
        }
        
        blueNotifyUpdatedDevice(self)
    }
    
    internal override func getMaxFrameSize() -> UInt16 {
        return UInt16(mtuSize)
    }
    
    internal override func transmit(txData: Data) throws {
        dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
        
        guard let rxCharacteristic = rxCharacteristic else {
            throw BlueError(.invalidState)
        }
        
        if (peripheral.state != .connected) {
            throw BlueError(.invalidState)
        }
        
        if (BlueDeviceBluetooth.writeWithoutResponse) {
            blueDeviceQueue.async {
                self.peripheral.writeValue(txData, for: rxCharacteristic, type: .withoutResponse)
            }
            
            while (true) {
                if (self.peripheral.canSendWriteWithoutResponse) {
                    return
                }
            }
        } else {
            try blueAddSignal(group: "blePeripheral", name: "didWriteValueFor")
            
            defer { blueRemoveSignal(group: "blePeripheral", name: "didWriteValueFor") }
            
            blueDeviceQueue.async {
                self.peripheral.writeValue(txData, for: rxCharacteristic, type: .withResponse)
            }
            
            _ = try blueWaitSignal(group: "blePeripheral", name: "didWriteValueFor")
        }
    }
    
    internal override func receive() throws -> Data? {
        dispatchPrecondition(condition: .notOnQueue(blueDeviceQueue))
        
        try blueAddSignal(group: "blePeripheral", name: "didUpdateValueFor")
        
        defer { blueRemoveSignal(group: "blePeripheral", name: "didUpdateValueFor") }
        
        let rxData = try blueWaitSignal(group: "blePeripheral", name: "didUpdateValueFor", signalFromHistory: true)
        
        if let rxData = rxData as? Data {
            return rxData
        }
        
        return nil
    }
    
    //
    // CBPeripheral delegate methods
    //
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueLogDebug("peripheral.didDiscoverServices")
        
        if let error = error {
            blueSignalFailure(group: "blePeripheral", name: "didDiscoverServices", error: error)
        } else {
            blueSignalSuccess(group: "blePeripheral", name: "didDiscoverServices")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueLogDebug("peripheral.didDiscoverCharacteristicsFor")
        
        if let error = error {
            blueSignalFailure(group: "blePeripheral", name: "didDiscoverCharacteristicsFor", error: error)
        } else {
            blueSignalSuccess(group: "blePeripheral", name: "didDiscoverCharacteristicsFor")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueLogDebug("peripheral.didUpdateNotificationStateFor")
        
        if let error = error {
            blueSignalFailure(group: "blePeripheral", name: "didUpdateNotificationStateFor", error: error)
        } else {
            blueSignalSuccess(group: "blePeripheral", name: "didUpdateNotificationStateFor")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueLogDebug("peripheral.didUpdateValueFor")
        
        if let error = error {
            blueSignalFailure(group: "blePeripheral", name: "didUpdateValueFor", error: error)
        } else {
            blueSignalSuccess(group: "blePeripheral", name: "didUpdateValueFor", result: characteristic.value)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        dispatchPrecondition(condition: .onQueue(blueDeviceQueue))
        
        blueLogDebug("peripheral.didWriteValueFor")
        
        if let error = error {
            blueSignalFailure(group: "blePeripheral", name: "didWriteValueFor", error: error)
        } else {
            blueSignalSuccess(group: "blePeripheral", name: "didWriteValueFor", result: characteristic.value)
        }
    }
}

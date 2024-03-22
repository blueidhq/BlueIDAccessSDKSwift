import CoreBluetooth
import Foundation
import NordicDFU

/**
 * @class BlueDFUPeripheralService
 * A utility class for looking up peripherals that are advertising DFU service.
 */
internal class BlueDFUPeripheralService: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager? = nil
    private var discoveredPeripheral: CBPeripheral?
    private var continuation: CheckedContinuation<CBPeripheral, any Error>?
    
    /// Finds a peripheral that is advertising DFU service asynchronously within the specified timeout period.
    ///
    /// - parameter timeout: The duration in seconds to wait for the peripheral to be discovered. Default value is 10.0 seconds.
    /// - returns: A `CBPeripheral` object representing the DFU peripheral if found.
    /// - throws: An error of type `BlueError` if the timeout period elapses without finding the peripheral.
    func find(_ timeout: TimeInterval = 10.0) async throws -> CBPeripheral {
        if self.centralManager != nil {
            throw BlueError(.invalidState)
        }
        
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            self.startScan()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if self.discoveredPeripheral == nil {
                    continuation.resume(throwing: BlueError(.sdkTimeout))
                }
            }
        }
    }
    
    /// Destroys the BlueDFUPeripheralService instance, releasing any resources it holds.
    func destroy() {
        if let centralManager = centralManager {
            if centralManager.isScanning {
                centralManager.stopScan()
            }
            centralManager.delegate = nil
        }
    }
    
    /// Starts scanning for peripherals that are that are advertising DFU service.
    private func startScan() {
        if let centralManager = centralManager {
            if (centralManager.isScanning) {
                centralManager.stopScan()
            }
            
            if centralManager.state == .poweredOn {
                centralManager.scanForPeripherals(withServices: [DFUUuidHelper().secureDFUService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate API
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.discoveredPeripheral = peripheral
        self.continuation?.resume(returning: peripheral)
        self.destroy()
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.startScan()
    }
}

import Foundation

internal class BlueDevice: NSObject, BlueSPConnectionDelegate {
    internal var info = BlueDeviceInfo()
    
    internal var lastSeenAt = Date()
    
    internal var isConnected: Bool {
        get {
            return false
        }
    }
    
    internal var spConnection: BlueSPConnection!
    
    internal override init() {
        self.spConnection = BlueSPConnection()
        
        super.init()
        
        self.spConnection.delegate = self
    }
    
    internal func connect() throws {
        preconditionFailure("Not implemented")
    }
    
    internal func disconnect() throws {
        preconditionFailure("Not implemented")
    }
    
    //
    // BlueSPConnectionDelegate
    //
    
    internal func getMaxFrameSize() -> UInt16 {
        preconditionFailure("Not implemented")
    }
    
    internal func transmit(txData: Data) throws {
        preconditionFailure("Not implemented")
    }
    
    internal func receive() throws -> Data? {
        preconditionFailure("Not implemented")
    }
    
    internal func updateInfo(systemStatus: BlueSystemStatus) {
        info.manufacturerInfo.isFactory = !systemStatus.settings.timeWasSet
        info.manufacturerInfo.hardwareType = systemStatus.hardwareType
        info.manufacturerInfo.batteryLevel = systemStatus.batteryLevel
        info.manufacturerInfo.applicationVersion = systemStatus.applicationVersion
        
        blueNotifyUpdatedDevice(self)
    }
}

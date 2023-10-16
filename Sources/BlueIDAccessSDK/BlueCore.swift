import Foundation
import CBlueIDAccess

internal var blueIsInitialized = false

internal var blueDeviceQueue = DispatchQueue(label: "blueid.device", qos: .default, attributes: [])

public struct BlueInitializeCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        try run()
        return nil
    }
    
    public func run() throws -> Void {
        if (blueIsInitialized) {
            throw BlueError(.invalidState)
        }
        
        _ = try blueClibErrorCheck(blueCore_Init())
        blueIsInitialized = true
    }
}

public struct BlueReleaseCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        try run()
        return nil
    }
    
    public func run() throws -> Void {
        if (!blueIsInitialized) {
            throw BlueError(.invalidState)
        }
        
        _ = try blueClibErrorCheck(blueCore_Release())
        blueIsInitialized = false
    }
}

public struct BlueVersionInfoCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        let result: BlueVersionInfo = try run()
        return try blueCastResult(result)
    }
    
    public func run() throws -> BlueVersionInfo {
        return try blueClibFunctionOut({ (dataPtr, dataSize) in
            return blueCore_getVersionInfo_Ext(dataPtr, dataSize)
        })
    }
}

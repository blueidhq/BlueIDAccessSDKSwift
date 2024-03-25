import Foundation
import SwiftProtobuf

public class BlueAsyncTerminalCommand: BlueAsyncCommand {
    let action: String
    
    init(action: String) { self.action = action }
    
    internal func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        return try await runAsync(deviceID: try blueCastArg(String.self, arg0))
    }
    
    public func runAsync(deviceID: String) async throws {
        return try await blueTerminalRun(deviceID: deviceID, timeoutSeconds: 30.0, action: action)
    }
}

public class BlueClearBlacklistCommand: BlueAsyncTerminalCommand {
    init() { super.init(action: "BL_CLEAR") }
}

public class BlueClearEventLogCommand: BlueAsyncTerminalCommand {
    init() { super.init(action: "EV_CLEAR") }
}

public class BlueClearSystemLogCommand: BlueAsyncTerminalCommand {
    init() { super.init(action: "SL_CLEAR") }
}

public class BlueGetSystemStatusCommand: BlueSdkAsyncCommand {
    internal override func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        return try await runAsync(
            deviceID: try blueCastArg(String.self, arg0)
        )
    }
    
    public func runAsync(deviceID: String) async throws -> BlueSystemStatus {
        var status: BlueSystemStatus = try await blueTerminalRun(deviceID: deviceID, timeoutSeconds: 30.0, action: "STATUS")
        
        do {
            let credentials = try BlueGetAccessCredentialsCommand().run(credentialType: .maintenance, for: deviceID, includePrivateKey: true)
            
            if let credential = credentials.credentials.first {
                let tokenAuthentication = try await sdkService.authenticationTokenService
                    .getTokenAuthentication(credential: credential)
                
                let latestFW = try await self.sdkService.apiService.getLatestFirmware(deviceID: deviceID, with: tokenAuthentication).getData()
                
                self.updateFirmwareFlags(&status, latestFW)
            }
        } catch {
            blueLogError(error.localizedDescription)
        }
        
        return status
    }
    
    internal func updateFirmwareFlags(_ status: inout BlueSystemStatus, _ latestFW: BlueGetLatestFirmwareResult) {
        if let testFW = latestFW.test {
            if let testVersion = testFW.testVersion {
                status.newTestFirmwareVersionAvailable = testVersion != status.applicationVersionTest || testFW.version != status.applicationVersion
            }
        }
        
        if let productionFW = latestFW.production {
            let isTestVersion = status.hasApplicationVersionTest && status.applicationVersionTest != 0
            
            if isTestVersion {
                status.newFirmwareVersionAvailable = true
            } else {
                status.newFirmwareVersionAvailable = productionFW.version != status.applicationVersion
            }
        }
    }
}

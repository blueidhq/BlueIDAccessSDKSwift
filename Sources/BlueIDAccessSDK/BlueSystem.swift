import Foundation
import SwiftProtobuf

public class BlueAsyncTerminalCommand: BlueAsyncCommand {
    let action: String
    
    init(action: String) { self.action = action }
    
    internal func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        if #available(macOS 10.15, *) {
            return try await runAsync(deviceID: try blueCastArg(String.self, arg0))
        } else {
            throw BlueError(.unavailable)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(deviceID: String) async throws {
        return try await blueTerminalRun(deviceID: deviceID, timeoutSeconds: 30.0, action: action)
    }
}

public class BlueAsyncTerminalCommandWithResult<T>: BlueAsyncCommand where T: Message {
    let action: String
    
    init(action: String) { self.action = action }
    
    internal func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        if #available(macOS 10.15, *) {
            return try await runAsync(deviceID: try blueCastArg(String.self, arg0))
        } else {
            throw BlueError(.unavailable)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(deviceID: String) async throws -> T {
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

public class BlueGetSystemStatusCommand: BlueAsyncTerminalCommandWithResult<BlueSystemStatus> {
    init() { super.init(action: "STATUS") }
}

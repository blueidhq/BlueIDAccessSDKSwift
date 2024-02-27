import Foundation
import SwiftProtobuf

internal let blueAccessCredentialsKeyChain = BlueKeychain(attrService: "blueid.accessCredentials")
internal let blueAccessAuthenticationTokensKeyChain = BlueKeychain(attrService: "blueid.accessAuthenticationTokens")
internal let blueAccessDevicesStorage = BlueStorage(collection: "blueid.accessDevices")
internal let blueAccessOssSettingsKeyChain = BlueKeychain(attrService: "blueid.accessOssSettings")

public class BlueAddAccessCredentialCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(credential: try blueCastArg(BlueAccessCredential.self, arg0))
    }
    
    public func runAsync(credential: BlueAccessCredential) async throws -> Void {
        guard credential.hasPrivateKey else {
            throw BlueError(.sdkCredentialPrivateKeyNotFound)
        }
        
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: credential.jsonUTF8Data())
        
        try await BlueSynchronizeAccessCredentialCommand(self.blueAPI)
            .runAsync(credentialID: credential.credentialID.id)
        
        blueFireListeners(fireEvent: .accessCredentialAdded, data: nil)
    }
}

public class BlueClaimAccessCredentialCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(activationToken: try blueCastArg(String.self, arg0))
    }
    
    public func runAsync(activationToken: String) async throws -> Void {
        let credential = try await blueAPI!.claimAccessCredential(activationToken: activationToken).getData()
        
        try await BlueAddAccessCredentialCommand(self.blueAPI).runAsync(credential: credential)
    }
}

public struct BlueGetAccessCredentialsCommand: BlueAsyncCommand {
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        var credentialType: BlueCredentialType?
        
        if let rawValue = try blueCastArg(Int.self, arg0) {
            credentialType = BlueCredentialType(rawValue: rawValue)
        }
        
        return try await runAsync(
            credentialType: credentialType,
            for: blueCastArg(String.self, arg1),
            includePrivateKey: false
        )
    }
    
    public func runAsync(credentialType: BlueCredentialType? = nil, for deviceID: String? = nil, includePrivateKey: Bool? = false) async throws -> BlueAccessCredentialList {
        let filterByCredentialType = { (_ credential: BlueAccessCredential) -> Bool in
            guard let credentialType = credentialType else {
                return true
            }
            
            return credential.credentialType == credentialType
        }
        
        let filterByDeviceID = { (_ credential: BlueAccessCredential) -> Bool in
            guard let deviceID = deviceID else {
                return true
            }
            
            let deviceList = try BlueGetAccessDevicesCommand().run(credentialID: credential.credentialID.id)
            
            let device = deviceList.devices.first() { device in
                return device.deviceID == deviceID
            }
            
            return device != nil
        }
        
        var credentialList = BlueAccessCredentialList()
        
        if let entries = try blueAccessCredentialsKeyChain.getAllEntries() {
            credentialList.credentials = try entries.compactMap { entry in
                if var credential = try? BlueAccessCredential(jsonUTF8Data: entry) {
                    
                    if includePrivateKey != true {
                        // Never expose it
                        credential.clearPrivateKey()
                    }
                    
                    return credential
                }
                
                return nil
            }.filter() { credential in
                if (!filterByCredentialType(credential)) {
                    return false
                }
                
                if (try !filterByDeviceID(credential)) {
                    return false
                }
                
                return true
            }
        }
        
        return credentialList
    }
}

public struct BlueGetAccessDevicesCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try run(credentialID: try blueCastArg(String.self, arg0))
    }
    
    public func run(credentialID: String) throws -> BlueAccessDeviceList {
        if let data = blueAccessDevicesStorage.getEntry(id: credentialID) {
            return try BlueAccessDeviceList(jsonUTF8Data: data)
        }
        return BlueAccessDeviceList()
    }
}

public class BlueUpdateDeviceConfigurationCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        if #available(macOS 10.15, *) {
            return try await runAsync(
                credentialID: try blueCastArg(String.self, arg0),
                deviceID: try blueCastArg(String.self, arg1)
            )
        } else {
            throw BlueError(.sdkUnsupportedPlatform)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(credentialID: String, deviceID: String) async throws -> BlueSystemStatus? {
        guard let device = blueGetDevice(deviceID) else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tokenAuthentication = try await BlueAccessAPIHelper(blueAPI!)
            .getTokenAuthentication(credential: credential)
        
        let config = try await getBlueSystemConfig(deviceID: deviceID, with: tokenAuthentication)
        
        var update = BlueSystemUpdate()
        update.timeUnix = BlueSystemTimeUnix()
        update.timeUnix.epoch = UInt32(Date().timeIntervalSince1970)
        
        if let config = config {
            update.config = config
        }
        
        let updateStatus: BlueSystemStatus = try await blueTerminalRun(
            deviceID: deviceID,
            timeoutSeconds: 30.0,
            action: "UPDATE",
            data: update
        )
        
        device.updateInfo(systemStatus: updateStatus)
        
        await waitUntilDeviceHasBeenRestarted()
        
        try await pushEventLogs(status: updateStatus, credential: credential, deviceID: deviceID, with: tokenAuthentication)
        try await pushSystemLogs(status: updateStatus, deviceID: deviceID, with: tokenAuthentication)
        try await deployBlacklistEntries(deviceID: deviceID, with: tokenAuthentication)
        
        let status: BlueSystemStatus = await getSystemStatus(deviceID) ?? updateStatus
        
        try await pushDeviceSystemStatus(status: status, with: tokenAuthentication)
        
        return status
    }
    
    @available(macOS 10.15, *)
    private func waitUntilDeviceHasBeenRestarted() async {
        try? await Task.sleep(nanoseconds: UInt64(blueSecondsToNanoseconds(10)))
    }
    
    @available(macOS 10.15, *)
    private func getSystemStatus(_ deviceID: String) async -> BlueSystemStatus? {
        return try? await blueTerminalRun(
            deviceID: deviceID,
            timeoutSeconds: 30.0,
            action: "STATUS"
        )
    }
    
    @available(macOS 10.15, *)
    private func deployBlacklistEntries(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws {
        do {
            let response = try await blueAPI!.getBlacklistEntries(deviceID: deviceID, with: tokenAuthentication, limit: 50).getData()
            
            guard let data = Data(base64Encoded: response.blacklistEntries) else {
                return
            }
            
            let entries: BlueBlacklistEntries = try blueDecodeMessage(data)
            
            try await blueTerminalRun(
                deviceID: deviceID,
                timeoutSeconds: 30.0,
                action: "BL_PUSH",
                data: entries
            )
        } catch {
            throw BlueError(.sdkBlacklistEntriesDeployFailed, cause: error)
        }
    }
    
    private func getBlueSystemConfig(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueSystemConfig? {
        do {
            let result = try await blueAPI!.createDeviceConfiguration(deviceID: deviceID, with: tokenAuthentication).getData()
            
            guard let systemConfiguration = result.systemConfiguration else {
                return nil
            }
            
            guard let data = Data(base64Encoded: systemConfiguration) else {
                throw BlueError(.sdkDecodeBase64Failed)
            }
            
            let config: BlueSystemConfig = try blueDecodeMessage(data)
            
            return config
        } catch {
            throw BlueError(.sdkGetSystemConfigFailed, cause: error)
        }
    }
    
    private func pushDeviceSystemStatus(status: BlueSystemStatus, with tokenAuthentication: BlueTokenAuthentication) async throws {
        do {
            let result = try await blueAPI!.updateDeviceSystemStatus(systemStatus: blueEncodeMessage(status).base64EncodedString(), with: tokenAuthentication).getData()
            
            if (!result.updated) {
                blueLogWarn("System status could not be deployed")
            }
        } catch {
            throw BlueError(.sdkDeviceSystemStatusPushFailed, cause: error)
        }
    }
    
    @available(macOS 10.15, *)
    private func pushEventLogs(status: BlueSystemStatus, credential: BlueAccessCredential, deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws {
        do {
            guard status.settings.eventLogEntriesCount > 0 else {
                blueLogInfo("No event logs to be deployed")
                return
            }
            
            try await iterateEvents(
                sequenceID: status.settings.eventLogSequenceID,
                entriesCount: status.settings.eventLogEntriesCount,
                limit: 100
            ) { offset in
                
                var query = BlueEventLogQuery()
                query.maxCount = UInt32(40)
                
                // newest -> oldest
                query.sequenceID = UInt32(offset)
                
                let logResult: BlueEventLogResult = try await blueTerminalRun(
                    deviceID: deviceID,
                    timeoutSeconds: 30.0,
                    action: "EV_QUERY",
                    data: query
                )
                
                if (!logResult.events.isEmpty) {
                    let events = logResult.events.map{ BluePushEvent(event: $0, deviceId: deviceID) }
                    
                    let result = try await self.blueAPI!.pushEvents(events: events, with: tokenAuthentication).getData()
                    
                    if (result.storedEvents.count != events.count) {
                        blueLogWarn("Some event logs have not been deployed")
                    }
                }
                
                return logResult.events.count
            }
            
        } catch {
            throw BlueError(.sdkEventLogsPushFailed, cause: error)
        }
    }
    
    @available(macOS 10.15, *)
    private func pushSystemLogs(status: BlueSystemStatus, deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws {
        do {
            guard status.settings.systemLogEntriesCount > 0 else {
                blueLogInfo("No system log entries to be deployed")
                return
            }
            
            try await iterateEvents(
                sequenceID: status.settings.systemLogSequenceID,
                entriesCount: status.settings.systemLogEntriesCount,
                limit: 50
            ) { offset in
                
                var query = BlueSystemLogQuery()
                query.maxCount = UInt32(10)
                
                // newest -> oldest
                query.sequenceID = UInt32(max(1, Int(status.settings.systemLogSequenceID) - offset + 1))
                
                let logResult: BlueSystemLogResult = try await blueTerminalRun(
                    deviceID: deviceID,
                    timeoutSeconds: 30.0,
                    action: "SL_QUERY",
                    data: query
                )
                
                if (!logResult.entries.isEmpty) {
                    let logEntries = logResult.entries.map{ BluePushSystemLogEntry(logEntry: $0) }
                    
                    let result = try await self.blueAPI!.pushSystemLogs(deviceID: deviceID, logEntries: logEntries, with: tokenAuthentication).getData()
                    
                    if (result.storedLogEntries.count != logEntries.count) {
                        blueLogWarn("Some system log entries have not been deployed")
                    }
                }
                
                return logResult.entries.count
            }

        } catch {
            throw BlueError(.sdkSystemLogEntriesPushFailed, cause: error)
        }
    }
    
    private func iterateEvents(sequenceID: UInt32, entriesCount: UInt32, limit: Int, _ sendBatch: (_ offset: Int) async throws -> Int) async throws {
        var sent = 0
        var offset = max(1, Int(sequenceID) - limit)
        
        repeat {
            let entriesSent = try await sendBatch(offset)
            
            offset += entriesSent
            sent += entriesSent
            
        } while (sent < limit && offset < entriesCount)
    }
}

public class BlueGetAccessObjectsCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: try blueCastArg(String.self, arg0)
        )
    }
    
    public func runAsync(credentialID: String) async throws -> BlueAccessObjectList {
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tokenAuthentication = try await BlueAccessAPIHelper(blueAPI!)
            .getTokenAuthentication(credential: credential)
        
        let objects = try await blueAPI!.getAccessObjects(with: tokenAuthentication).getData()
        
        return BlueAccessObjectList(objects: objects)
    }
}

public struct BlueListAccessDevicesCommand: BlueAsyncCommand {
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        let credentialTypeRawValue: Int? = try blueCastArg(Int.self, arg0)
        var credentialType: BlueCredentialType? = nil
        
        if let credentialTypeRawValue = credentialTypeRawValue {
            credentialType = BlueCredentialType(rawValue: credentialTypeRawValue)
        }
        
        return try await runAsync(credentialType: credentialType)
    }
    
    public func runAsync(credentialType: BlueCredentialType? = nil) async throws -> BlueAccessDeviceList {
        let credentialList = try await BlueGetAccessCredentialsCommand().runAsync(credentialType: credentialType)
        
        let devices = credentialList.credentials.compactMap { credential in
            let deviceList = try? BlueGetAccessDevicesCommand().run(credentialID: credential.credentialID.id)
            
            return deviceList?.devices
        }.flatMap{ $0 }
        
        let uniqueDevices = Array(Set(devices)).sorted(by: { (firstDevice, secondDevice) -> Bool in
            return firstDevice.deviceID < secondDevice.deviceID
        })
        
        return BlueAccessDeviceList(devices: uniqueDevices)
    }
}

public class BlueClaimAccessDeviceCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        if #available(macOS 10.15, *) {
            return try await runAsync(
                credentialID: try blueCastArg(String.self, arg0),
                deviceID: try blueCastArg(String.self, arg1),
                objectID: try blueCastArg(String.self, arg2)
            )
        } else {
            throw BlueError(.sdkUnsupportedPlatform)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(credentialID: String, deviceID: String, objectID: String) async throws -> BlueSystemStatus? {
        guard let _ = blueGetDevice(deviceID) else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tokenAuthentication = try await BlueAccessAPIHelper(blueAPI!)
            .getTokenAuthentication(credential: credential)
        
        _ = try await blueAPI!.claimDevice(deviceID: deviceID, objectID: objectID, with: tokenAuthentication).getData()
        
        try await BlueSynchronizeMobileAccessCommand(self.blueAPI).runAsync(credentialID: credential.credentialID.id)
        
        let status = try await BlueUpdateDeviceConfigurationCommand(self.blueAPI).runAsync(credentialID: credential.credentialID.id, deviceID: deviceID)
        
        blueFireListeners(fireEvent: .accessDeviceClaimed, data: nil)
        
        return status
    }
}

public class BlueGetWritableAccessCredentialsCommand: BlueAPIAsyncCommand {
    override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            organisation: blueCastArg(String.self, arg0),
            siteID: blueCastArg(Int.self, arg1)
        )
    }
    
    public func runAsync(organisation: String, siteID: Int) async throws -> BlueAccessCredentialList {
        guard let credential = blueGetAccessCredential(organisation: organisation, siteID: siteID, credentialType: .nfcWriter) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tokenAuthentication = try await BlueAccessAPIHelper(blueAPI!)
            .getTokenAuthentication(credential: credential)
        
        let credentials = try await blueAPI!.getAccessCredentials(with: tokenAuthentication).getData()
        
        return BlueAccessCredentialList(credentials: credentials)
    }
}

public struct BlueClearDataCommand: BlueCommand {
    func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any? {
        return run()
    }
    
    public func run() {
        _ = try? blueAccessCredentialsKeyChain.deleteAllEntries()
        _ = try? blueAccessAuthenticationTokensKeyChain.deleteAllEntries()
        _ = try? blueAccessOssSettingsKeyChain.deleteAllEntries()
        _ = try? blueTerminalPublicKeysKeychain.deleteAllEntries()
        _ = try? blueTerminalRequestDataKeychain.deleteAllEntries()
        
        blueAccessDevicesStorage.deleteAllEntries()
    }
}

internal typealias BlueTerminalRunClosure = (
    _ deviceID: String,
    _ timeoutSeconds: Double,
    _ action: String
) async throws -> BlueOssAccessResult

public struct BlueTryAccessDeviceCommand: BlueAsyncCommand {
    private let terminalRun: BlueTerminalRunClosure?
    
    init(using terminalRun: BlueTerminalRunClosure? = nil) {
        if #available(macOS 10.15, *) {
            self.terminalRun = terminalRun ?? blueTerminalRun
        } else {
            self.terminalRun = nil
        }
    }
    
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(deviceID: blueCastArg(String.self, arg0))
    }
    
    /// Try to open/unlock the device via OssSo or OssSid command.
    /// A modal view (sheet) is shown in iOS to represent the progress of the command execution.
    ///
    /// - parameter deviceID: The Device ID.
    /// - throws: Throws an error of type `BlueError(.invalidState)` if the device could not be found.
    /// - throws: Throws an error of type `BlueError(.notFound)` if neither an OssSo nor an OssSid token is found.
    /// - throws: Throws an error of type `BlueError(.notSuported)` If the macOS version is earlier than 10.15.
    public func runAsync(deviceID: String) async throws -> BlueOssAccessResult {
        guard let device = blueGetDevice(deviceID) else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
        let hasOssSoToken = blueHasSpTokenForAction(device: device, action: "ossSoMobile")
        let hasOssSidToken = blueHasSpTokenForAction(device: device, action: "ossSidMobile")
        
        if (!hasOssSoToken && !hasOssSidToken) {
            throw BlueError(.sdkSpTokenNotFound)
        }
        
        let tryOssAccess: () async throws -> BlueOssAccessResult = {
            guard #available(macOS 10.15, *) else {
                throw BlueError(.sdkUnsupportedPlatform)
            }
            
            guard let terminalRun = self.terminalRun else {
                throw BlueError(.sdkUnsupportedPlatform)
            }
            
            if (hasOssSoToken) {
                return try await terminalRun(deviceID, defaultTimeoutSec, "ossSoMobile")
            }
            
            if (hasOssSidToken) {
                return try await terminalRun(deviceID, defaultTimeoutSec, "ossSidMobile")
            }
            
            throw BlueError(.sdkSpTokenNotFound)
        }
        
#if os(iOS) || os(watchOS)
        return try await blueShowAccessDeviceModal {
            return try await tryOssAccess()
        }
#else
        return try await tryOssAccess()
#endif
    }
}

internal func blueGetAccessCredential(credentialID: String) -> BlueAccessCredential? {
    if let entry = try? blueAccessCredentialsKeyChain.getEntry(id: credentialID) {
        return try? BlueAccessCredential(jsonUTF8Data: entry)
    }
    
    return nil
}

internal func blueGetAccessCredential(organisation: String, siteID: Int, credentialType: BlueCredentialType) -> BlueAccessCredential? {
    guard let entries = try? blueAccessCredentialsKeyChain.getAllEntries() else {
        return nil
    }
    
    let condition: (Data) -> Bool = { entry in
        if let credential = try? BlueAccessCredential(jsonUTF8Data: entry) {
            return credential.credentialType == credentialType && credential.organisation == organisation && credential.siteID == siteID
        }
        return false
    }
    
    guard let entry = entries.first(where: condition) else {
        return nil
    }
    
    return try? BlueAccessCredential(jsonUTF8Data: entry)
}

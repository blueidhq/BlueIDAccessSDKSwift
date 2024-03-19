import Foundation
import Combine
import SwiftProtobuf

internal let blueAccessCredentialsKeyChain = BlueKeychain(attrService: "blueid.accessCredentials")
internal let blueAccessAuthenticationTokensKeyChain = BlueKeychain(attrService: "blueid.accessAuthenticationTokens")
internal let blueAccessDevicesStorage = BlueStorage(collection: "blueid.accessDevices")
internal let blueAccessOssSettingsKeyChain = BlueKeychain(attrService: "blueid.accessOssSettings")

// TODO: Split into separate files

public class BlueAddAccessCredentialCommand: BlueSdkAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(credential: try blueCastArg(BlueAccessCredential.self, arg0))
    }
    
    public func runAsync(credential: BlueAccessCredential) async throws -> Void {
        guard credential.hasPrivateKey else {
            throw BlueError(.sdkCredentialPrivateKeyNotFound)
        }
        
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: credential.jsonUTF8Data())
        
        try await BlueSynchronizeAccessCredentialCommand(sdkService)
            .runAsync(credentialID: credential.credentialID.id)
        
        blueFireListeners(fireEvent: .accessCredentialAdded, data: nil)
    }
}

public class BlueClaimAccessCredentialCommand: BlueSdkAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(activationToken: try blueCastArg(String.self, arg0))
    }
    
    public func runAsync(activationToken: String) async throws -> Void {
        let credential = try await sdkService.apiService.claimAccessCredential(activationToken: activationToken).getData()
        
        try await BlueAddAccessCredentialCommand(sdkService).runAsync(credential: credential)
    }
}

public struct BlueGetAccessCredentialsCommand: BlueCommand {
    func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any? {
        var credentialType: BlueCredentialType?
        
        if let rawValue = try blueCastArg(Int.self, arg0) {
            credentialType = BlueCredentialType(rawValue: rawValue)
        }
        
        return try run(
            credentialType: credentialType,
            for: blueCastArg(String.self, arg1),
            includePrivateKey: false
        )
    }
    
    public func run(credentialType: BlueCredentialType? = nil, for deviceID: String? = nil, includePrivateKey: Bool? = false) throws -> BlueAccessCredentialList {
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
                do {
                    var credential = try BlueAccessCredential(jsonUTF8Data: entry)
                    
                    if includePrivateKey != true {
                        // Never expose it
                        credential.clearPrivateKey()
                    }
                    
                    return credential
                    
                } catch {
                    throw BlueError(.sdkDecodeJsonFailed, cause: error, detail: String(data: entry, encoding: .utf8))
                }

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

public class BlueSynchronizeAccessDeviceCommand: BlueSdkAsyncCommand {
    public enum BlueSynchronizeAccessTaskId {
        case getAuthenticationToken
        case getDeviceConfig
        case updateDeviceConfig
        case updateDeviceTime
        case waitForRestart
        case pushEventLogs
        case pushSystemLogs
        case getBlacklistEntries
        case deployBlacklistEntries
        case getSystemStatus
        case pushSystemStatus
    }
    
    internal override func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        return try await runAsync(
            credentialID: try blueCastArg(String.self, arg0),
            deviceID: try blueCastArg(String.self, arg1),
            showModal: try blueCastArg(Bool.self, arg2)
        )
    }
    
    public func runAsync(credentialID: String, deviceID: String, showModal: Bool? = false) async throws -> BlueSystemStatus? {
        guard let device = blueGetDevice(deviceID) else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tasks = [
            BlueTask(
                id: BlueSynchronizeAccessTaskId.getAuthenticationToken,
                label: blueI18n.syncDeviceGetAuthenticationTokenTaskLabel
            ) { _ in
                .result(try await self.getAuthenticationToken(credential))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.getDeviceConfig,
                label: blueI18n.syncDeviceRetrieveDeviceConfigurationTaskLabel
            ) { runner in
                let tokenAuthentication: BlueTokenAuthentication = try runner.getResult(BlueSynchronizeAccessTaskId.getAuthenticationToken)
                
                return .result(try await self.getBlueSystemConfig(deviceID: deviceID, with: tokenAuthentication))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.updateDeviceConfig,
                label: blueI18n.syncDeviceUpdateDeviceConfigurationTaskLabel
            ) { runner in
                let config: BlueSystemConfig? = try runner.getResult(BlueSynchronizeAccessTaskId.getDeviceConfig)
                
                let status: BlueSystemStatus = try await self.updateDevice(deviceID, config)
                
                device.updateInfo(systemStatus: status)
                
                return .resultWithStatus(status, config == nil ? .skipped: .succeeded)
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.updateDeviceTime,
                label: blueI18n.syncDeviceUpdateDeviceTimeTaskLabel
            ) { runner in
                let status: BlueSystemStatus = try runner.getResult(BlueSynchronizeAccessTaskId.updateDeviceConfig)
                
                return .resultWithStatus(nil, status.settings.timeWasSet == true ? .succeeded : .skipped)
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.waitForRestart,
                label: blueI18n.syncDeviceWaitForDeviceToRestartTaskLabel
            ) { _ in
                .result(try await self.waitUntilDeviceHasBeenRestarted(deviceID))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.pushEventLogs,
                label: blueI18n.syncDevicePushEventLogsTaskLabel,
                failable: true
            ) { runner in                
                let tokenAuthentication: BlueTokenAuthentication = try runner.getResult(BlueSynchronizeAccessTaskId.getAuthenticationToken)
                let status: BlueSystemStatus = try runner.getResult(BlueSynchronizeAccessTaskId.updateDeviceConfig)
                
                return .result(try await self.pushEventLogs(status: status, credential: credential, deviceID: deviceID, with: tokenAuthentication))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.pushSystemLogs,
                label: blueI18n.syncDevicePushSystemLogsTaskLabel,
                failable: true
            ) { runner in
                let tokenAuthentication: BlueTokenAuthentication = try runner.getResult(BlueSynchronizeAccessTaskId.getAuthenticationToken)
                let status: BlueSystemStatus = try runner.getResult(BlueSynchronizeAccessTaskId.updateDeviceConfig)
                
                return .result(try await self.pushSystemLogs(status: status, deviceID: deviceID, with: tokenAuthentication))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.getBlacklistEntries,
                label: blueI18n.syncDeviceRetrieveBlacklistEntriesTaskLabel,
                failable: true
            ) { runner in
                let tokenAuthentication: BlueTokenAuthentication = try runner.getResult(BlueSynchronizeAccessTaskId.getAuthenticationToken)
                
                return .result(try await self.getBlacklistEntries(deviceID, tokenAuthentication))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.deployBlacklistEntries,
                label: blueI18n.syncDeviceDeployBlacklistEntriesTaskLabel,
                failable: true
            ) { runner in
                let entries: BlueBlacklistEntries? = try runner.getResult(BlueSynchronizeAccessTaskId.getBlacklistEntries)
                
                guard let entries = entries else {
                    return .resultWithStatus(nil, .failed)
                }
                
                return .result(try await self.deployBlacklistEntries(deviceID, entries))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.getSystemStatus,
                label: blueI18n.syncDeviceRetrieveSystemStatusTaskLabel
            ) { _ in
                .result(try await self.getSystemStatus(deviceID))
            },
            
            BlueTask(
                id: BlueSynchronizeAccessTaskId.pushSystemStatus,
                label: blueI18n.syncDevicePushSystemStatusTaskLabel
            ) { runner in
                let tokenAuthentication: BlueTokenAuthentication = try runner.getResult(BlueSynchronizeAccessTaskId.getAuthenticationToken)
                let status: BlueSystemStatus = try runner.getResult(BlueSynchronizeAccessTaskId.getSystemStatus)
                
                try await self.pushDeviceSystemStatus(status: status, with: tokenAuthentication)
                
                return .result(status)
            }
        ]
        
        let runner = BlueSerialTaskRunner(tasks)
        
#if os(iOS) || os(watchOS)
        if (showModal == true) {
            try await blueShowSynchronizeAccessDeviceModal(runner)
        } else {
            try await runner.execute(true)
        }
#else
        try await runner.execute(true)
#endif
        
        if runner.isSuccessful() {
            return try runner.getResult(BlueSynchronizeAccessTaskId.pushSystemStatus)
        }
        
        return nil
    }
    
    private func updateDevice(_ deviceID: String, _ config: BlueSystemConfig?) async throws -> BlueSystemStatus {
        do {
            var update = BlueSystemUpdate()
            update.timeUnix = BlueSystemTimeUnix()
            update.timeUnix.epoch = UInt32(Date().timeIntervalSince1970)
            
            if let config = config {
                update.config = config
            }
            
            return try await blueTerminalRun(
                deviceID: deviceID,
                timeoutSeconds: 30.0,
                action: "UPDATE",
                data: update
            )
        } catch {
            throw BlueError(.sdkUpdateDeviceFailed, cause: error)
        }
    }
    
    private func getAuthenticationToken(_ credential: BlueAccessCredential) async throws -> BlueTokenAuthentication {
        do {
            return try await sdkService.authenticationTokenService
                .getTokenAuthentication(credential: credential)
        } catch {
            throw BlueError(.sdkGetAuthenticationTokenFailed, cause: error)
        }
    }
    
    private func waitUntilDeviceHasBeenRestarted(_ deviceID: String) async throws {
        do {
            var attempts = 0
            
            while attempts <= 2 {
                try? await Task.sleep(nanoseconds: UInt64(blueSecondsToNanoseconds(10)))
                
                if blueGetDevice(deviceID) != nil {
                    return
                }
                
                attempts += 1
            }
            
            throw BlueError(.sdkDeviceNotFound)
        } catch {
            throw BlueError(.sdkWaitDeviceToRestartFailed, cause: error)
        }
    }
    
    private func getSystemStatus(_ deviceID: String) async throws -> BlueSystemStatus {
        do {
            return try await blueTerminalRun(
                deviceID: deviceID,
                timeoutSeconds: 30.0,
                action: "STATUS"
            )
        } catch {
            throw BlueError(.sdkGetSystemStatusFailed, cause: error)
        }
    }
    
    private func getBlacklistEntries(_ deviceID: String, _ tokenAuthentication: BlueTokenAuthentication) async throws -> BlueBlacklistEntries {
        do {
            let response = try await sdkService.apiService.getBlacklistEntries(deviceID: deviceID, with: tokenAuthentication, limit: 50).getData()
            
            guard let data = Data(base64Encoded: response.blacklistEntries) else {
                throw BlueError(.sdkDecodeBase64Failed)
            }
            
            return try blueDecodeMessage(data)
        } catch {
            throw BlueError(.sdkGetBlacklistEntriesFailed, cause: error)
        }
    }
    
    private func deployBlacklistEntries(_ deviceID: String, _ entries: BlueBlacklistEntries) async throws {
        do {
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
            let result = try await sdkService.apiService.createDeviceConfiguration(deviceID: deviceID, with: tokenAuthentication).getData()
            
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
            let result = try await sdkService.apiService.updateDeviceSystemStatus(systemStatus: blueEncodeMessage(status).base64EncodedString(), with: tokenAuthentication).getData()
            
            if (!result.updated) {
                blueLogWarn("System status could not be deployed")
            }
        } catch {
            throw BlueError(.sdkDeviceSystemStatusPushFailed, cause: error)
        }
    }
    
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
                    
                    let result = try await sdkService.apiService.pushEvents(events: events, with: tokenAuthentication).getData()
                    
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
                    
                    let result = try await sdkService.apiService.pushSystemLogs(deviceID: deviceID, logEntries: logEntries, with: tokenAuthentication).getData()
                    
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

public class BlueGetAccessObjectsCommand: BlueSdkAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: try blueCastArg(String.self, arg0)
        )
    }
    
    public func runAsync(credentialID: String) async throws -> BlueAccessObjectList {
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tokenAuthentication = try await sdkService.authenticationTokenService
            .getTokenAuthentication(credential: credential)
        
        let objects = try await sdkService.apiService.getAccessObjects(with: tokenAuthentication).getData()
        
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
        
        return try await runAsync(
            credentialType: credentialType,
            suppressCredentialValidityStart: blueCastArg(Bool.self, arg1)
        )
    }
    
    public func runAsync(credentialType: BlueCredentialType? = nil, suppressCredentialValidityStart: Bool? = false) async throws -> BlueAccessDeviceList {
        let credentialList = try BlueGetAccessCredentialsCommand().run(credentialType: credentialType)
        
        let devices = credentialList.credentials.compactMap { credential in
            
            if (suppressCredentialValidityStart != true) {
                if (!credential.checkValidityStart()) {
                    return [BlueAccessDevice]()
                }
            }
            
            let deviceList = try? BlueGetAccessDevicesCommand().run(credentialID: credential.credentialID.id)
            
            return deviceList?.devices
        }.flatMap{ $0 }
        
        let uniqueDevices = Array(Set(devices)).sorted(by: { (firstDevice, secondDevice) -> Bool in
            return firstDevice.deviceID < secondDevice.deviceID
        })
        
        return BlueAccessDeviceList(devices: uniqueDevices)
    }
}

public class BlueClaimAccessDeviceCommand: BlueSdkAsyncCommand {
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

    public func runAsync(credentialID: String, deviceID: String, objectID: String) async throws -> BlueSystemStatus? {
        guard let _ = blueGetDevice(deviceID) else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let tokenAuthentication = try await sdkService.authenticationTokenService
            .getTokenAuthentication(credential: credential)
        
        _ = try await sdkService.apiService.claimDevice(deviceID: deviceID, objectID: objectID, with: tokenAuthentication).getData()
        
        try await BlueSynchronizeMobileAccessCommand(sdkService).runAsync(credentialID: credential.credentialID.id)
        
        let status = try await BlueSynchronizeAccessDeviceCommand(sdkService).runAsync(credentialID: credential.credentialID.id, deviceID: deviceID)
        
        blueFireListeners(fireEvent: .accessDeviceClaimed, data: nil)
        
        return status
    }
}

public class BlueGetWritableAccessCredentialsCommand: BlueSdkAsyncCommand {
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
        
        let tokenAuthentication = try await sdkService.authenticationTokenService
            .getTokenAuthentication(credential: credential)
        
        let credentials = try await sdkService.apiService.getAccessCredentials(with: tokenAuthentication).getData()
        
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

protocol BlueTerminalRunProtocol {
    func runOssSoMobile(deviceID: String) async throws -> BlueOssAccessEventsResult
    func runOssSidMobile(deviceID: String) async throws -> BlueOssAccessResult
}

internal class BlueTerminalRunImplementation: BlueTerminalRunProtocol {
    func runOssSoMobile(deviceID: String) async throws -> BlueOssAccessEventsResult {
        return try await blueTerminalRun(deviceID: deviceID, action: "ossSoMobile")
    }
    
    func runOssSidMobile(deviceID: String) async throws -> BlueOssAccessResult {
        return try await blueTerminalRun(deviceID: deviceID, action: "ossSidMobile")
    }
}

public class BlueTryAccessDeviceCommand: BlueSdkAsyncCommand {
    private let terminalRun: BlueTerminalRunProtocol
    
    init(_ sdkService: BlueSdkService, using terminalRun: BlueTerminalRunProtocol? = nil) {
        self.terminalRun = terminalRun ?? BlueTerminalRunImplementation()
        
        super.init(sdkService)
    }
    
    override internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(deviceID: blueCastArg(String.self, arg0))
    }
    
    /// Try to open/unlock the device via OssSo or OssSid command.
    /// A modal view (sheet) is shown in iOS to represent the progress of the command execution.
    ///
    /// - parameter deviceID: The Device ID.
    /// - throws: Throws an error of type `BlueError(.sdkDeviceNotFound)` if the device could not be found.
    /// - throws: Throws an error of type `BlueError(.sdkSpTokenNotFound)` if neither an OssSo nor an OssSid token is found.
    public func runAsync(deviceID: String) async throws -> BlueOssAccessResult {
        guard let device = blueGetDevice(deviceID) else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
#if os(iOS) || os(watchOS)
        return try await blueShowAccessDeviceModal {
            return try await self.tryOssAccess(device)
        }
#else
        return try await tryOssAccess(device)
#endif
    }
    
    private func tryOssAccess(_ device: BlueDevice) async throws -> BlueOssAccessResult {
        let hasOssSoToken = blueHasSpTokenForAction(device: device, action: "ossSoMobile")
        let hasOssSidToken = blueHasSpTokenForAction(device: device, action: "ossSidMobile")
        
        if (hasOssSoToken) {
            let accessResult = try await terminalRun.runOssSoMobile(deviceID: device.info.deviceID)
        
            if (!accessResult.events.isEmpty) {
                pushEvents(device: device, events: accessResult.events)
            }
            
            return accessResult.accessResult
        }
        
        if (hasOssSidToken) {
            return try await terminalRun.runOssSidMobile(deviceID: device.info.deviceID)
        }
        
        throw BlueError(.sdkSpTokenNotFound)
    }
    
    private func pushEvents(device: BlueDevice, events: [BlueEvent]) {
        do {
            let token = try blueGetSpTokenForAction(device: device, action: "ossSoMobile", data: nil)
            
            let credentialID = String(data: token.ossSo.infoFile.subdata(in: 3..<13), encoding: .utf8) ?? ""
            
            sdkService.eventService.pushEvents(
                credentialID,
                events.map { BluePushEvent(event: $0, deviceId: device.info.deviceID) }
            )
        } catch {
            blueLogError(error.localizedDescription)
        }
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

import Foundation
import SwiftProtobuf

internal let blueAccessCredentialsKeyChain = BlueKeychain(attrService: "blueid.accessCredentials")
internal let blueAccessAuthenticationTokensKeyChain = BlueKeychain(attrService: "blueid.accessAuthenticationTokens")
internal let blueAccessDevicesStorage = BlueStorage(collection: "blueid.accessDevices")
internal let blueAccessOssSettingsKeyChain = BlueKeychain(attrService: "blueid.accessOssSettings")

public class BlueAPIAsyncCommand: BlueAsyncCommand {
    internal let blueAPI: BlueAPIProtocol?
    
    init(_ blueAPI: BlueAPIProtocol? = nil) {
        if #available(macOS 12.0, *) {
            self.blueAPI = blueAPI ?? BlueAPI()
        } else {
            self.blueAPI = nil
        }
    }
    
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        fatalError("not implemented")
    }
    
    internal func getTokenAuthentication(credential: BlueAccessCredential, refreshToken: Bool) async throws -> BlueTokenAuthentication {
        let token = try await getAccessToken(credential: credential, refreshToken: refreshToken)
        
        guard let inputData = token.token.data(using: .utf8) else {
            throw BlueError(.invalidState)
        }
        
        guard let signature = try createSignature(inputData: inputData, privateKey: credential.privateKey) else {
            throw BlueError(.invalidSignature)
        }
        
        let tokenAuthentication = BlueTokenAuthentication(
            token: token.token,
            signature: signature.base64EncodedString()
        )
        
        return tokenAuthentication
    }
    
    internal func getAccessToken(credential: BlueAccessCredential, refreshToken: Bool) async throws -> BlueAccessToken {
        if (!refreshToken) {
            if let accessToken: BlueAccessToken = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id) {
                let expiresAt = Date(timeIntervalSince1970: TimeInterval(accessToken.expiresAt) / 1000.0)
                let isExpired = expiresAt < Date()
                
                if (!isExpired) {
                    return accessToken
                }
            }
        }
        
        let accessToken: BlueAccessToken = try await self.blueAPI!.getAccessToken(credentialId: credential.credentialID.id).getData()
        
        self.storeAccessToken(credential: credential, accessToken: accessToken)
        
        return accessToken
    }
    
    private func storeAccessToken(credential: BlueAccessCredential, accessToken: BlueAccessToken) {
        do {
            try? blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: accessToken)
        }
    }
}

public class BlueAddAccessCredentialCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(credential: try blueCastArg(BlueAccessCredential.self, arg0))
    }
    
    public func runAsync(credential: BlueAccessCredential) async throws -> Void {
        guard credential.hasPrivateKey else {
            throw BlueError(.invalidState)
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
            for: blueCastArg(String.self, arg1)
        )
    }
    
    public func runAsync(credentialType: BlueCredentialType? = nil, for deviceID: String? = nil) async throws -> BlueAccessCredentialList {
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
                    
                    // Never expose it
                    credential.clearPrivateKey()
                    
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
            throw BlueError(.unavailable)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(credentialID: String, deviceID: String) async throws -> BlueSystemStatus? {
        guard let device = blueGetDevice(deviceID) else {
            throw BlueError(.invalidState)
        }
        
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.notFound)
        }
        
        let tokenAuthentication = try await getTokenAuthentication(credential: credential, refreshToken: false)
        
        let config = await getBlueSystemConfig(deviceID: deviceID, with: tokenAuthentication)
        
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
        
        await pushEventLogs(status: updateStatus, credential: credential, deviceID: deviceID, with: tokenAuthentication)
        await pushSystemLogs(status: updateStatus, deviceID: deviceID, with: tokenAuthentication)
        await deployBlacklistEntries(deviceID: deviceID, with: tokenAuthentication)
        
        let status: BlueSystemStatus = await getSystemStatus(deviceID) ?? updateStatus
        
        await pushDeviceSystemStatus(status: status, with: tokenAuthentication)
        
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
    private func deployBlacklistEntries(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async {
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
            blueLogError(error.localizedDescription)
        }
    }
    
    private func getBlueSystemConfig(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async -> BlueSystemConfig? {
        do {
            let result = try await blueAPI!.createDeviceConfiguration(deviceID: deviceID, with: tokenAuthentication).getData()
            
            guard let systemConfiguration = result.systemConfiguration else {
                return nil
            }
            
            guard let data = Data(base64Encoded: systemConfiguration) else {
                return nil
            }
            
            let config: BlueSystemConfig = try blueDecodeMessage(data)
            
            return config
        } catch {
            blueLogError(error.localizedDescription)
        }
        
        return nil
    }
    
    private func pushDeviceSystemStatus(status: BlueSystemStatus, with tokenAuthentication: BlueTokenAuthentication) async {
        do {
            let result = try await blueAPI!.updateDeviceSystemStatus(systemStatus: blueEncodeMessage(status).base64EncodedString(), with: tokenAuthentication).getData()
            
            if (!result.updated) {
                blueLogWarn("System status could not be deployed")
            }
        } catch {
            blueLogError(error.localizedDescription)
        }
    }
    
    @available(macOS 10.15, *)
    private func pushEventLogs(status: BlueSystemStatus, credential: BlueAccessCredential, deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async {
        do {
            let deviceList = try BlueGetAccessDevicesCommand().run(credentialID: credential.credentialID.id)
            guard let device = deviceList.devices.first(where: { $0.deviceID == deviceID }) else {
                blueLogWarn("Device could not be found. Event logs have not been deployed")
                return
            }
            
            guard status.settings.eventLogEntriesCount > 0 else {
                blueLogWarn("No event logs to be deployed")
                return
            }
            
            let limit = 50
            
            let pushEvents = { (_ offset: Int) in
                var query = BlueEventLogQuery()
                query.maxCount = UInt32(limit)
                
                // newest -> oldest
                query.sequenceID = UInt32(max(1, Int(status.settings.eventLogSequenceID) - offset + 1))
                
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
                
                return logResult
            }
            
            var sent = 0
            var offset = 0
            
            repeat {
                offset += limit
                
                let logResult = try await pushEvents(offset)
                if (logResult.events.count < limit) {
                    break
                }
                
                sent += logResult.events.count
                
            } while (sent < 100 && sent < status.settings.eventLogEntriesCount)
            
        } catch {
            blueLogError(error.localizedDescription)
        }
    }
    
    @available(macOS 10.15, *)
    private func pushSystemLogs(status: BlueSystemStatus, deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async {
        do {
            let limit = 10
            
            let pushEvents = { (_ offset: Int) in
                var query = BlueSystemLogQuery()
                query.maxCount = UInt32(limit)
                
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
                
                return logResult
            }
            
            var sent = 0
            var offset = 0
            
            repeat {
                offset += limit
                
                let logResult = try await pushEvents(offset)
                if (logResult.entries.count < limit) {
                    break
                }
                
                sent += logResult.entries.count
                
            } while (sent < 50 && sent < status.settings.systemLogEntriesCount)
        } catch {
            blueLogError(error.localizedDescription)
        }
    }
}

public class BlueGetAccessObjectsCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: try blueCastArg(String.self, arg0)
        )
    }
    
    public func runAsync(credentialID: String, refreshToken: Bool? = nil) async throws -> BlueAccessObjectList {
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.notFound)
        }
        
        let tokenAuthentication = try await getTokenAuthentication(credential: credential, refreshToken: refreshToken ?? false)
        
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
            throw BlueError(.unavailable)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(credentialID: String, deviceID: String, objectID: String) async throws -> BlueSystemStatus? {
        guard let _ = blueGetDevice(deviceID) else {
            throw BlueError(.invalidState)
        }
        
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.notFound)
        }
        
        let tokenAuthentication = try await getTokenAuthentication(credential: credential, refreshToken: false)
        
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
    
    public func runAsync(organisation: String, siteID: Int, refreshToken: Bool? = nil) async throws -> BlueAccessCredentialList {
        guard let credential = blueGetAccessCredential(organisation: organisation, siteID: siteID, credentialType: .nfcWriter) else {
            throw BlueError(.notFound)
        }
        
        let tokenAuthentication = try await getTokenAuthentication(credential: credential, refreshToken: refreshToken ?? false)
        
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
            throw BlueError(.invalidState)
        }
        
        let hasOssSoToken = blueHasSpTokenForAction(device: device, action: "ossSoMobile")
        let hasOssSidToken = blueHasSpTokenForAction(device: device, action: "ossSidMobile")
        
        if (!hasOssSoToken && !hasOssSidToken) {
            throw BlueError(.notFound)
        }
        
        let tryOssAccess: () async throws -> BlueOssAccessResult = {
            guard #available(macOS 10.15, *) else {
                throw BlueError(.notSupported)
            }
            
            guard let terminalRun = self.terminalRun else {
                throw BlueError(.notSupported)
            }
            
            if (hasOssSoToken) {
                return try await terminalRun(deviceID, defaultTimeoutSec, "ossSoMobile")
            }
            
            if (hasOssSidToken) {
                return try await terminalRun(deviceID, defaultTimeoutSec, "ossSidMobile")
            }
            
            throw BlueError(.invalidState)
        }
        
#if os(iOS) || os(watchOS)
        return try await blueShowModal(
            title: blueI18n.openViaOssTitle,
            message: blueI18n.openViaOssWaitMessage,
            successMessage: blueI18n.openViaOssSuccessMessage
        ) {
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

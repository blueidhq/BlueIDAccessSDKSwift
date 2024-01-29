import Foundation

public class BlueSynchronizeAccessCredentialCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: try blueCastArg(String.self, arg0)
        )
    }
    
    public func runAsync(credentialID: String, forceRefresh: Bool? = nil) async throws {
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.notFound)
        }
        
        if (credential.credentialType == .nfcWriter) {
            return try await BlueSynchronizeNfcAccessCommand(self.blueAPI)
                .runAsync(credentialID: credentialID, forceRefresh: forceRefresh)
        }
        
        return try await BlueSynchronizeMobileAccessCommand(self.blueAPI)
            .runAsync(credentialID: credentialID, forceRefresh: forceRefresh)
    }
}

internal class BlueAbstractSynchronizeAccessCommand<T>: BlueAPIAsyncCommand where T: BlueSynchronizationResponse {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: try blueCastArg(String.self, arg0)
        )
    }
    
    func runAsync(credentialID: String, forceRefresh: Bool? = nil) async throws -> Void {
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.notFound)
        }
        
        let tokenAuthentication = try await self.getTokenAuthentication(credential: credential, refreshToken: false)
        
        guard let response = try? await self.sync(with: tokenAuthentication, forceRefresh: forceRefresh) else {
            if (credential.hasValidTo) {
                if let validTo = credential.validTo.toDate() {
                    
                    let isExpired = validTo < Date()
                    if (isExpired) {
                        try purge(credential)
                    }
                }
            }
            
            return
        }
        
        if (response.statusCode == 401) {
            try purge(credential)
            return
        }
        
        guard let synchronizationResult = response.data else {
            return
        }
        
        if synchronizationResult.noRefresh == true {
            return
        }
        
        try update(credential, synchronizationResult)
    }
    
    func sync(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<T> {
        fatalError("not implemented")
    }
    
    func update(_ credential: BlueAccessCredential, _ synchronizationResult: T) throws {
        fatalError("not implemented")
    }
    
    func purge(_ credential: BlueAccessCredential) throws {
        fatalError("not implemented")
    }
}

internal struct BlueOssEntry: Codable {
    var ossSo: Data?
    var ossSid: Data?
}

internal class BlueSynchronizeNfcAccessCommand: BlueAbstractSynchronizeAccessCommand<BlueNfcAccessSynchronizationResult> {
    override func sync(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueNfcAccessSynchronizationResult> {
        return try await self.blueAPI!.synchronizeNfcAccess(with: tokenAuthentication)
    }
    
    override func update(_ credential: BlueAccessCredential, _ synchronizationResult: BlueNfcAccessSynchronizationResult) throws {
        var ossEntry = BlueOssEntry()
        
        if let ossSoSettings = synchronizationResult.ossSoSettings {
            if let data = Data(base64Encoded: ossSoSettings) {
                ossEntry.ossSo = data
            }
        }
        
        if let ossSidSettings = synchronizationResult.ossSidSettings {
            if let data = Data(base64Encoded: ossSidSettings) {
                ossEntry.ossSid = data
            }
        }
        
        if (ossEntry.ossSid != nil || ossEntry.ossSo != nil) {
            try blueAccessOssSettingsKeyChain.storeCodableEntry(id: credential.credentialID.id, data: ossEntry)
        }
    }
    
    override func purge(_ credential: BlueAccessCredential) throws {
        _ = try? blueAccessCredentialsKeyChain.deleteEntry(id: credential.credentialID.id)
        _ = try? blueAccessOssSettingsKeyChain.deleteEntry(id: credential.credentialID.id)
    }
}

internal class BlueSynchronizeMobileAccessCommand: BlueAbstractSynchronizeAccessCommand<BlueMobileAccessSynchronizationResult> {
    override func sync(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        return try await self.blueAPI!.synchronizeMobileAccess(with: tokenAuthentication, forceRefresh: forceRefresh)
    }
    
    override func update(_ credential: BlueAccessCredential, _ synchronizationResult: BlueMobileAccessSynchronizationResult) throws {
        var updatedCredential = credential
        updatedCredential.siteName = synchronizationResult.siteName ?? ""
        
        if let siteId = synchronizationResult.siteId {
            updatedCredential.siteID = Int32(siteId)
        }
        
        if let validity = synchronizationResult.validity {
            updatedCredential.validity = BlueLocalTimestamp(Date(timeIntervalSince1970: TimeInterval(validity/1000)))
        }
        
        try blueAccessCredentialsKeyChain.storeEntry(id: updatedCredential.credentialID.id, data: updatedCredential.jsonUTF8Data())
        
        let deviceList = synchronizationResult.getAccessDeviceList()
        try blueAccessDevicesStorage.storeEntry(id: credential.credentialID.id, data: deviceList.jsonUTF8Data())
        
        try synchronizationResult.deviceTerminalPublicKeys?.forEach{terminalPublicKey in
            if let publicKey = Data(base64Encoded: terminalPublicKey.value) {
                try blueTerminalPublicKeysKeychain.storeEntry(id: terminalPublicKey.key, data: publicKey)
            }
        }
        
        try synchronizationResult.tokens?.forEach{deviceToken in
            try blueStoreSpToken(credential: credential, deviceID: deviceToken.deviceId, token: deviceToken.token)
        }
    }
    
    override func purge(_ credential: BlueAccessCredential) throws {
        _ = try? blueAccessCredentialsKeyChain.deleteEntry(id: credential.credentialID.id)
        _ = try? blueAccessAuthenticationTokensKeyChain.deleteEntry(id: credential.credentialID.id)
        
        guard let deviceList = try? BlueGetAccessDevicesCommand().run(credentialID: credential.credentialID.id) else {
            return
        }
        
        purgeSpTokens(credential, deviceList.devices)
        purgeTerminalPublicKeys(deviceList.devices)
        purgeDevicesStorage(credential)
    }
    
    private func purgeSpTokens(_ credential: BlueAccessCredential, _ devices: [BlueAccessDevice]) {
        devices.forEach { device in
            _ = try? blueDeleteSpTokens(credential: credential, deviceID: device.deviceID)
        }
    }
    
    /// Deletes terminal public keys for a given device list.
    /// The terminal public keys are only removed if there are no BlueSPTokens in use by the device.
    /// We may have more than one credential that grants access to the same device.
    /// Therefore, if we simply remove the terminal public key without checking it, the other credentials will no longer work.
    /// - parameter devices:The devices to purge their terminal public keys, if possible.
    /// - throws: An error is thrown if any error occurs during the retrieval of the entry IDs from the KeyChain.
    private func purgeTerminalPublicKeys(_ devices: [BlueAccessDevice]) {
        devices.forEach { device in
            if let entryIds = try? blueGetSpTokenEntryIds(deviceID: device.deviceID) {
                if (entryIds.isEmpty) {
                    _ = try? blueTerminalPublicKeysKeychain.deleteEntry(id: device.deviceID)
                }
            }
        }
    }
    
    private func purgeDevicesStorage(_ credential: BlueAccessCredential) {
        blueAccessDevicesStorage.deleteEntry(id: credential.credentialID.id)
    }
}

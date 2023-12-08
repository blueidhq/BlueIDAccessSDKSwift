import Foundation

internal let blueAccessCredentialsKeyChain = BlueKeychain(attrService: "blueid.accessCredentials")
internal let blueAccessAuthenticationTokensKeyChain = BlueKeychain(attrService: "blueid.accessAuthenticationTokens")
internal let blueAccessDevicesStorage = BlueStorage(collection: "blueid.accessDevices")

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
        throw BlueError(.unavailable)
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
                let isExpired = accessToken.expiresAt < Int(Date().timeIntervalSince1970)
                
                if (!isExpired) {
                    return accessToken
                }
            }
        }
        
        let accessToken: BlueAccessToken = try await self.blueAPI!.getAccessToken(credentialId: credential.credentialID.id)
        
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
        
        try await BlueSynchronizeMobileAccessCommand(self.blueAPI).runAsync(credential: credential, refreshToken: true)
        
        blueFireListeners(fireEvent: .accessCredentialAdded, data: nil)
    }
}

public struct BlueGetAccessCredentialsCommand: BlueAsyncCommand {
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            includePrivateKey: false,
            credentialType: blueCastArg(BlueCredentialType.self, arg0),
            for: blueCastArg(String.self, arg1)
        )
    }
    
    public func runAsync(includePrivateKey: Bool, credentialType: BlueCredentialType? = nil, for deviceID: String? = nil) async throws -> BlueAccessCredentialList {
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
            
            let deviceList = try BlueGetAccessDevicesCommand().run(credential: credential)
            
            let device = deviceList.devices.first() { device in
                return device.deviceID == deviceID
            }
            
            return device != nil
        }
        
        var credentialList = BlueAccessCredentialList()

        if let entries = try blueAccessCredentialsKeyChain.getAllEntries() {
            credentialList.credentials = try entries.compactMap { entry in
                if var credential = try? BlueAccessCredential(jsonUTF8Data: entry) {
                    
                    if (!includePrivateKey) {
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

public class BlueSynchronizeMobileAccessCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credential: try blueCastArg(BlueAccessCredential.self, arg0),
            refreshToken: try blueCastArg(Bool.self, arg1)
        )
    }
    
    public func runAsync(credential: BlueAccessCredential, refreshToken: Bool? = nil) async throws -> Void {
        let tokenAuthentication = try await self.getTokenAuthentication(credential: credential, refreshToken: refreshToken ?? false)
        
        let synchronizationResult = try await self.blueAPI!.synchronizeMobileAccess(with: tokenAuthentication)
        
        if case .some(true) = synchronizationResult.noRefresh {
            return
        }
        
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
        try blueAccessDevicesStorage.storeEntry(key: credential.credentialID.id, data: deviceList.jsonUTF8Data())
        
        try synchronizationResult.deviceTerminalPublicKeys?.forEach{terminalPublicKey in
            if let publicKey = Data(base64Encoded: terminalPublicKey.value) {
                try blueTerminalPublicKeysKeychain.storeEntry(id: terminalPublicKey.key, data: publicKey)
            }
        }
        
        try synchronizationResult.tokens?.forEach{deviceToken in
            try blueStoreSpToken(deviceID: deviceToken.deviceId, token: deviceToken.token)
        }
    }
}

public struct BlueGetAccessDevicesCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try run(credential: try blueCastArg(BlueAccessCredential.self, arg0))
    }
    
    public func run(credential: BlueAccessCredential) throws -> BlueAccessDeviceList {
        if let data = blueAccessDevicesStorage.getEntry(key: credential.credentialID.id) {
            return try BlueAccessDeviceList(jsonUTF8Data: data)
        }
        return BlueAccessDeviceList()
    }
}

public class BlueUpdateDeviceConfigurationCommand: BlueAPIAsyncCommand {
    internal override func runAsync(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) async throws -> Any? {
        if #available(macOS 10.15, *) {
            return try await runAsync(
                credential: try blueCastArg(BlueAccessCredential.self, arg0),
                deviceID: try blueCastArg(String.self, arg1)
            )
        } else {
            throw BlueError(.unavailable)
        }
    }
    
    @available(macOS 10.15, *)
    public func runAsync(credential: BlueAccessCredential, deviceID: String, refreshToken: Bool? = false) async throws -> BlueSystemStatus {
        guard let _ = blueGetDevice(deviceID) else {
            throw BlueError(.invalidState)
        }
        
        let tokenAuthentication = try await getTokenAuthentication(credential: credential, refreshToken: refreshToken ?? false)
        
        let result = try await blueAPI!.createDeviceConfiguration(deviceID: deviceID, with: tokenAuthentication)
        
        guard let data = Data(base64Encoded: result.systemConfiguration) else {
            throw BlueError(.invalidState)
        }
        
        let config: BlueSystemConfig = try blueDecodeMessage(data)
        
        var update = BlueSystemUpdate()
        update.config = config
        
        let status: BlueSystemStatus = try await blueTerminalRun(
            deviceID: deviceID,
            timeoutSeconds: 30.0,
            action: "UPDATE",
            data: update
        )
        
        return status
    }
}

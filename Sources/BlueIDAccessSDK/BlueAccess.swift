import Foundation

internal let blueAccessCredentialsKeyChain = BlueKeychain(attrService: "blueid.accessCredentials")
internal let blueAccessAuthenticationTokensKeyChain = BlueKeychain(attrService: "blueid.accessAuthenticationTokens")
internal let blueAccessDeviceTokensKeyChain = BlueKeychain(attrService: "blueid.accessDeviceTokens")
internal let blueAccessDevicesStorage = BlueStorage(collection: "blueid.accessDevices")

public struct BlueAddAccessCredentialCommand: BlueAsyncCommand {
    private let blueAPI: BlueAPIProtocol?
    
    init(_ blueAPI: BlueAPIProtocol? = nil) {
        if #available(macOS 12.0, *) {
            self.blueAPI = blueAPI ?? BlueAPI()
        } else {
            self.blueAPI = nil
        }
    }
    
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
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
        return try await runAsync(includePrivateKey: false)
    }
    
    public func runAsync(includePrivateKey: Bool) async throws -> BlueAccessCredentialList {
        var credentialList = BlueAccessCredentialList()

        if let entries = try blueAccessCredentialsKeyChain.getAllEntries() {
            credentialList.credentials = entries.compactMap { entry in
                if var credential = try? BlueAccessCredential(jsonUTF8Data: entry) {
                    if (!includePrivateKey) {
                        credential.clearPrivateKey()
                    }
                    
                    return credential
                }
                
                return nil
            }
        }
        
        return credentialList
    }
}

public struct BlueSynchronizeMobileAccessCommand: BlueAsyncCommand {
    private let blueAPI: BlueAPIProtocol?
    
    init(_ blueAPI: BlueAPIProtocol? = nil) {
        if #available(macOS 12.0, *) {
            self.blueAPI = blueAPI ?? BlueAPI()
        } else {
            self.blueAPI = nil
        }
    }
    
    internal func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credential: try blueCastArg(BlueAccessCredential.self, arg0),
            refreshToken: try blueCastArg(Bool.self, arg1)
        )
    }
    
    public func runAsync(credential: BlueAccessCredential, refreshToken: Bool? = false) async throws -> Void {
        let accessToken = try await self.getAccessToken(credential, refreshToken ?? false)
        let synchronizationResult = try await self.synchronizeMobileAccess(credential, accessToken)
        
        if case .some(true) = synchronizationResult.noRefresh {
            return
        }
        
        var updatedCredential = credential
        updatedCredential.siteName = synchronizationResult.siteName ?? ""
        
        if let validity = synchronizationResult.validity {
            updatedCredential.validity = BlueLocalTimestamp(Date(timeIntervalSince1970: TimeInterval(validity/1000)))
        }
        
        try blueAccessCredentialsKeyChain.storeEntry(id: updatedCredential.credentialID.id, data: updatedCredential.jsonUTF8Data())
        
        let deviceList = synchronizationResult.getAccessDeviceList()
        try blueAccessDevicesStorage.storeEntry(key: credential.credentialID.id, data: deviceList.jsonUTF8Data())
        
        try synchronizationResult.deviceTerminalPublicKeys?.forEach{terminalPublicKey in
            if let publicKey = terminalPublicKey.value.data(using: .ascii) {
                try blueTerminalPublicKeysKeychain.storeEntry(id: terminalPublicKey.key, data: publicKey)
            }
        }
        
        try synchronizationResult.tokens?.forEach{deviceToken in
            if let token = deviceToken.token.data(using: .ascii) {
                try blueAccessDeviceTokensKeyChain.storeEntry(id: deviceToken.deviceId, data: token)
            }
        }
    }
    
    private func getAccessToken(_ credential: BlueAccessCredential, _ refreshToken: Bool) async throws -> BlueAccessToken {
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
    
    private func synchronizeMobileAccess(_ credential: BlueAccessCredential, _ token: BlueAccessToken) async throws -> BlueMobileAccessSynchronizationResult {
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
        
        return try await self.blueAPI!.synchronizeMobileAccess(with: tokenAuthentication)
    }
}

public struct BlueGetAccessDevices: BlueCommand {
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

import Foundation

/**
 * @class BlueAccessAPIHelper
 * A helper class for interacting with the BlueAPI to perform various operations related to authentication and access tokens.
 */
internal struct BlueAccessAPIHelper {
    private let blueAPI: BlueAPIProtocol
    
    init(_ blueAPI: BlueAPIProtocol) { self.blueAPI = blueAPI }
    
    internal func getTokenAuthentication(credential: BlueAccessCredential, refreshToken: Bool? = false) async throws -> BlueTokenAuthentication {
        let token = try await getAccessToken(credential: credential, refreshToken: refreshToken ?? false)
        
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
        
        // Before issuing a new token, we should always delete the current one.
        // Whenever we issue a new token, the backend purges any other tokens.
        // So, in case we are not able to store the token in the keychain, we won't end up having a nonexistent token for upcoming requests.
        _ = try blueAccessAuthenticationTokensKeyChain.deleteEntry(id: credential.credentialID.id)
        
        let accessToken: BlueAccessToken = try await self.blueAPI.getAccessToken(credentialId: credential.credentialID.id).getData()
        
        storeAccessToken(credential: credential, accessToken: accessToken)
        
        return accessToken
    }
    
    private func storeAccessToken(credential: BlueAccessCredential, accessToken: BlueAccessToken) {
        do {
            try blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: accessToken)
        } catch {
            blueLogError(error.localizedDescription)
        }
    }
}

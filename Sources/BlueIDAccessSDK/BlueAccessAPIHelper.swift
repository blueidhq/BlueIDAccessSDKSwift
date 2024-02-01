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
        
        let accessToken: BlueAccessToken = try await self.blueAPI.getAccessToken(credentialId: credential.credentialID.id).getData()
        
        self.storeAccessToken(credential: credential, accessToken: accessToken)
        
        return accessToken
    }
    
    private func storeAccessToken(credential: BlueAccessCredential, accessToken: BlueAccessToken) {
        do {
            try? blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: accessToken)
        }
    }
}

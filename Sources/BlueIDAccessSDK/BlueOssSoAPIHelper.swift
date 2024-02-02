import Foundation

/**
 * @class BlueOssSoAPIHelper
 * A helper class for interacting with the BlueAPI to perform various operations related to event logs and synchronization.
 */
internal struct BlueOssSoAPIHelper {
    private let blueAPI: BlueAPIProtocol
    
    init(_ blueAPI: BlueAPIProtocol) { self.blueAPI = blueAPI }
    
    /// Synchronizes a given offline credential and returns its configuration, if any.
    ///
    /// - parameter nfcCredential: The NFC Writer credential.
    /// - parameter offlineCredentialID: The Offline Credential ID.
    /// - throws: Throws an error of type `BlueError(.invalidState)` if the configuration returned from the backend cannot be converted into a BlueOssSoConfiguration.
    func synchronizeOfflineCredential(nfcCredential: BlueAccessCredential, offlineCredentialID: String) async throws -> BlueOssSoConfiguration? {
        let tokenAuthentication = try await BlueAccessAPIHelper(blueAPI)
            .getTokenAuthentication(credential: nfcCredential)
        
        let result = try await blueAPI.synchronizeOfflineAccess(credentialID: offlineCredentialID, with: tokenAuthentication).getData()
        
        if (result.noRefresh == true) {
            return nil
        }
        
        var ossSoConfiguration: BlueOssSoConfiguration?
        
        if let configuration = result.configuration {
            if let data = Data(base64Encoded: configuration) {
                ossSoConfiguration = try blueDecodeMessage(data)
            }
        }
        else if let blacklistFile = result.blacklistFile {
            if let data = Data(base64Encoded: blacklistFile) {
                ossSoConfiguration = BlueOssSoConfiguration()
                ossSoConfiguration?.blacklist = try blueDecodeMessage(data)
            }
        }
        
        guard let ossSoConfiguration = ossSoConfiguration else {
            throw BlueError(.invalidState)
        }
        
        return ossSoConfiguration
    }
    
    /// Pushes a given offline credential events to the backend.
    ///
    /// - parameter nfcCredential: The NFC Writer credential.
    /// - parameter ossSoConfiguration: The Transponder's OssSo configuration
    /// - throws: Throws any errors raised by BlueAPI.pushEvents
    func pushEventLogs(nfcCredential: BlueAccessCredential, ossSoConfiguration: BlueOssSoConfiguration) async throws {
        guard !ossSoConfiguration.event.events.isEmpty else {
            return
        }
        
        let tokenAuthentication = try await BlueAccessAPIHelper(blueAPI)
            .getTokenAuthentication(credential: nfcCredential)
        
        let chunks = ossSoConfiguration.event.events.chunks(of: 50)
        
        for chunk in chunks {
            let events = chunk.map{ BluePushEvent( event: $0, credentialId: ossSoConfiguration.info.credentialID.id ) }
            
            _ = try await self.blueAPI.pushEvents(events: events, with: tokenAuthentication).getData()
        }
    }
}

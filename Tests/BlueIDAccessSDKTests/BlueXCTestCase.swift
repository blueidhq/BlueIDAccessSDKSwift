import XCTest
@testable import BlueIDAccessSDK

class DefaultBlueAPIMock: BlueAPIProtocol {
    func createDeviceConfiguration(deviceID: String, with tokenAuthentication: BlueIDAccessSDK.BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueCreateDeviceConfigurationResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueCreateDeviceConfigurationResult(
                systemConfiguration: "dummy"
            )
        )
    }
    
    func updateDeviceSystemStatus(systemStatus: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueUpdateDeviceSystemStatusResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueUpdateDeviceSystemStatusResult(updated: true)
        )
    }
    
    func pushEvents(events: [BluePushEvent], with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BluePushEventsResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BluePushEventsResult(storedEvents: [])
        )
    }
    
    func pushSystemLogs(deviceID: String, logEntries: [BluePushSystemLogEntry], with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BluePushSystemLogResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BluePushSystemLogResult(storedLogEntries: [])
        )
    }
    
    func getAccessToken(credentialId: String) async throws -> BlueFetchResponse<BlueAccessToken> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueAccessToken(token: "dummy", expiresAt: 0)
        )
    }
    
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult>{
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueMobileAccessSynchronizationResult(
                siteId: 1,
                validity: 0,
                tokens: [],
                deviceTerminalPublicKeys: [:]
            )
        )
    }
    
    func getAccessObjects(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessObjectsResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: []
        )
    }
    
    func getBlacklistEntries(deviceID: String, with tokenAuthentication: BlueTokenAuthentication, limit: Int?) async throws -> BlueFetchResponse<BlueGetBlacklistEntriesResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueGetBlacklistEntriesResult(blacklistEntries: "")
        )
    }
    
    func claimDevice(deviceID: String, objectID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueClaimDeviceResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueClaimDeviceResult(site: "")
        )
    }
}

class BlueXCTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        
        do {
            _ = try? BlueInitializeCommand().run()
        }
    }
    
    override func tearDown() {
        do {
            _ = try? blueAccessCredentialsKeyChain.deleteAllEntries()
            _ = try? blueAccessAuthenticationTokensKeyChain.deleteAllEntries()
            _ = try? blueTerminalPublicKeysKeychain.deleteAllEntries()
            _ = try? blueTerminalRequestDataKeychain.deleteAllEntries()
            
            blueAccessDevicesStorage.deleteAllEntries()
            
            _ = try? BlueReleaseCommand().run()
        }
        
        super.tearDown()
    }
}

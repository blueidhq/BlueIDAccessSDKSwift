import XCTest
@testable import BlueIDAccessSDK

internal class DefaultBlueAPIMock: BlueAPIProtocol {
    func getLatestFirmware(deviceID: String, with tokenAuthentication: BlueIDAccessSDK.BlueTokenAuthentication) async throws -> BlueIDAccessSDK.BlueFetchResponse<BlueIDAccessSDK.BlueGetLatestFirmwareResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueGetLatestFirmwareResult(version: 1, url: "file://")
        )
    }
    
    
    func getAccessCredentials(with tokenAuthentication: BlueIDAccessSDK.BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessCredentialsResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: []
        )
    }
    
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
    
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult>{
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
    
    func synchronizeNfcAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueNfcAccessSynchronizationResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueNfcAccessSynchronizationResult()
        )
    }
    
    func getAccessObjects(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessObjectsResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: []
        )
    }
    
    func synchronizeOfflineAccess(credentialID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueOfflineAccessSynchronizationResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueOfflineAccessSynchronizationResult()
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
    
    func claimAccessCredential(activationToken: String) async throws -> BlueFetchResponse<BlueClaimAccessCredentialResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueAccessCredential()
        )
    }
}

internal class BlueDefaultAccessEventServiceMock: BlueAccessEventServiceProtocol {
    func pushEvents(_ credentialID: String, _ events: [BluePushEvent]) {}
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
            BlueClearDataCommand().run()
            
            _ = try? BlueReleaseCommand().run()
        }
        
        super.tearDown()
    }
}

extension XCTest {
    func XCTAssertThrowsError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message())
        } catch {
            errorHandler(error)
        }
    }
    
    func XCTAssertNotThrowsError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> T? {
        do {
            return try await expression()
        } catch {
            XCTFail(message())
        }
        
        return nil
    }
}

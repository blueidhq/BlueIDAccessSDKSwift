import XCTest

@testable import BlueIDAccessSDK

private class BlueAPIMock: DefaultBlueAPIMock {
    override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        let token = try blueCreateSignedCommandDemoToken("MAINTC")
        
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueMobileAccessSynchronizationResult(
                tokens: [
                    BlueAccessDeviceToken(
                        deviceId: "device-1",
                        objectId: 1,
                        token: try blueEncodeMessage(token).base64EncodedString()
                    )
                ]
            )
        )
    }
}

final class BlueGetAccessCredentialsCommandTests: BlueXCTestCase {
    func testGetCredentials() async throws {
        var credential1 = blueCreateAccessCredentialDemo()
        credential1.credentialID.id = "credential-1"
        credential1.credentialType = .maintenance
        
        var credential2 = blueCreateAccessCredentialDemo()
        credential2.credentialID.id = "credential-2"
        credential2.credentialType = .nfcWriter
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential1)
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential2)
        
        let accessCredentialList = try? BlueGetAccessCredentialsCommand().run()
        
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 2, "There should be 2 credentials")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialID.id, "credential-1", "Wrong id")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialType, .maintenance, "Wrong type")
        XCTAssertEqual(accessCredentialList?.credentials[1].credentialID.id, "credential-2", "Wrong id")
        XCTAssertEqual(accessCredentialList?.credentials[1].credentialType, .nfcWriter, "Wrong type")
    }
    
    func testGetCredentialsFilteringByCredentialType() async throws {
        var credential1 = blueCreateAccessCredentialDemo()
        credential1.credentialID.id = "credential-1"
        credential1.credentialType = .maintenance
        
        var credential2 = blueCreateAccessCredentialDemo()
        credential2.credentialID.id = "credential-2"
        credential2.credentialType = .nfcWriter
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential1)
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential2)
        
        var accessCredentialList = try? BlueGetAccessCredentialsCommand().run(credentialType: .nfcWriter)
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 1, "There should be 1 credential")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialID.id, "credential-2", "Wrong id")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialType, .nfcWriter, "Wrong type")
        
        accessCredentialList = try? BlueGetAccessCredentialsCommand().run(credentialType: .regular)
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 0, "There should no credentials")
    }
    
    func testGetCredentialsFilteringByDeviceID() async throws {
        var credential1 = blueCreateAccessCredentialDemo()
        credential1.credentialID.id = "credential-1"
        credential1.credentialType = .maintenance
        
        var credential2 = blueCreateAccessCredentialDemo()
        credential2.credentialID.id = "credential-2"
        credential2.credentialType = .nfcWriter
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(BlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential1)
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential2)
        
        var accessCredentialList = try? BlueGetAccessCredentialsCommand().run(for: "device-1")
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 1, "There should be 1 credential")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialID.id, "credential-1", "Wrong id")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialType, .maintenance, "Wrong type")
        
        accessCredentialList = try? BlueGetAccessCredentialsCommand().run(for: "device-2")
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 0, "There should no credentials")
    }
    
    func testGetCredentialsFilteringByCredentialTypeAndDeviceID() async throws {
        var credential1 = blueCreateAccessCredentialDemo()
        credential1.credentialID.id = "credential-1"
        credential1.credentialType = .maintenance
        
        var credential2 = blueCreateAccessCredentialDemo()
        credential2.credentialID.id = "credential-2"
        credential2.credentialType = .nfcWriter
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(BlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential1)
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential2)
        
        var accessCredentialList = try? BlueGetAccessCredentialsCommand().run(credentialType: .maintenance, for: "device-1")
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 1, "There should be 1 credential")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialID.id, "credential-1", "Wrong id")
        XCTAssertEqual(accessCredentialList?.credentials[0].credentialType, .maintenance, "Wrong type")
        
        accessCredentialList = try? BlueGetAccessCredentialsCommand().run(credentialType: .nfcWriter, for: "device-1")
        XCTAssertNotNil(accessCredentialList, "Returned access credential list should not be null")
        XCTAssertEqual(accessCredentialList?.credentials.count, 0, "There should no credentials")
    }
}

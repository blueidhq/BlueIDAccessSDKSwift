import XCTest

@testable import BlueIDAccessSDK

private class BlueAPIMock: DefaultBlueAPIMock {
    private let credentialId: String
    
    init(_ credentialId: String) {
        self.credentialId = credentialId
    }
    
    override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        let token = try blueCreateSignedOssSoDemoToken(credentialId)
        
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueMobileAccessSynchronizationResult(
                siteId: 1,
                validity: 0,
                tokens: [
                    BlueAccessDeviceToken(
                        deviceId: "device-1",
                        objectId: 1,
                        token: try blueEncodeMessage(token).base64EncodedString()
                    ),
                ],
                deviceTerminalPublicKeys: [
                    "device-1": "public-key-1".data(using: .utf8)!.base64EncodedString(),
                ]
            )
        )
    }
}

final class BlueSynchronizeAccessCredentials: BlueXCTestCase {
    func testPurgeTokens() async throws {
        var credentialA = blueCreateAccessCredentialDemo()
        credentialA.credentialID.id = "CREDENT-AA"
        credentialA.credentialType = .regular
        
        var credentialB = blueCreateAccessCredentialDemo()
        credentialB.credentialID.id = "CREDENT-BB"
        credentialB.credentialType = .regular
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(BlueAPIMock("CREDENT-AA"), BlueDefaultAccessEventServiceMock())).runAsync(credential: credentialA)
        try await BlueAddAccessCredentialCommand(BlueSdkService(BlueAPIMock("CREDENT-BB"), BlueDefaultAccessEventServiceMock())).runAsync(credential: credentialB)
        
        var entry = try blueGetSpTokenEntry("device-1:ossSoMobile");
        guard let spTokenEntry = entry as? [BlueSPTokenEntry] else {
            XCTFail("Wrong entry type")
            return
        }
    
        XCTAssertEqual(spTokenEntry.count, 2, "Wrong number of entries")
        
        // sync should NOT purge anything yet.
        _ = try await BlueSynchronizeAccessCredentialsCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync()
        
        entry = try blueGetSpTokenEntry("device-1:ossSoMobile");
        guard let spTokenEntry = entry as? [BlueSPTokenEntry] else {
            XCTFail("Wrong entry type")
            return
        }
        XCTAssertEqual(spTokenEntry.count, 2, "Wrong number of entries")
        
        // Remove only the credential and leave its (orphaned) tokens.
        _ = try blueAccessCredentialsKeyChain.deleteEntry(id: credentialB.credentialID.id)
        
        // sync should purge orphaned tokens.
        _ = try await BlueSynchronizeAccessCredentialsCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync()
        
        entry = try blueGetSpTokenEntry("device-1:ossSoMobile");
        guard let spTokenEntry = entry as? [BlueSPTokenEntry] else {
            XCTFail("Wrong entry type")
            return
        }
        
        XCTAssertEqual(spTokenEntry.count, 1)
        XCTAssertEqual(spTokenEntry[0].credentialID, "CREDENT-AA")
        
        let spToken = try blueGetSpToken("device-1:ossSoMobile")
        XCTAssertNotNil(spToken)
        XCTAssertEqual(String(data: spToken!.ossSo.infoFile.subdata(in: 3..<13), encoding: .utf8), "CREDENT-AA")
    }
}

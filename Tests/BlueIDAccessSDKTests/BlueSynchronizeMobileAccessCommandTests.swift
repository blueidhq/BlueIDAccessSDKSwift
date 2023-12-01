import XCTest

@testable import BlueIDAccessSDK

private struct BlueAPIMock: BlueAPIProtocol {
    func getAccessToken(credentialId: String) -> BlueAccessToken{
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        
        return BlueAccessToken(
            token: "new-access-token",
            expiresAt: Int(tomorrowDate!.timeIntervalSince1970)
        )
    }
    
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueMobileAccessSynchronizationResult {
        return BlueMobileAccessSynchronizationResult(
            siteId: 1,
            validity: 0,
            tokens: [
                BlueAccessDeviceToken(deviceId: "device-1", token: "device-token-1"),
                BlueAccessDeviceToken(deviceId: "device-2", token: "device-token-2")
            ],
            deviceTerminalPublicKeys: [
                "device-1": "public-key-1",
                "device-2": "public-key-2",
            ]
        )
    }
}

final class BlueSynchronizeMobileAccessCommandTests: BlueXCTestCase {
    
    func testSynchronizeMobileAccess() async throws {
        let credential = blueCreateAccessCredentialDemo()
        
        do {
            try await BlueSynchronizeMobileAccessCommand(BlueAPIMock()).runAsync(credential: credential)
        } catch {
            XCTFail("Should not throw any errors")
        }
        
        let result = try BlueGetAccessDevices().run(credential: credential)
        XCTAssertEqual(result.devices[0].deviceID, "device-1")
        XCTAssertEqual(result.devices[1].deviceID, "device-2")
        
        let accessToken: BlueAccessToken? = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(accessToken, "Access token should have been stored in the KeyChain")
        XCTAssertEqual(accessToken!.token, "new-access-token")
        XCTAssertGreaterThan(accessToken!.expiresAt, Int(Date().timeIntervalSince1970))
        
        let terminalPublicKey1 = try blueTerminalPublicKeysKeychain.getEntry(id: "device-1")
        XCTAssertNotNil(terminalPublicKey1)
        XCTAssertEqual(terminalPublicKey1, "public-key-1".data(using: .ascii))
        
        let terminalPublicKey2 = try blueTerminalPublicKeysKeychain.getEntry(id: "device-2")
        XCTAssertNotNil(terminalPublicKey2)
        XCTAssertEqual(terminalPublicKey2, "public-key-2".data(using: .ascii))
        
        let deviceToken1 = try blueAccessDeviceTokensKeyChain.getEntry(id: "device-1")
        XCTAssertNotNil(deviceToken1)
        XCTAssertEqual(deviceToken1, "device-token-1".data(using: .ascii))
        
        let deviceToken2 = try blueAccessDeviceTokensKeyChain.getEntry(id: "device-2")
        XCTAssertNotNil(deviceToken2)
        XCTAssertEqual(deviceToken2, "device-token-2".data(using: .ascii))
    }
    
    func testSynchronizeMobileAccessWithValidAccessToken() async throws {
        let credential = blueCreateAccessCredentialDemo()
        
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        let validAccessToken = BlueAccessToken(token: "valid-access-token", expiresAt: Int(tomorrowDate!.timeIntervalSince1970))
        try blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: validAccessToken)
        
        do {
            try await BlueSynchronizeMobileAccessCommand(BlueAPIMock()).runAsync(credential: credential)
        } catch {
            XCTFail("Should not throw any errors")
        }
        
        let accessToken: BlueAccessToken? = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(accessToken, "No new token should have been issued")
        XCTAssertEqual(accessToken!.token, "valid-access-token")
        XCTAssertEqual(accessToken!.expiresAt, Int(tomorrowDate!.timeIntervalSince1970))
    }
    
    func testSynchronizeMobileAccessWithExpiredAccessToken() async throws {
        let credential = blueCreateAccessCredentialDemo()
        
        let expiredAccessToken = BlueAccessToken(token: "expired-access--oken", expiresAt: 0)
        try blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: expiredAccessToken)
        
        do {
            try await BlueSynchronizeMobileAccessCommand(BlueAPIMock()).runAsync(credential: credential)
        } catch {
            XCTFail("Should not throw any errors")
        }
        
        let accessToken: BlueAccessToken? = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(accessToken, "A new access token should have been stored in the KeyChain")
        XCTAssertEqual(accessToken!.token, "new-access-token")
        XCTAssertGreaterThan(accessToken!.expiresAt, Int(Date().timeIntervalSince1970))
    }
}

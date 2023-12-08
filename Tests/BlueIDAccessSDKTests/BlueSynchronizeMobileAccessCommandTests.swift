import XCTest

@testable import BlueIDAccessSDK

private struct BlueAPIMock: BlueAPIProtocol {
    func createDeviceConfiguration(deviceID: String, with tokenAuthentication: BlueIDAccessSDK.BlueTokenAuthentication) async throws -> BlueCreateDeviceConfigurationResult {
        return BlueCreateDeviceConfigurationResult(
            systemConfiguration: "dummy"
        )
    }
    
    func getAccessToken(credentialId: String) -> BlueAccessToken{
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        
        return BlueAccessToken(
            token: "new-access-token",
            expiresAt: Int(tomorrowDate!.timeIntervalSince1970)
        )
    }
    
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueMobileAccessSynchronizationResult {
        let token1 = try blueCreateSignedCommandDemoToken("MAINTC")
        let token2 = try blueCreateSignedCommandDemoToken("PING")
        
        return BlueMobileAccessSynchronizationResult(
            siteId: 1,
            validity: 0,
            tokens: [
                BlueAccessDeviceToken(deviceId: "device-1", token: try blueEncodeMessage(token1).base64EncodedString()),
                BlueAccessDeviceToken(deviceId: "device-2", token: try blueEncodeMessage(token2).base64EncodedString())
            ],
            deviceTerminalPublicKeys: [
                "device-1": "public-key-1".data(using: .utf8)!.base64EncodedString(),
                "device-2": "public-key-2".data(using: .utf8)!.base64EncodedString(),
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
            print(error.localizedDescription)
            XCTFail("Should not throw any errors")
        }
        
        let result = try BlueGetAccessDevicesCommand().run(credential: credential)
        XCTAssertEqual(result.devices[0].deviceID, "device-1")
        XCTAssertEqual(result.devices[1].deviceID, "device-2")
        
        let accessToken: BlueAccessToken? = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(accessToken, "Access token should have been stored in the KeyChain")
        XCTAssertEqual(accessToken!.token, "new-access-token")
        XCTAssertGreaterThan(accessToken!.expiresAt, Int(Date().timeIntervalSince1970))
        
        let terminalPublicKey1 = try blueTerminalPublicKeysKeychain.getEntry(id: "device-1")
        XCTAssertNotNil(terminalPublicKey1)
        XCTAssertEqual(String(data: terminalPublicKey1!, encoding: .utf8), "public-key-1")
        
        let terminalPublicKey2 = try blueTerminalPublicKeysKeychain.getEntry(id: "device-2")
        XCTAssertNotNil(terminalPublicKey2)
        XCTAssertEqual(String(data: terminalPublicKey2!, encoding: .utf8), "public-key-2")
        
        let deviceToken1Data = try blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC")
        XCTAssertNotNil(deviceToken1Data)
        
        let deviceToken1: BlueSPToken = try blueDecodeMessage(deviceToken1Data!)
        XCTAssertEqual(deviceToken1.command.command, "MAINTC")
        
        let deviceToken2Data = try blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING")
        XCTAssertNotNil(deviceToken2Data)
        
        let deviceToken2: BlueSPToken = try blueDecodeMessage(deviceToken2Data!)
        XCTAssertEqual(deviceToken2.command.command, "PING")
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

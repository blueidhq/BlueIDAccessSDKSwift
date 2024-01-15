import XCTest

@testable import BlueIDAccessSDK

private class BlueAPIMock: DefaultBlueAPIMock {
    
    override func getAccessToken(credentialId: String) async throws -> BlueFetchResponse<BlueAccessToken> {
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueAccessToken(
                token: "new-access-token",
                expiresAt: Int(tomorrowDate!.timeIntervalSince1970)
            )
        )
    }
    
    override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        let token1 = try blueCreateSignedCommandDemoToken("MAINTC")
        let token2 = try blueCreateSignedCommandDemoToken("PING")
        
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueMobileAccessSynchronizationResult(
                siteId: 1,
                validity: 0,
                tokens: [
                    BlueAccessDeviceToken(
                        deviceId: "device-1",
                        objectId: 1,
                        token: try blueEncodeMessage(token1).base64EncodedString()
                    ),
                    BlueAccessDeviceToken(
                        deviceId: "device-2",
                        objectId: 1,
                        token: try blueEncodeMessage(token2).base64EncodedString()
                    )
                ],
                deviceTerminalPublicKeys: [
                    "device-1": "public-key-1".data(using: .utf8)!.base64EncodedString(),
                    "device-2": "public-key-2".data(using: .utf8)!.base64EncodedString(),
                ]
            )
        )
    }
}

final class BlueSynchronizeMobileAccessCommandTests: BlueXCTestCase {
    
    func testSynchronizeMobileAccess() async throws {
        let credential = blueCreateAccessCredentialDemo()
        try! await BlueAddAccessCredentialCommand(BlueAPIMock()).runAsync(credential: credential)
        
        try! await BlueSynchronizeMobileAccessCommand(BlueAPIMock()).runAsync(credentialID: credential.credentialID.id)
        
        let result = try BlueGetAccessDevicesCommand().run(credentialID: credential.credentialID.id)
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
        try! await BlueAddAccessCredentialCommand(BlueAPIMock()).runAsync(credential: credential)
        
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        let validAccessToken = BlueAccessToken(token: "valid-access-token", expiresAt: Int(tomorrowDate!.timeIntervalSince1970))
        try blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: validAccessToken)
        
        try! await BlueSynchronizeMobileAccessCommand(BlueAPIMock()).runAsync(credentialID: credential.credentialID.id)
        let accessToken: BlueAccessToken? = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(accessToken, "No new token should have been issued")
        XCTAssertEqual(accessToken!.token, "valid-access-token")
        XCTAssertEqual(accessToken!.expiresAt, Int(tomorrowDate!.timeIntervalSince1970))
    }
    
    func testSynchronizeMobileAccessWithExpiredAccessToken() async throws {
        let credential = blueCreateAccessCredentialDemo()
        try! await BlueAddAccessCredentialCommand(BlueAPIMock()).runAsync(credential: credential)
        
        let expiredAccessToken = BlueAccessToken(token: "expired-access--oken", expiresAt: 0)
        try blueAccessAuthenticationTokensKeyChain.storeCodableEntry(id: credential.credentialID.id, data: expiredAccessToken)
        
        try! await BlueSynchronizeMobileAccessCommand(BlueAPIMock()).runAsync(credentialID: credential.credentialID.id)
        let accessToken: BlueAccessToken? = try blueAccessAuthenticationTokensKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(accessToken, "A new access token should have been stored in the KeyChain")
        XCTAssertEqual(accessToken!.token, "new-access-token")
        XCTAssertGreaterThan(accessToken!.expiresAt, Int(Date().timeIntervalSince1970))
    }
    
    func testSynchronizeMobileAccessWithUnauthorizedResponse() async throws {
        class BlueAPIUnauthorizedMock: BlueAPIMock {
            override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
                return BlueFetchResponse(statusCode: 401)
            }
        }
        
        let credential = blueCreateAccessCredentialDemo()
        
        try! await BlueAddAccessCredentialCommand(BlueAPIMock()).runAsync(credential: credential)
        XCTAssertNotNil(try? blueAccessCredentialsKeyChain.getEntry(id: credential.credentialID.id), "Access credential should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-1"), "Terminal public key should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-2"), "Terminal public key should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC"), "SP Token should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING"), "SP Token should have been stored in the KeyChain")
        XCTAssertNotNil(blueAccessDevicesStorage.getEntry(id: credential.credentialID.id), "Access device list should have been stored in the local storage")
        
        try! await BlueSynchronizeMobileAccessCommand(BlueAPIUnauthorizedMock()).runAsync(credentialID: credential.credentialID.id)
        XCTAssertNil(try? blueAccessCredentialsKeyChain.getEntry(id: credential.credentialID.id), "Access credential should have been removed from the KeyChain")
        XCTAssertNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-1"), "Terminal public key should have been removed from the KeyChain")
        XCTAssertNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-2"), "Terminal public key should have been removed from the KeyChain")
        XCTAssertNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC"), "SP Token should have been removed from the KeyChain")
        XCTAssertNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING"), "SP Token should have been removed from the KeyChain")
        XCTAssertNil(blueAccessDevicesStorage.getEntry(id: credential.credentialID.id), "Access device list should have been removed from the local storage")
    }
    
    func testSynchronizeMobileAccessWithBadRequestResponse() async throws {
        class BlueAPIBadRequestMock: BlueAPIMock {
            override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
                return BlueFetchResponse(statusCode: 400)
            }
        }
        
        let credential = blueCreateAccessCredentialDemo()
        
        try! await BlueAddAccessCredentialCommand(BlueAPIMock()).runAsync(credential: credential)
        XCTAssertNotNil(try? blueAccessCredentialsKeyChain.getEntry(id: credential.credentialID.id), "Access credential should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-1"), "Terminal public key should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-2"), "Terminal public key should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC"), "SP Token should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING"), "SP Token should have been stored in the KeyChain")
        XCTAssertNotNil(blueAccessDevicesStorage.getEntry(id: credential.credentialID.id), "Access device list should have been stored in the local storage")
        
        try! await BlueSynchronizeMobileAccessCommand(BlueAPIBadRequestMock()).runAsync(credentialID: credential.credentialID.id)
        XCTAssertNotNil(try? blueAccessCredentialsKeyChain.getEntry(id: credential.credentialID.id), "Access credential should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-1"), "Terminal public key should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-2"), "Terminal public key should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC"), "SP Token should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING"), "SP Token should NOT have been removed from the KeyChain")
        XCTAssertNotNil(blueAccessDevicesStorage.getEntry(id: credential.credentialID.id), "Access device list should NOT have been removed from the local storage")
    }
    
    func testSynchronizeMobileAccessWithOfflineMode() async throws {
        class BlueAPIOfflineMock: BlueAPIMock {
            override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
                throw BlueError(.disconnected)
            }
        }
        
        let credential = blueCreateAccessCredentialDemo()
        
        try! await BlueAddAccessCredentialCommand(BlueAPIMock()).runAsync(credential: credential)
        XCTAssertNotNil(try? blueAccessCredentialsKeyChain.getEntry(id: credential.credentialID.id), "Access credential should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-1"), "Terminal public key should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-2"), "Terminal public key should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC"), "SP Token should have been stored in the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING"), "SP Token should have been stored in the KeyChain")
        XCTAssertNotNil(blueAccessDevicesStorage.getEntry(id: credential.credentialID.id), "Access device list should have been stored in the local storage")
        
        try! await BlueSynchronizeMobileAccessCommand(BlueAPIOfflineMock()).runAsync(credentialID: credential.credentialID.id)
        XCTAssertNotNil(try? blueAccessCredentialsKeyChain.getEntry(id: credential.credentialID.id), "Access credential should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-1"), "Terminal public key should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalPublicKeysKeychain.getEntry(id: "device-2"), "Terminal public key should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-1:MAINTC"), "SP Token should NOT have been removed from the KeyChain")
        XCTAssertNotNil(try? blueTerminalRequestDataKeychain.getEntry(id: "device-2:PING"), "SP Token should NOT have been removed from the KeyChain")
        XCTAssertNotNil(blueAccessDevicesStorage.getEntry(id: credential.credentialID.id), "Access device list should NOT have been removed from the local storage")
    }
}

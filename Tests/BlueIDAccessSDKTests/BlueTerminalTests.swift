import XCTest

@testable import BlueIDAccessSDK

private func createMockToken() throws -> (token: BlueSPToken, data: Data, base64: String){
    let token = try blueCreateSignedCommandDemoToken("PING")
    let data = try blueEncodeMessage(token)
    let base64 = data.base64EncodedString()
    
    return (token: token, data: data, base64: base64)
}

final class BlueTerminalTests: BlueXCTestCase {
    func testBlueStoreSpToken() throws {
        let mockToken = try createMockToken()
        
        var credentialA = blueCreateAccessCredentialDemo()
        credentialA.credentialID.id = "A"
        
        var credentialB = blueCreateAccessCredentialDemo()
        credentialB.credentialID.id = "B"
        
        try blueStoreSpToken(credential: credentialA, deviceID: "test", token: mockToken.base64)
        try blueStoreSpToken(credential: credentialA, deviceID: "test", token: mockToken.base64)
        try blueStoreSpToken(credential: credentialB, deviceID: "test", token: mockToken.base64)
        try blueStoreSpToken(credential: credentialB, deviceID: "test", token: mockToken.base64)
        
        let entry = try blueGetSpTokenEntry("test:PING")
        XCTAssert(entry is [BlueSPTokenEntry], "Wrong type")
        
        let spTokenEntries = entry as! [BlueSPTokenEntry]
        XCTAssertEqual(spTokenEntries.count, 2)
        XCTAssertEqual(spTokenEntries[0].credentialID, "A")
        XCTAssertEqual(spTokenEntries[0].data, mockToken.data)
        XCTAssertEqual(spTokenEntries[1].credentialID, "B")
        XCTAssertEqual(spTokenEntries[1].data, mockToken.data)
    }
    
    func testBlueStoreSpTokenInPreviousSDKVersion() throws {
        let mockToken = try createMockToken()
        
        // In the previous version, the token is stored as raw Data.
        try blueTerminalRequestDataKeychain.storeEntry(id: "test:PING", data: mockToken.data)
        
        var credentialA = blueCreateAccessCredentialDemo()
        credentialA.credentialID.id = "A"
        
        try blueStoreSpToken(credential: credentialA, deviceID: "test", token: mockToken.base64)
        
        let entry = try blueGetSpTokenEntry("test:PING")
        XCTAssert(entry is [BlueSPTokenEntry], "Wrong type")
        
        let spTokenEntries = entry as! [BlueSPTokenEntry]
        XCTAssertEqual(spTokenEntries.count, 1)
        XCTAssertEqual(spTokenEntries[0].credentialID, "A")
        XCTAssertEqual(spTokenEntries[0].data, mockToken.data)
    }
    
    func testBlueGetSpToken() throws {
        let mockToken = try createMockToken()
        
        var credentialA = blueCreateAccessCredentialDemo()
        credentialA.credentialID.id = "A"
        
        var credentialB = blueCreateAccessCredentialDemo()
        credentialB.credentialID.id = "B"
        
        try blueStoreSpToken(credential: credentialA, deviceID: "test", token: mockToken.base64)
        try blueStoreSpToken(credential: credentialB, deviceID: "test", token: mockToken.base64)
        
        let storedSpToken = try blueGetSpToken("test:PING")
        XCTAssertNotNil(storedSpToken)
        XCTAssertNotNil(storedSpToken?.command.credentialID, "A")
    }
    
    func testBlueGetSpTokenInPreviousSDKVersion() throws {
        let mockToken = try createMockToken()
        
        // In the previous version, the token is stored as raw Data.
        try blueTerminalRequestDataKeychain.storeEntry(id: "test:PING", data: mockToken.data)
        
        let storedSpToken = try blueGetSpToken("test:PING")
        XCTAssertNotNil(storedSpToken)
        XCTAssertEqual(storedSpToken?.command.credentialID.id, "DEMOIDENTI")
    }
    
    func testBlueDeleteSpTokens() throws {
        let mockToken = try createMockToken()
        
        var credentialA = blueCreateAccessCredentialDemo()
        credentialA.credentialID.id = "A"
        
        var credentialB = blueCreateAccessCredentialDemo()
        credentialB.credentialID.id = "B"
        
        try blueStoreSpToken(credential: credentialA, deviceID: "test", token: mockToken.base64)
        try blueStoreSpToken(credential: credentialB, deviceID: "test", token: mockToken.base64)
        
        try blueDeleteSpTokens(credential: credentialA)
        
        let entry = try blueGetSpTokenEntry("test:PING")
        XCTAssert(entry is [BlueSPTokenEntry], "Wrong type")
        
        let spTokenEntries = entry as! [BlueSPTokenEntry]
        XCTAssertEqual(spTokenEntries.count, 1)
        XCTAssertEqual(spTokenEntries[0].credentialID, "B")
        XCTAssertEqual(spTokenEntries[0].data, mockToken.data)
        
        try blueDeleteSpTokens(credential: credentialB)
        XCTAssertNil(try blueGetSpTokenEntry("test:PING"))
    }
    
    func testBlueDeleteSpTokensInPreviousSDKVersion() throws {
        let mockToken = try createMockToken()
        
        var credentialA = blueCreateAccessCredentialDemo()
        credentialA.credentialID.id = "A"
        
        // In the previous version, the token is stored as raw Data.
        try blueTerminalRequestDataKeychain.storeEntry(id: "test:PING", data: mockToken.data)
        
        try blueDeleteSpTokens(credential: credentialA)
        
        let entry = try blueGetSpTokenEntry("test:PING")
        XCTAssertNil(entry)
    }
}

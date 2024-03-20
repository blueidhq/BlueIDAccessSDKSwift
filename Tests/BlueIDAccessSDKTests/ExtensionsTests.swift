import XCTest

@testable import BlueIDAccessSDK

private func toJSON(_ json: String) -> Data { return json.data(using: .utf8)! }

final class BlueAccessCredentialDecodableExtensionTests: BlueXCTestCase {
    
    func testMissingCredentialId() async {
        let json = "{\"credentialType\": \"regular\", \"siteId\": 1, \"organisation\": \"1\"}"
        
        await XCTAssertThrowsError(try JSONDecoder().decode(BlueAccessCredential.self, from: toJSON(json))) { error in
            XCTAssert(error is DecodingError)
        }
    }
    
    func testCredentialTypes() async {
        let testCases: [(String, Bool)] = [
            ("regular", true),
            ("maintenance", true),
            ("nfcWriter", true),
            ("master", true),
            ("unknown", false)
        ]
        
        for testCase in testCases {
            let (credentialType, isValid) = testCase
            
            let json = "{\"credentialId\": \"1\", \"credentialType\": \"\(credentialType)\", \"siteId\": 1, \"organisation\": \"1\"}"
            
            if (isValid) {
                _ = await XCTAssertNotThrowsError(try JSONDecoder().decode(BlueAccessCredential.self, from: toJSON(json)))
            } else {
                await XCTAssertThrowsError(try JSONDecoder().decode(BlueAccessCredential.self, from: toJSON(json))) { error in
                    XCTAssert(error is BlueError)
                    XCTAssertEqual((error as! BlueError).returnCode, .invalidState)
                }
            }
        }
    }
    
    func testMissingSiteID() async {
        let json = "{\"credentialId\": \"1\", \"credentialType\": \"regular\", \"organisation\": \"1\"}"
        
        await XCTAssertThrowsError(try JSONDecoder().decode(BlueAccessCredential.self, from: toJSON(json))) { error in
            XCTAssert(error is DecodingError)
        }
    }
    
    func testMissingOrganisation() async {
        let json = "{\"credentialId\": \"1\", \"credentialType\": \"regular\", \"siteId\": \"1\"}"
        
        await XCTAssertThrowsError(try JSONDecoder().decode(BlueAccessCredential.self, from: toJSON(json))) { error in
            XCTAssert(error is DecodingError)
        }
    }
    
    func testMissingOptionalFields() async {
        let json = "{\"credentialId\": \"1\", \"credentialType\": \"regular\", \"siteId\": 1, \"organisation\": \"1\"}"
        
        let credential = await XCTAssertNotThrowsError(try JSONDecoder().decode(BlueAccessCredential.self, from: toJSON(json)))
        
        XCTAssertNotNil(credential)
        XCTAssertFalse(credential!.hasValidFrom)
        XCTAssertFalse(credential!.hasValidTo)
        XCTAssertFalse(credential!.hasValidity)
        XCTAssertFalse(credential!.hasPrivateKey)
    }
    
    func testBlueLocalTimestampToUTCDate() {
        XCTAssertEqual(BlueLocalTimestamp.fromUTCDate(Date(timeIntervalSince1970: 1704285000)).toUTCDate(), Date(timeIntervalSince1970: 1704285000))
    }
}

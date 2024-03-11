import XCTest

@testable import BlueIDAccessSDK

final class BlueAddAccessCredentialCommandTests: BlueXCTestCase {
    
    func testBlueAddAccessCredentialCommand() async throws {
        let credential = blueCreateAccessCredentialDemo()
        
        do {
            try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        } catch {
            XCTFail("Should not throw any errors when adding the credential for the first time")
        }
        
        let storedAccessCredentialData = try BlueKeychain(attrService: "blueid.accessCredentials").getEntry(id: "8M-1xA3oze")
        
        XCTAssertNotNil(storedAccessCredentialData, "Stored access credential data should not be null")
       
        let storedCredential = try BlueAccessCredential(jsonUTF8Data: storedAccessCredentialData! as Data)
        
        XCTAssertEqual(storedCredential.credentialID.id, credential.credentialID.id, "Credential ID should be equal")
        XCTAssertEqual(storedCredential.credentialType, credential.credentialType, "Credential type should be equal")
        XCTAssertEqual(storedCredential.privateKey, credential.privateKey, "Private key should be equal")
    }
    
    func testUpdateAccessCredentialCommand() async throws {
        let credential = blueCreateAccessCredentialDemo()
        
        do {
            try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        } catch {
            XCTFail("Should not throw any errors when adding the credential for the first time")
        }
        
        do {
            try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        } catch {
            XCTFail("Should not throw any errors when updating the same credential")
        }
        
        XCTAssertEqual(try BlueKeychain(attrService: "blueid.accessCredentials").getEntryIds(), ["8M-1xA3oze"], "there should be only one entry ID")
    }
}

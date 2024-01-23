import XCTest

@testable import BlueIDAccessSDK

final class BlueAccessTests: BlueXCTestCase {
    func testGetAccessCredentialByCredentialID() async throws {
        var credential = blueCreateAccessCredentialDemo()
        credential.credentialID.id = "credential-1"
        
        try await BlueAddAccessCredentialCommand(DefaultBlueAPIMock()).runAsync(credential: credential)
        
        var returnedCredential = blueGetAccessCredential(credentialID: "credential-1")
        XCTAssertNotNil(returnedCredential)
        XCTAssertEqual(returnedCredential?.credentialID.id, "credential-1")
        
        returnedCredential = blueGetAccessCredential(credentialID: "credential-2")
        XCTAssertNil(returnedCredential)
    }
    
    func testGetAccessCredentialWithMoreFilters() async throws {
        var credential = blueCreateAccessCredentialDemo()
        credential.credentialID.id = "credential-1"
        credential.organisation = "organisation-1"
        credential.credentialType = .nfcWriter
        credential.siteID = 1
        
        try await BlueAddAccessCredentialCommand(DefaultBlueAPIMock()).runAsync(credential: credential)
        
        var returnedCredential = blueGetAccessCredential(organisation: "organisation-1", siteID: 1, credentialType: .nfcWriter)
        XCTAssertNotNil(returnedCredential)
        XCTAssertEqual(returnedCredential?.credentialID.id, "credential-1")
        
        returnedCredential = blueGetAccessCredential(organisation: "organisation-1", siteID: 1, credentialType: .maintenance)
        XCTAssertNil(returnedCredential)
        
        returnedCredential = blueGetAccessCredential(organisation: "organisation-1", siteID: 10, credentialType: .nfcWriter)
        XCTAssertNil(returnedCredential)
        
        returnedCredential = blueGetAccessCredential(organisation: "organisation-2", siteID: 1, credentialType: .nfcWriter)
        XCTAssertNil(returnedCredential)
    }
}

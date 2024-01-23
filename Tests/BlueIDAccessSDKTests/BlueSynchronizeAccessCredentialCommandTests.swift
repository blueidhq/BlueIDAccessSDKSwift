import XCTest

@testable import BlueIDAccessSDK

private class BlueAPIMock: DefaultBlueAPIMock {
    var synchronizeNfcAccessWasCalled: Bool = false
    var synchronizeMobileAccessWasCalled: Bool = false
    
    override func synchronizeNfcAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueNfcAccessSynchronizationResult> {
        synchronizeNfcAccessWasCalled = true
        
        return BlueFetchResponse(
            statusCode: 200
        )
    }
    
    override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        synchronizeMobileAccessWasCalled = true
        
        return BlueFetchResponse(
            statusCode: 200
        )
    }
}

final class BlueSynchronizeAccessCredentialCommandTests: BlueXCTestCase {
    func testRunAsyncWithNfcCredential() async throws {
        var credential = blueCreateAccessCredentialDemo()
        credential.credentialType = .nfcWriter
        
        try await BlueAddAccessCredentialCommand(DefaultBlueAPIMock()).runAsync(credential: credential)
        
        let apiMock = BlueAPIMock()
        
        try await BlueSynchronizeAccessCredentialCommand(apiMock).runAsync(credentialID: credential.credentialID.id)
        
        XCTAssertTrue(apiMock.synchronizeNfcAccessWasCalled)
    }
    
    func testRunAsyncWithNonNfcCredential() async throws {
        let testCases: [BlueCredentialType] = [
            .maintenance,
            .master,
            .regular
        ]
        
        for credentialType in testCases {
            var credential = blueCreateAccessCredentialDemo()
            credential.credentialType = credentialType
            
            try await BlueAddAccessCredentialCommand(DefaultBlueAPIMock()).runAsync(credential: credential)
            
            let apiMock = BlueAPIMock()
            
            try await BlueSynchronizeAccessCredentialCommand(apiMock).runAsync(credentialID: credential.credentialID.id)
            
            XCTAssertTrue(apiMock.synchronizeMobileAccessWasCalled)
        }
    }
}

import XCTest

@testable import BlueIDAccessSDK

private class BlueAPIMock: DefaultBlueAPIMock {
    var synchronizeNfcAccessWasCalled: Bool = false
    var synchronizeMobileAccessWasCalled: Bool = false
    
    override func synchronizeNfcAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueNfcAccessSynchronizationResult> {
        synchronizeNfcAccessWasCalled = true
        
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueNfcAccessSynchronizationResult()
        )
    }
    
    override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        synchronizeMobileAccessWasCalled = true
        
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueMobileAccessSynchronizationResult(
                siteId: 1,
                validity: 0,
                tokens: [],
                deviceTerminalPublicKeys: [:]
            )
        )
    }
}

final class BlueSynchronizeAccessCredentialCommandTests: BlueXCTestCase {
    func testRunAsyncWithNfcCredential() async throws {
        var credential = blueCreateAccessCredentialDemo()
        credential.credentialType = .nfcWriter
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        
        let apiMock = BlueAPIMock()
        
        try await BlueSynchronizeAccessCredentialCommand(BlueSdkService(apiMock, BlueDefaultAccessEventServiceMock())).runAsync(credentialID: credential.credentialID.id)
        
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
            
            try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
            
            let apiMock = BlueAPIMock()
            
            try await BlueSynchronizeAccessCredentialCommand(BlueSdkService(apiMock, BlueDefaultAccessEventServiceMock())).runAsync(credentialID: credential.credentialID.id)
            
            XCTAssertTrue(apiMock.synchronizeMobileAccessWasCalled)
        }
    }
}

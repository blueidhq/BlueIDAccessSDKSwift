import XCTest

@testable import BlueIDAccessSDK

private struct BlueSynchronizationResponseMock: BlueSynchronizationResponse {
    var credentialId: String?
    var noRefresh: Bool?
}

private class BlueAbstractSynchronizeAccessCommandMock: BlueAbstractSynchronizeAccessCommand<BlueSynchronizationResponseMock> {
    var purged: Bool = false
    var synced: Bool = false
    var updated: Bool = false
    var statusCode = 200
    var data: BlueSynchronizationResponseMock?
    
    init(statusCode: Int? = 200, data: BlueSynchronizationResponseMock? = BlueSynchronizationResponseMock()) {
        self.statusCode = statusCode ?? 200
        self.data = data
  
        super.init(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
    }
    
    override func sync(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueSynchronizationResponseMock> {
        synced = true
        
        return BlueFetchResponse(
            statusCode: statusCode,
            data: data
        )
    }
    
    override func update(_ credential: BlueAccessCredential, _ synchronizationResult: BlueSynchronizationResponseMock) throws {
        updated = true
    }
    
    override func purge(_ credential: BlueAccessCredential) throws {
        purged = true
    }
}

private class BlueAbstractSynchronizeAccessCommandOfflineMock: BlueAbstractSynchronizeAccessCommandMock {
    override func sync(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueSynchronizationResponseMock> {
        throw BlueError(.error)
    }
}

final class BlueAbstractSynchronizeAccessCommandTests: BlueXCTestCase {
    func testRunAsyncWithMissingCredential() async {
        let command = BlueAbstractSynchronizeAccessCommandMock()
        
        await XCTAssertThrowsError(try await command.runAsync(credentialID: "")) {error in
            XCTAssert(error is BlueError)
            XCTAssertEqual((error as! BlueError).returnCode, .sdkCredentialNotFound)
        }
        
        XCTAssertFalse(command.purged, "purge function should NOT have been called")
        XCTAssertFalse(command.updated, "update function should NOT have been called")
    }
    
    func testRunAsyncOffline() async throws {
        let command = BlueAbstractSynchronizeAccessCommandOfflineMock()
        
        let credential = blueCreateAccessCredentialDemo()
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: try credential.jsonUTF8Data())
        
        await XCTAssertNotThrowsError(try await command.runAsync(credentialID: credential.credentialID.id))
        XCTAssertFalse(command.purged, "purge function should NOT have been called")
        XCTAssertFalse(command.updated, "update function should NOT have been called")
    }
    
    func testRunAsyncOfflineWithExpiredValidToDate() async throws {
        let command = BlueAbstractSynchronizeAccessCommandOfflineMock()
        
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        var credential = blueCreateAccessCredentialDemo()
        credential.validTo = BlueLocalTimestamp(yesterday!)
        
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: try credential.jsonUTF8Data())
        
        await XCTAssertNotThrowsError(try await command.runAsync(credentialID: credential.credentialID.id))
        XCTAssertTrue(command.purged, "purge function should have been called")
        XCTAssertFalse(command.updated, "update function should NOT have been called")
    }
    
    func testRunAsyncWith401StatusCode() async throws {
        let command = BlueAbstractSynchronizeAccessCommandMock(statusCode: 401)
        
        let credential = blueCreateAccessCredentialDemo()
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: try credential.jsonUTF8Data())
        
        await XCTAssertNotThrowsError(try await command.runAsync(credentialID: credential.credentialID.id))
        XCTAssertTrue(command.purged, "purge function should have been called")
        XCTAssertFalse(command.updated, "update function should NOT have been called")
    }
    
    func testRunAsyncWithNoRefresh() async throws {
        let command = BlueAbstractSynchronizeAccessCommandMock(
            data: BlueSynchronizationResponseMock(noRefresh: true)
        )
        
        let credential = blueCreateAccessCredentialDemo()
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: try credential.jsonUTF8Data())
        
        await XCTAssertNotThrowsError(try await command.runAsync(credentialID: credential.credentialID.id))
        XCTAssertFalse(command.purged, "purge function should NOT have been called")
        XCTAssertFalse(command.updated, "update function should NOT have been called")
    }
    
    func testRunAsyncWithResponseData() async throws {
        let command = BlueAbstractSynchronizeAccessCommandMock(
            data: BlueSynchronizationResponseMock()
        )
        
        let credential = blueCreateAccessCredentialDemo()
        try blueAccessCredentialsKeyChain.storeEntry(id: credential.credentialID.id, data: try credential.jsonUTF8Data())
        
        await XCTAssertNotThrowsError(try await command.runAsync(credentialID: credential.credentialID.id))
        XCTAssertFalse(command.purged, "purge function should NOT have been called")
        XCTAssertTrue(command.updated, "update function should have been called")
    }
}

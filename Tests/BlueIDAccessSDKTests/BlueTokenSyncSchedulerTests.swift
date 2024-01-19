import XCTest

@testable import BlueIDAccessSDK

private class ViewMock: BlueEventListener {
    var tokenSyncStartedCalled: Bool = false
    var tokenSyncFinishedCalled: Bool = false
    
    init() {
        blueAddEventListener(listener: self)
    }
    
    deinit {
        blueRemoveEventListener(listener: self)
    }
    
    func blueEvent(event: BlueEventType, data: Any?) {
        if (event == .tokenSyncStarted) {
            tokenSyncStartedCalled = true
        }
        else if (event == .tokenSyncFinished) {
            tokenSyncFinishedCalled = true
        }
    }
}

final class BlueTokenSyncSchedulerTests: BlueXCTestCase {
    func testWithoutAccessCredentials() async throws {
        _ = try? blueAccessCredentialsKeyChain.deleteAllEntries()
        
        let viewMock = ViewMock()
        
        let scheduler = BlueTokenSyncScheduler(
            timeInterval: 1,
            autoSchedule: false,
            command: BlueSynchronizeAccessCredentialCommand(DefaultBlueAPIMock())
        )
        
        defer {
            scheduler.suspend()
        }
        
        scheduler.setup()
        
        let expectation = XCTestExpectation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 10)
        
        XCTAssertFalse(viewMock.tokenSyncStartedCalled, "TokenSyncStarted event should not be triggered")
        XCTAssertFalse(viewMock.tokenSyncFinishedCalled, "TokenSyncFinished event should not be triggered")
    }
    
    func testAddAccessCredential() async throws {
        let viewMock = ViewMock()
        
        let scheduler = BlueTokenSyncScheduler(
            timeInterval: 1,
            autoSchedule: false,
            command: BlueSynchronizeAccessCredentialCommand(DefaultBlueAPIMock())
        )
        
        defer {
            scheduler.suspend()
        }

        try await BlueAddAccessCredentialCommand(DefaultBlueAPIMock()).runAsync(credential: blueCreateAccessCredentialDemo())
        
        let expectation = XCTestExpectation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 10)
        
        XCTAssertTrue(viewMock.tokenSyncStartedCalled, "TokenSyncStarted event should be triggered")
        XCTAssertTrue(viewMock.tokenSyncFinishedCalled, "TokenSyncFinished event should be triggered")
    }
}

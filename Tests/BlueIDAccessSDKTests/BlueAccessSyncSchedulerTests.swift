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
        let viewMock = ViewMock()
        
        let scheduler = BlueAccessSyncScheduler(
            timeInterval: 1,
            autoSchedule: false,
            command: BlueSynchronizeAccessCredentialsCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
        )
        
        addTeardownBlock {
            scheduler.suspend()
        }
        
        scheduler.schedule()
        
        let expectation = XCTestExpectation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 10)
        
        XCTAssertFalse(viewMock.tokenSyncStartedCalled, "TokenSyncStarted event should not be triggered")
        XCTAssertFalse(viewMock.tokenSyncFinishedCalled, "TokenSyncFinished event should not be triggered")
    }
    
    func testAddAccessCredential() async throws {
        let viewMock = ViewMock()
        
        let scheduler = BlueAccessSyncScheduler(
            timeInterval: 1,
            autoSchedule: false,
            command: BlueSynchronizeAccessCredentialsCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
        )
        
        addTeardownBlock {
            scheduler.suspend()
        }

        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: blueCreateAccessCredentialDemo())
        
        let expectation = XCTestExpectation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 10)
        
        XCTAssertTrue(viewMock.tokenSyncStartedCalled, "TokenSyncStarted event should be triggered")
        XCTAssertTrue(viewMock.tokenSyncFinishedCalled, "TokenSyncFinished event should be triggered")
    }
    
    func testWithAccessCredentiaslWithValidFrom() async throws {
        let now = Date()
        let validFrom = now.addingTimeInterval(2)
        
        let credential = blueCreateAccessCredentialDemo(
            validFrom: BlueLocalTimestamp.fromUTCDate(validFrom)
        )
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        
        let viewMock = ViewMock()
        
        let scheduler = BlueAccessSyncScheduler(
            timeInterval: TimeInterval.infinity,
            autoSchedule: false,
            command: BlueSynchronizeAccessCredentialsCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
        )
        
        addTeardownBlock {
            scheduler.suspend()
        }
        
        scheduler.schedule()
        
        let expectation = XCTestExpectation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 10)
        
        XCTAssertTrue(viewMock.tokenSyncStartedCalled, "TokenSyncStarted event should be triggered")
        XCTAssertTrue(viewMock.tokenSyncFinishedCalled, "TokenSyncFinished event should be triggered")
    }
    
    func testCalculateNextInterval() async throws {
        let now = Date()
        
        let storedCredential = blueCreateAccessCredentialDemo(
            id: "A",
            validFrom: BlueLocalTimestamp.fromUTCDate(now.addingTimeInterval(120))
        )
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: storedCredential)
        
        let scheduler = BlueAccessSyncScheduler(
            timeInterval: TimeInterval.infinity,
            autoSchedule: false,
            command: BlueSynchronizeAccessCredentialsCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
        )
        
        var expected = storedCredential.validFrom.toUTCDate()!.timeIntervalSince(now)

        XCTAssertEqual(scheduler.calculateNextInterval(now), expected)
        
        let newCredential = blueCreateAccessCredentialDemo(
            id: "B",
            validFrom: BlueLocalTimestamp.fromUTCDate(now.addingTimeInterval(30))
        )
        try await BlueAddAccessCredentialCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(credential: newCredential)
        
        expected = newCredential.validFrom.toUTCDate()!.timeIntervalSince(now)

        XCTAssertEqual(scheduler.calculateNextInterval(now), expected)
    }
}

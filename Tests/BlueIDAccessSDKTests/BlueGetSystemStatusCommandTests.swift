import XCTest

@testable import BlueIDAccessSDK


final class BlueGetSystemStatusCommandTests: BlueXCTestCase {
    func testUpdateFirmwareFlags() {
        var status = BlueSystemStatus()
        status.applicationVersion = 1
        status.clearApplicationVersionTest()
        
        BlueGetSystemStatusCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: nil,
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.applicationVersionTest = 106
        BlueGetSystemStatusCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: nil,
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.applicationVersionTest = 105
        BlueGetSystemStatusCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: nil,
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertFalse(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.clearApplicationVersionTest()
        BlueGetSystemStatusCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: BlueLatestFirmwareInfo(version: 1, testVersion: nil, url: ""),
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 2
        status.clearApplicationVersionTest()
        BlueGetSystemStatusCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: BlueLatestFirmwareInfo(version: 1, testVersion: nil, url: ""),
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertTrue(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.applicationVersionTest = 106
        BlueGetSystemStatusCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: BlueLatestFirmwareInfo(version: 1, testVersion: nil, url: ""),
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertTrue(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
    }
}

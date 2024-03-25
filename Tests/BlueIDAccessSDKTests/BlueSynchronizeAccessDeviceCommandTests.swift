import XCTest

@testable import BlueIDAccessSDK


final class BlueSynchronizeAccessDeviceCommandTests: BlueXCTestCase {
    func testUpdateFirmwareFlags() {
        var status = BlueSystemStatus()
        status.applicationVersion = 1
        status.clearApplicationVersionTest()
        
        BlueSynchronizeAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: nil,
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.applicationVersionTest = 106
        BlueSynchronizeAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: nil,
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.applicationVersionTest = 105
        BlueSynchronizeAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: nil,
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertFalse(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.clearApplicationVersionTest()
        BlueSynchronizeAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: BlueLatestFirmwareInfo(version: 1, testVersion: nil, url: ""),
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertFalse(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 2
        status.clearApplicationVersionTest()
        BlueSynchronizeAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: BlueLatestFirmwareInfo(version: 1, testVersion: nil, url: ""),
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertTrue(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
        
        
        status.applicationVersion = 1
        status.applicationVersionTest = 106
        BlueSynchronizeAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()))
            .updateFirmwareFlags(&status, BlueGetLatestFirmwareResult(
                production: BlueLatestFirmwareInfo(version: 1, testVersion: nil, url: ""),
                test: BlueLatestFirmwareInfo(version: 1, testVersion: 105, url: "")
            )
        )
        XCTAssertTrue(status.newFirmwareVersionAvailable)
        XCTAssertTrue(status.newTestFirmwareVersionAvailable)
    }
}

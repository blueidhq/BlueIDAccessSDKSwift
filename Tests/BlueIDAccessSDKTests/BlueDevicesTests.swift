import XCTest

@testable import BlueIDAccessSDK

final class BlueDevicesTests: BlueXCTestCase {
    func testBlueSetMaxDeviceAgeSeconds() {
        XCTAssertEqual(maxDeviceAgeSeconds, 10)
        
        blueSetMaxDeviceAgeSeconds(0)
        XCTAssertEqual(maxDeviceAgeSeconds, 1)
        
        blueSetMaxDeviceAgeSeconds(-1)
        XCTAssertEqual(maxDeviceAgeSeconds, 1)
        
        blueSetMaxDeviceAgeSeconds(5)
        XCTAssertEqual(maxDeviceAgeSeconds, 5)
        
        blueSetMaxDeviceAgeSeconds(120)
        XCTAssertEqual(maxDeviceAgeSeconds, 120)
    }
}

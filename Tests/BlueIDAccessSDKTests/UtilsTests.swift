import XCTest
import SwiftProtobuf

@testable import BlueIDAccessSDK

final class InternalUtilsTests: XCTestCase {
    let binaryTestContent = Data([
        0x20, 0x0A, 0x0B, 0x42, 0x6C, 0x75, 0x65, 0x49, 0x44, 0x20, 0x47, 0x6D, 0x62, 0x48, 0x12, 0x0D,
        0x4D, 0x61, 0x67, 0x69, 0x63, 0x20, 0x55, 0x6E, 0x69, 0x63, 0x6F, 0x72, 0x6E, 0x18, 0x01, 0x20,
        0x02,
        // -- some dummy data here to ensure it correctly decodes --
        0x33,
        0x21,
        0x66,
    ])
    
    func testEncodeMessage() throws {
        var testData = _BlueTestEncodeDecode()
        testData.vendor = "BlueID GmbH"
        testData.hardwareName = "Magic Unicorn"
        testData.hardwareVersion = 1
        testData.applicationVersion = 2
        
        let data = try blueEncodeMessage(testData)
        
        XCTAssertEqual(data.prefix(data.count), binaryTestContent.prefix(data.count))
    }
    
    func testDecodeMessage() throws {
        let testData: _BlueTestEncodeDecode = try blueDecodeMessage(binaryTestContent)
        
        XCTAssertNotNil(testData)
        
        XCTAssertEqual(testData.vendor, "BlueID GmbH")
        XCTAssertEqual(testData.hardwareName, "Magic Unicorn")
        XCTAssertEqual(testData.hardwareVersion, 1)
        XCTAssertEqual(testData.applicationVersion, 2)
    }
    
    func testIBeaconMajorMinorToId() {
        XCTAssertEqual(blueIBeaconMajorMinorToId(major: 30561, minor: 12409), "wa0y")
    }
}

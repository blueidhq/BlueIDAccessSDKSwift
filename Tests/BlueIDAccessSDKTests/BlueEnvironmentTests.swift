import XCTest

@testable import BlueIDAccessSDK

final class BlueEnvironmentTests: BlueXCTestCase {
    
    func testGetEnvVar() {
        XCTAssertEqual(BlueEnvironment.getEnvVar(key: "DOES_NOT_EXIST", defaultValue: "nothing"), "nothing")
        XCTAssertEqual(BlueEnvironment.getEnvVar(key: "CFBundleName", defaultValue: "nothing"), "xctest")
    }
}

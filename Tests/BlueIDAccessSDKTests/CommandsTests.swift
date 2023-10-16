import XCTest

@testable import BlueIDAccessSDK

final class CommandsTests: XCTestCase {
    func testRunCommand() async throws {
        let versionInfoData = try await blueRunCommand("versionInfo")
        
        guard let versionInfoData = versionInfoData as? Data else {
            XCTAssert(false)
            return
        }
        
        let versionInfo: BlueVersionInfo = try blueDecodeMessage(versionInfoData)
        
        XCTAssertEqual(versionInfo.version, 1);
    }
}

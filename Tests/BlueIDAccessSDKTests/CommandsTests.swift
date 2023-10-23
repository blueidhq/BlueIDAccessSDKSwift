import XCTest

@testable import BlueIDAccessSDK

final class CommandsTests: XCTestCase {
    func testRunCommand() async throws {
        _ = try await blueRunCommand("initialize")
        
        let commandResult: BlueCommandResult = try await blueRunCommand("versionInfo")
        
        XCTAssertEqual(commandResult.messageTypeName, "BlueVersionInfo")
        
        guard let versionInfoData = commandResult.data as? Data else {
            XCTAssert(false)
            return
        }
        
        let versionInfo: BlueVersionInfo = try blueDecodeMessage(versionInfoData)
        
        XCTAssertEqual(versionInfo.version, 1);
    }
}

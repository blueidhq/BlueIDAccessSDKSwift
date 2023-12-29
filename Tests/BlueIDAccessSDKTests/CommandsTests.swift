import XCTest

@testable import BlueIDAccessSDK

final class CommandsTests: BlueXCTestCase {
    func testRunCommand() async throws {
        let commandResult: BlueCommandResult = try await blueRunCommand("versionInfo")
        
        XCTAssertEqual(commandResult.messageTypeName, "BlueVersionInfo")
        
        guard let versionInfoData = commandResult.data as? Data else {
            XCTAssert(false)
            return
        }
        
        let versionInfo: BlueVersionInfo = try blueDecodeMessage(versionInfoData)
        
        XCTAssertEqual(versionInfo.version, 1);
    }
    
    func testRunGetAccessCredentialsCommand() async throws {
        let arg0: Any? = NSNull()
        let arg1: Data? = nil
        
        let commandResult: BlueCommandResult = try await blueRunCommand("getAccessCredentials", arg0: arg0, arg1: arg1)
        
        XCTAssertEqual(commandResult.messageTypeName, "BlueAccessCredentialList")
        
        guard let credentialListData = commandResult.data as? Data else {
            XCTAssert(false)
            return
        }
        
        let credentialList: BlueAccessCredentialList = try blueDecodeMessage(credentialListData)
        
        XCTAssertNotNil(credentialList)
    }
    
    func testRunListAccessDevicesCommand() async throws {
        let commandResult1 = try? await blueRunCommand("listAccessDevices")
        XCTAssertNil(commandResult1, "Should be null due to missing credential type argument")
        
        let commandResult2: BlueCommandResult = try await blueRunCommand("listAccessDevices", arg0: BlueCredentialType.maintenance.rawValue)
        XCTAssertEqual(commandResult2.messageTypeName, "BlueAccessDeviceList", "Wrong message type name")
        XCTAssertNotNil(commandResult2.data, "Data should not be null")
        
        let deviceList: BlueAccessDeviceList = try blueDecodeMessage(commandResult2.data as! Data)
        XCTAssertNotNil(deviceList, "Device list should not be null")
    }
}

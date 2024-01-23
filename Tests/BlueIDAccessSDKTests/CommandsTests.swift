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
    
    func testIsBluetoothActive() async throws {
        let commandResult: BlueCommandResult = try await blueRunCommand("isBluetoothActive")
        XCTAssertEqual(commandResult.data as! Bool, false)
    }
    
    func testRunGetAccessCredentialsCommand() async throws {
        let credential = blueCreateAccessCredentialDemo()
        try await BlueAddAccessCredentialCommand(DefaultBlueAPIMock()).runAsync(credential: credential)
        
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
        XCTAssertEqual(credentialList.credentials.count, 1)
    }
    
    func testRunListAccessDevicesCommand() async throws {
        let commandResult1 = try await blueRunCommand("listAccessDevices")
        XCTAssertEqual(commandResult1.messageTypeName, "BlueAccessDeviceList", "Wrong message type name")
        XCTAssertNotNil(commandResult1.data, "Data should not be null")
        
        let deviceList1: BlueAccessDeviceList = try blueDecodeMessage(commandResult1.data as! Data)
        XCTAssertNotNil(deviceList1, "Device list should not be null")
        
        let commandResult2 = try await blueRunCommand("listAccessDevices", arg0: BlueCredentialType.maintenance.rawValue)
        XCTAssertEqual(commandResult2.messageTypeName, "BlueAccessDeviceList", "Wrong message type name")
        XCTAssertNotNil(commandResult2.data, "Data should not be null")
        
        let deviceList2: BlueAccessDeviceList = try blueDecodeMessage(commandResult2.data as! Data)
        XCTAssertNotNil(deviceList2, "Device list should not be null")
    }
    
    func testRunUNSAFE_clearDataCommand() async throws {
        await XCTAssertNotThrowsError(try await blueRunCommand("UNSAFE_clearData"))
    }
}

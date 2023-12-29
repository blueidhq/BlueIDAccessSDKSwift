import XCTest

@testable import BlueIDAccessSDK

final class BlueListAccessDevicesCommandTests: BlueXCTestCase {
    
    func testListAccessDevices() async throws {
        class BlueAPIMock: DefaultBlueAPIMock {
            let tokens: [BlueAccessDeviceToken]
            
            init(tokens: [BlueAccessDeviceToken]) { self.tokens = tokens }
            
            override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
                return BlueFetchResponse(
                    statusCode: 200,
                    data: BlueMobileAccessSynchronizationResult(
                        siteId: 1,
                        validity: 0,
                        tokens: tokens,
                        deviceTerminalPublicKeys: [:]
                    )
                )
            }
        }
        
        var credential1 = blueCreateAccessCredentialDemo()
        credential1.credentialID.id = "maintenance-1"
        credential1.credentialType = .maintenance
        
        var credential2 = blueCreateAccessCredentialDemo()
        credential2.credentialID.id = "maintenance-2"
        credential1.credentialType = .maintenance
        
        var credential3 = blueCreateAccessCredentialDemo()
        credential3.credentialID.id = "regular"
        credential3.credentialType = .regular
        
        let commandForCredential1 = BlueAddAccessCredentialCommand(BlueAPIMock(
            tokens: [
                BlueAccessDeviceToken(
                    deviceId: "device-for-maintenance-1",
                    objectId: 1,
                    token: try blueEncodeMessage(try blueCreateSignedCommandDemoToken("MAINTC")).base64EncodedString()
                )
            ])
        )
        
        let commandForCredential2 = BlueAddAccessCredentialCommand(BlueAPIMock(
            tokens: [
                BlueAccessDeviceToken(
                    deviceId: "device-for-maintenance-2",
                    objectId: 1,
                    token: try blueEncodeMessage(try blueCreateSignedCommandDemoToken("MAINTC")).base64EncodedString()
                )
            ])
        )
        
        let commandForCredential3 = BlueAddAccessCredentialCommand(BlueAPIMock(
            tokens: [
                BlueAccessDeviceToken(
                    deviceId: "device-for-regular-1",
                    objectId: 1,
                    token: try blueEncodeMessage(try blueCreateSignedCommandDemoToken("PING")).base64EncodedString()
                ),
                BlueAccessDeviceToken(
                    deviceId: "device-for-regular-2",
                    objectId: 1,
                    token: try blueEncodeMessage(try blueCreateSignedCommandDemoToken("PING")).base64EncodedString()
                ),
                BlueAccessDeviceToken(
                    deviceId: "device-for-regular-3",
                    objectId: 1,
                    token: try blueEncodeMessage(try blueCreateSignedCommandDemoToken("PING")).base64EncodedString()
                ),
            ])
        )
        
        try? await commandForCredential1.runAsync(credential: credential1)
        try? await commandForCredential2.runAsync(credential: credential2)
        try? await commandForCredential3.runAsync(credential: credential3)
        
        let maintenanceDeviceList = try? await BlueListAccessDevicesCommand().runAsync(credentialType: .maintenance)
        XCTAssertNotNil(maintenanceDeviceList, "Should not be null")
        XCTAssertEqual(maintenanceDeviceList?.devices.count, 2, "There should be 2 devices")
        XCTAssertEqual(maintenanceDeviceList?.devices[0].deviceID, "device-for-maintenance-1", "Wrong device ID")
        XCTAssertEqual(maintenanceDeviceList?.devices[1].deviceID, "device-for-maintenance-2", "Wrong device ID")
        
        let regularDeviceList = try? await BlueListAccessDevicesCommand().runAsync(credentialType: .regular)
        XCTAssertNotNil(regularDeviceList, "Should not be null")
        XCTAssertEqual(regularDeviceList?.devices.count, 3, "There should be 3 devices")
        XCTAssertEqual(regularDeviceList?.devices[0].deviceID, "device-for-regular-1", "Wrong device ID")
        XCTAssertEqual(regularDeviceList?.devices[1].deviceID, "device-for-regular-2", "Wrong device ID")
        XCTAssertEqual(regularDeviceList?.devices[2].deviceID, "device-for-regular-3", "Wrong device ID")
    }
}

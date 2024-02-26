import XCTest

@testable import BlueIDAccessSDK

private class BlueAPIMock: DefaultBlueAPIMock {
    private let token: BlueSPToken
    
    init(_ token: BlueSPToken) {
        self.token = token
    }
    
    override func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool? = nil) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        return BlueFetchResponse(
            statusCode: 200,
            data: BlueMobileAccessSynchronizationResult(
                siteId: 1,
                validity: 0,
                tokens: [
                    BlueAccessDeviceToken(
                        deviceId: "device-1",
                        objectId: 1,
                        token: try blueEncodeMessage(token).base64EncodedString()
                    ),
                ],
                deviceTerminalPublicKeys: [
                    "device-1": "public-key-1".data(using: .utf8)!.base64EncodedString(),
                ]
            )
        )
    }
}

private class BlueTerminalMock {
    var actionCalled: String = ""
    
    func terminalRun(deviceID: String, timeout: Double, action: String) -> BlueOssAccessResult {
        actionCalled = action
        
        return BlueOssAccessResult()
    }
}

final class BlueTryAccessDeviceCommandTests: BlueXCTestCase {
    
    func testWhenDeviceIsMissing() async throws {
        try await XCTAssertThrowsError(await BlueTryAccessDeviceCommand().runAsync(deviceID: "")) { error in
            XCTAssert(error is BlueError)
            XCTAssertEqual((error as? BlueError)?.returnCode, .sdkDeviceNotFound)
        }
    }
    
    func testWhenOssTokensAreMissing() async throws {
        let device = BlueDevice()
        device.info.deviceID = "device-1"
        blueAddDevice(device)
        
        try await XCTAssertThrowsError(await BlueTryAccessDeviceCommand().runAsync(deviceID: "device-1")) { error in
            XCTAssert(error is BlueError)
            XCTAssertEqual((error as? BlueError)?.returnCode, .sdkSpTokenNotFound)
        }
    }
    
    func testWhenOssSoTokenIsPresent() async throws {
        let device = BlueDevice()
        device.info.deviceID = "device-1"
        blueAddDevice(device)
        
        let credential = blueCreateAccessCredentialDemo()
        let ossSoToken = try blueCreateSignedOssSoDemoToken()
        let terminalRunMock = BlueTerminalMock()
        
        try await BlueAddAccessCredentialCommand(BlueAPIMock(ossSoToken)).runAsync(credential: credential)
        
        _ = try await XCTAssertNotThrowsError(await BlueTryAccessDeviceCommand(using: terminalRunMock.terminalRun).runAsync(deviceID: "device-1"))
        XCTAssertEqual(terminalRunMock.actionCalled, "ossSoMobile")
    }
    
    func testWhenOssSidTokenIsPresent() async throws {
        let device = BlueDevice()
        device.info.deviceID = "device-1"
        blueAddDevice(device)
        
        let credential = blueCreateAccessCredentialDemo()
        let ossSidToken = try blueCreateSignedOssSidDemoToken()
        let terminalRunMock = BlueTerminalMock()
        
        try await BlueAddAccessCredentialCommand(BlueAPIMock(ossSidToken)).runAsync(credential: credential)
        
        _ = try await XCTAssertNotThrowsError(await BlueTryAccessDeviceCommand(using: terminalRunMock.terminalRun).runAsync(deviceID: "device-1"))
        XCTAssertEqual(terminalRunMock.actionCalled, "ossSidMobile")
    }
}

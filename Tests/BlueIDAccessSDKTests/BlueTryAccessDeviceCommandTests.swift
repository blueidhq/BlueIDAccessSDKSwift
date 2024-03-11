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

private class BlueTerminalRunMock: BlueTerminalRunProtocol {
    var actionCalled: String?
    
    func runOssSidMobile(deviceID: String) async throws -> BlueOssAccessResult {
        actionCalled = "ossSidMobile"
        
        return BlueOssAccessResult()
    }
    
    func runOssSoMobile(deviceID: String) async throws -> BlueOssAccessEventsResult {
        actionCalled = "ossSoMobile"
        
        return BlueOssAccessEventsResult()
    }
}

final class BlueTryAccessDeviceCommandTests: BlueXCTestCase {
    
    func testWhenDeviceIsMissing() async throws {
        try await XCTAssertThrowsError(await BlueTryAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(deviceID: "")) { error in
            XCTAssert(error is BlueError)
            XCTAssertEqual((error as? BlueError)?.returnCode, .sdkDeviceNotFound)
        }
    }
    
    func testWhenOssTokensAreMissing() async throws {
        let device = BlueDevice()
        device.info.deviceID = "device-1"
        blueAddDevice(device)
        
        try await XCTAssertThrowsError(await BlueTryAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock())).runAsync(deviceID: "device-1")) { error in
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
        let terminalRunMock = BlueTerminalRunMock()
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(BlueAPIMock(ossSoToken), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        
        _ = try await XCTAssertNotThrowsError(await BlueTryAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()), using: terminalRunMock).runAsync(deviceID: "device-1"))
        XCTAssertEqual(terminalRunMock.actionCalled, "ossSoMobile")
    }
    
    func testWhenOssSidTokenIsPresent() async throws {
        let device = BlueDevice()
        device.info.deviceID = "device-1"
        blueAddDevice(device)
        
        let credential = blueCreateAccessCredentialDemo()
        let ossSidToken = try blueCreateSignedOssSidDemoToken()
        let terminalRunMock = BlueTerminalRunMock()
        
        try await BlueAddAccessCredentialCommand(BlueSdkService(BlueAPIMock(ossSidToken), BlueDefaultAccessEventServiceMock())).runAsync(credential: credential)
        
        _ = try await XCTAssertNotThrowsError(await BlueTryAccessDeviceCommand(BlueSdkService(DefaultBlueAPIMock(), BlueDefaultAccessEventServiceMock()), using: terminalRunMock).runAsync(deviceID: "device-1"))
        XCTAssertEqual(terminalRunMock.actionCalled, "ossSidMobile")
    }
}

import XCTest

@testable import BlueIDAccessSDK

final class BlueSynchronizeNfcAccessCommandTests: BlueXCTestCase {
    func testSync() async throws {
        let command = BlueSynchronizeNfcAccessCommand(DefaultBlueAPIMock())
        
        let tokenAuthentication = BlueTokenAuthentication(token: "", signature: "")
        
        let result = try await command.sync(with: tokenAuthentication)
        XCTAssertNotNil(result)
        XCTAssertNotNil(result.data)
    }
    
    func testUpdate() throws {
        let command = BlueSynchronizeNfcAccessCommand()
        
        let credential = blueCreateAccessCredentialDemo()
        let synchronizationResult = BlueNfcAccessSynchronizationResult(
            ossSoSettings: try blueEncodeMessage(BlueOssSoSettings()).base64EncodedString(),
            ossSidSettings: try blueEncodeMessage(BlueOssSidSettings()).base64EncodedString()
        )
        
        try command.update(credential, synchronizationResult)
        
        let ossEntry: BlueOssEntry? = try blueAccessOssSettingsKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNotNil(ossEntry)
        XCTAssertNotNil(ossEntry?.ossSo)
        XCTAssertNotNil(ossEntry?.ossSid)
    }
    
    func testPurge() throws {
        let command = BlueSynchronizeNfcAccessCommand()
        
        let credential = blueCreateAccessCredentialDemo()
        
        let storedOssEntry = BlueOssEntry(
            ossSo: try blueEncodeMessage(BlueOssSoSettings()),
            ossSid: try blueEncodeMessage(BlueOssSidSettings())
        )
        
        try blueAccessOssSettingsKeyChain.storeCodableEntry(id: credential.credentialID.id, data: storedOssEntry)
        
        try command.purge(credential)
        
        let ossEntry: BlueOssEntry? = try blueAccessOssSettingsKeyChain.getCodableEntry(id: credential.credentialID.id)
        XCTAssertNil(ossEntry)
    }
}

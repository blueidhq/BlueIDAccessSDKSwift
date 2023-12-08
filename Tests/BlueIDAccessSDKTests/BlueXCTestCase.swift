import XCTest
@testable import BlueIDAccessSDK

class BlueXCTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        
        do {
            _ = try? BlueInitializeCommand().run()
        }
    }
    
    override func tearDown() {
        do {
            _ = try? blueAccessCredentialsKeyChain.deleteAllEntries()
            _ = try? blueAccessAuthenticationTokensKeyChain.deleteAllEntries()
            
            blueAccessDevicesStorage.deleteAllEntries()
            
            _ = try? BlueReleaseCommand().run()
        }
        
        super.tearDown()
    }
}

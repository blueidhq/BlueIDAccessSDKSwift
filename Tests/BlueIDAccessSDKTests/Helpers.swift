@testable import BlueIDAccessSDK

func setUpCommandTests() {
    do {
        _ = try? BlueInitializeCommand().run()
    }
}

func tearDownCommandTests() {
    do {
        _ = try? blueAccessCredentialsKeyChain.deleteAllEntries()
        _ = try? blueAccessDeviceTokensKeyChain.deleteAllEntries()
        _ = try? blueAccessAuthenticationTokensKeyChain.deleteAllEntries()
        _ = try? BlueReleaseCommand().run()
    }
}

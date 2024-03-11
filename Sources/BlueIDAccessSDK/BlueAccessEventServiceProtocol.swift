import Foundation

internal protocol BlueAccessEventServiceProtocol {
    func pushEvents(_ credentialID: String, _ events: [BluePushEvent])
}

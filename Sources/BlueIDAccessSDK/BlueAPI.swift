import Foundation

// TODO: implement .xconfig files
//private let baseURL = "http://localhost:3000"
private let baseURL = "https://api.dev.blue-id.com"

/*
 /access/(...) endpoints
 */
private enum BlueAccessEndpoints: String {
    case authenticationToken = "/access/authenticationToken"
    case synchronizeMobileAccess = "/access/synchronizeMobileAccess"

    var url: URL {
        guard let url = URL(string: baseURL) else {
            preconditionFailure("\(BlueAccessEndpoints.self): Invalid URL")
        }
        return url.appendingPathComponent(self.rawValue)
    }
}

internal struct BlueTokenAuthentication: Encodable {
    var token: String
    var signature: String
}

internal struct BlueAccessDeviceToken: Decodable {
    var deviceId: String
    var objectName: String?
    var token: String
}

/*
 [POST] /access/synchronizeMobileAccess
 */
internal struct BlueMobileAccessSynchronizationResult: Decodable {
    var credentialId: String?
    var noRefresh: Bool?
    var siteId: Int?
    var siteName: String?
    var validity: Int?
    var tokens: [BlueAccessDeviceToken]?
    var deviceTerminalPublicKeys: [String: String]?

    func getAccessDeviceList() -> BlueAccessDeviceList {
        var deviceList = BlueAccessDeviceList()

        if let tokens = self.tokens {
            deviceList.devices = tokens.map{ token in
                var device = BlueAccessDevice()
                device.deviceID = token.deviceId
                device.objectName = token.objectName ?? ""
                return device
            }
        }
        return deviceList
    }
}

/*
 [POST] /access/authenticationToken
 */
internal struct BlueAccessToken: Codable {
    var token: String
    var expiresAt: Int
}

protocol BlueAPIProtocol {
    func getAccessToken(credentialId: String) async throws -> BlueAccessToken
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueMobileAccessSynchronizationResult
}

@available(macOS 12.0, *)
class BlueAPI: BlueAPIProtocol {
    func getAccessToken(credentialId: String) async throws -> BlueAccessToken {
        let data = try JSONSerialization.data(withJSONObject: [
            "credentialId": credentialId,
        ])

        return try await BlueFetch.post(
            url: BlueAccessEndpoints.authenticationToken.url,
            data: data,
            config: BlueFetchConfig(headers: ["Content-type": "application/json"])
        )
    }

    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueMobileAccessSynchronizationResult {
        let data = try JSONEncoder().encode([
            "tokenAuthentication": tokenAuthentication
        ])

        return try await BlueFetch.post(
            url: BlueAccessEndpoints.synchronizeMobileAccess.url,
            data: data,
            config: BlueFetchConfig(headers: ["Content-type": "application/json"])
        )
    }
}

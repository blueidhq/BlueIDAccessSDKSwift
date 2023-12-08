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
    case createDeviceConfiguration = "/access/createDeviceConfiguration"

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

/*
 [POST] /access/createDeviceConfiguration
 */
internal struct BlueCreateDeviceConfigurationRequest: Encodable {
    var deviceId: String
    var tokenAuthentication: BlueTokenAuthentication
}
internal struct BlueCreateDeviceConfigurationResult: Decodable {
    var systemConfiguration: String
}

/*
 [POST] /access/synchronizeMobileAccess
 */
internal struct BlueAccessDeviceToken: Decodable {
    var deviceId: String
    var objectName: String?
    var token: String
}
internal struct BlueMobileAccessSynchronizationRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
}
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
internal struct BlueAccessTokenRequest: Encodable {
    var credentialId: String
}

protocol BlueAPIProtocol {
    func getAccessToken(credentialId: String) async throws -> BlueAccessToken
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueMobileAccessSynchronizationResult
    func createDeviceConfiguration(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueCreateDeviceConfigurationResult
}

@available(macOS 12.0, *)
class BlueAPI: BlueAPIProtocol {
    func getAccessToken(credentialId: String) async throws -> BlueAccessToken {
        let request = BlueAccessTokenRequest(credentialId: credentialId)

        return try await BlueFetch.post(
            url: BlueAccessEndpoints.authenticationToken.url,
            data: self.toData(request),
            config: BlueFetchConfig(headers: ["Content-type": "application/json"])
        )
    }

    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueMobileAccessSynchronizationResult {
        let request = BlueMobileAccessSynchronizationRequest(tokenAuthentication: tokenAuthentication)
        
        return try await BlueFetch.post(
            url: BlueAccessEndpoints.synchronizeMobileAccess.url,
            data: self.toData(request),
            config: BlueFetchConfig(headers: ["Content-type": "application/json"])
        )
    }
    
    func createDeviceConfiguration(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueCreateDeviceConfigurationResult {
        let request = BlueCreateDeviceConfigurationRequest(deviceId: deviceID, tokenAuthentication: tokenAuthentication)
        
        return try await BlueFetch.post(
            url: BlueAccessEndpoints.createDeviceConfiguration.url,
            data: self.toData(request),
            config: BlueFetchConfig(headers: ["Content-type": "application/json"])
        )
    }
    
    private func toData<T>(_ data: T) throws -> Data where T: Encodable {
        return try JSONEncoder().encode(data)
    }
}

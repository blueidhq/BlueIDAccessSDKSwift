import Foundation

// TODO: implement .xconfig files
// private let baseURL = "http://localhost:3000"
private let baseURL = "https://api.dev.blue-id.com"

public enum BlueAPIEndpoints: String {
    case AccessAuthenticationToken = "/access/authenticationToken"
    case AccessSynchronizeMobileAccess = "/access/synchronizeMobileAccess"
    case AccessSynchronizeNfcAccess = "/access/synchronizeNfcAccess"
    case AccessCreateDeviceConfiguration = "/access/createDeviceConfiguration"
    case AccessUpdateDeviceSystemStatus = "/access/updateDeviceSystemStatus"
    case AccessObjects = "/access/objects"
    case AccessPushEvents = "/access/pushEvents"
    case AccessPushSystemLog = "/access/pushSystemLog"
    case AccessBlacklistEntries = "/access/blacklistEntries"
    case AccessClaimDevice = "/access/claimDevice"
    case AccessCredentials = "/access/credentials"
    case AccessSynchronizeOfflineAccess = "/access/synchronizeOfflineAccess"
    case AccessClaimCredential = "/access/cc"
    case AccessGetLatestFirmware = "/access/getLatestFirmware"
    
    var url: URL {
        guard let url = URL(string: baseURL) else {
            preconditionFailure("\(BlueAPIEndpoints.self): Invalid URL")
        }
        return url.appendingPathComponent(self.rawValue)
    }
}

/// Basically used by all /access endpoints
internal struct BlueTokenAuthentication: Encodable {
    var token: String
    var signature: String
}

/// [GET] /access/cc response
internal typealias BlueClaimAccessCredentialResult = BlueAccessCredential

/// [POST] /access/credentials request
internal struct BlueGetAccessCredentialsRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/credentials response
internal typealias BlueGetAccessCredentialsResult = [BlueAccessCredential]

/// [POST] /access/claimDevice request
internal struct BlueClaimDeviceRequest: Encodable {
    var deviceId: String
    var object: String
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/claimDevice response
internal struct BlueClaimDeviceResult: Decodable {
    var site: String
}

/// [POST] /access/blacklistEntries request
internal struct BlueGetBlacklistEntriesRequest: Encodable {
    var deviceId: String
    var tokenAuthentication: BlueTokenAuthentication
    var limit: Int?
}
/// [POST] /access/blacklistEntries response
internal struct BlueGetBlacklistEntriesResult: Decodable {
    var blacklistEntries: String
}

internal struct BluePushSystemLogEntry: Encodable {
    var sequenceId: Int
    var logTime: BlueLocalTimestamp
    var severity: Int
    var line: Int
    var file: String
    var message: String
    
    init(logEntry: BlueSystemLogEntry) {
        self.sequenceId = Int(logEntry.sequenceID)
        self.logTime = logEntry.time
        self.severity = Int(logEntry.severity)
        self.line = Int(logEntry.line)
        self.file = logEntry.file
        self.message = logEntry.message
    }
}
/// [POST] /access/pushSystemLog request
internal struct BluePushSystemLogRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
    var deviceId: String
    var logEntries: [BluePushSystemLogEntry]
}
/// [POST] /access/pushSystemLog response
internal struct BluePushSystemLogResult: Decodable {
    var storedLogEntries: [Int]
}

internal struct BluePushEvent: Encodable {
    var deviceId: String?
    var objectId: Int?
    var eventTime: BlueLocalTimestamp
    var sequenceId: Int?
    var eventId: Int
    var eventInfo: Int
    var credentialId: String?
    var command: String?
    
    init(event: BlueEvent, deviceId: String) {
        self.deviceId = deviceId
        self.sequenceId = Int(event.sequenceID)
        self.eventId = event.eventID.rawValue
        self.eventTime = event.eventTime
        self.eventInfo = Int(event.eventInfo)
        self.credentialId = event.credentialID.id
        self.command = event.command
    }
    
    init(event: BlueOssSoEvent, credentialId: String) {
        self.objectId = Int(event.doorID)
        self.eventId = event.eventID.rawValue
        self.eventTime = event.eventTime
        self.eventInfo = Int(event.eventInfo)
        self.credentialId = credentialId
    }
}
/// [POST] /access/pushEvents request
internal struct BluePushEventsRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
    var events: [BluePushEvent]
}
/// [POST] /access/pushEvents response
internal struct BluePushEventsResult: Decodable {
    var storedEvents: [Int]
}

/// [POST] /access/objects request
internal struct BlueGetAccessObjectsRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/objects response
internal typealias BlueGetAccessObjectsResult = [BlueAccessObject]

/// [POST] /access/createDeviceConfiguration request
internal struct BlueCreateDeviceConfigurationRequest: Encodable {
    var deviceId: String
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/createDeviceConfiguration response
internal struct BlueCreateDeviceConfigurationResult: Decodable {
    var systemConfiguration: String?
}

/// [POST] /access/updateDeviceSystemStatus request
internal struct BlueUpdateDeviceSystemStatusRequest: Encodable {
    var systemStatus: String
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/updateDeviceSystemStatus response
internal struct BlueUpdateDeviceSystemStatusResult: Decodable {
    var updated: Bool
}

internal struct BlueAccessDeviceToken: Decodable {
    var deviceId: String
    var objectId: Int
    var objectName: String?
    var token: String
}

internal protocol BlueSynchronizationResponse: Decodable {
    var credentialId: String? { get }
    var noRefresh: Bool? { get }
}

/// [POST] /access/synchronizeOfflineAccess request
internal struct BlueOfflineAccessSynchronizationRequest: Encodable {
    var credentialId: String
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/synchronizeOfflineAccess response
internal struct BlueOfflineAccessSynchronizationResult: BlueSynchronizationResponse {
    var credentialId: String?
    var noRefresh: Bool?
    var configuration: String?
    var blacklistFile: String?
}

/// [POST] /access/synchronizeNfcAccess request
internal struct BlueNfcAccessSynchronizationRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
}
/// [POST] /access/synchronizeNfcAccess response
internal struct BlueNfcAccessSynchronizationResult: BlueSynchronizationResponse {
    var credentialId: String?
    var noRefresh: Bool?
    var ossSoSettings: String?
    var ossSidSettings: String?
}

/// [POST] /access/synchronizeMobileAccess request
internal struct BlueMobileAccessSynchronizationRequest: Encodable {
    var tokenAuthentication: BlueTokenAuthentication
    var forceRefresh: Bool?
}
/// [POST] /access/synchronizeMobileAccess response
internal struct BlueMobileAccessSynchronizationResult: BlueSynchronizationResponse {
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
                device.objectID = Int32(token.objectId)
                device.objectName = token.objectName ?? ""
                return device
            }
        }
        return deviceList
    }
}

/// [POST] /access/authenticationToken request
internal struct BlueAccessTokenRequest: Encodable {
    var credentialId: String
}
/// [POST] /access/authenticationToken response
internal struct BlueAccessToken: Codable {
    var token: String
    var expiresAt: Int
}

/// [POST] /access/getLatestFirmware request
internal struct BlueGetLatestFirmwareRequest: Encodable {
    var deviceId: String
    var tokenAuthentication: BlueTokenAuthentication
}

internal struct BlueLatestFirmwareInfo: Decodable {
    let version: Int
    let testVersion: Int?
    let url: String
}

/// [POST] /access/getLatestFirmware response
internal struct BlueGetLatestFirmwareResult: Decodable {
    let production: BlueLatestFirmwareInfo?
    let test: BlueLatestFirmwareInfo?
}

protocol BlueAPIProtocol {
    func getAccessToken(credentialId: String) async throws -> BlueFetchResponse<BlueAccessToken>
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication, forceRefresh: Bool?) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult>
    func synchronizeNfcAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueNfcAccessSynchronizationResult>
    func synchronizeOfflineAccess(credentialID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueOfflineAccessSynchronizationResult>
    func createDeviceConfiguration(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueCreateDeviceConfigurationResult>
    func updateDeviceSystemStatus(systemStatus: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueUpdateDeviceSystemStatusResult>
    func pushEvents(events: [BluePushEvent], with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BluePushEventsResult>
    func pushSystemLogs(deviceID: String, logEntries: [BluePushSystemLogEntry], with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BluePushSystemLogResult>
    func getAccessObjects(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessObjectsResult>
    func getBlacklistEntries(deviceID: String, with tokenAuthentication: BlueTokenAuthentication, limit: Int?) async throws -> BlueFetchResponse<BlueGetBlacklistEntriesResult>
    func claimDevice(deviceID: String, objectID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueClaimDeviceResult>
    func claimAccessCredential(activationToken: String) async throws -> BlueFetchResponse<BlueClaimAccessCredentialResult>
    func getAccessCredentials(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessCredentialsResult>
    func getLatestFirmware(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetLatestFirmwareResult>
}

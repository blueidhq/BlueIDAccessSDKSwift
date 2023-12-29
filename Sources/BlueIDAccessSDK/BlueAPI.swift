import Foundation

@available(macOS 12.0, *)
class BlueAPI: BlueAPIProtocol {
    
    func getAccessToken(credentialId: String) async throws -> BlueFetchResponse<BlueAccessToken> {
        return try await post(
            endpoint: .AccessAuthenticationToken,
            request: BlueAccessTokenRequest(credentialId: credentialId)
        )
    }
    
    func synchronizeMobileAccess(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueMobileAccessSynchronizationResult> {
        return try await post(
            endpoint: .AccessSynchronizeMobileAccess,
            request: BlueMobileAccessSynchronizationRequest(tokenAuthentication: tokenAuthentication)
        )
    }
    
    func createDeviceConfiguration(deviceID: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueCreateDeviceConfigurationResult> {
        return try await post(
            endpoint: .AccessCreateDeviceConfiguration,
            request: BlueCreateDeviceConfigurationRequest(deviceId: deviceID, tokenAuthentication: tokenAuthentication)
        )
    }
    
    func updateDeviceSystemStatus(systemStatus: String, with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueUpdateDeviceSystemStatusResult> {
        return try await post(
            endpoint: .AccessUpdateDeviceSystemStatus,
            request: BlueUpdateDeviceSystemStatusRequest(systemStatus: systemStatus, tokenAuthentication: tokenAuthentication)
        )
    }
    
    func pushEvents(events: [BluePushEvent], with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BluePushEventsResult> {
        return try await post(
            endpoint: .AccessPushEvents,
            request: BluePushEventsRequest(tokenAuthentication: tokenAuthentication, events: events)
        )
    }
    
    func pushSystemLogs(deviceID: String, logEntries: [BluePushSystemLogEntry], with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BluePushSystemLogResult> {
        return try await post(
            endpoint: .AccessPushSystemLog,
            request: BluePushSystemLogRequest(tokenAuthentication: tokenAuthentication, deviceId: deviceID, logEntries: logEntries)
        )
    }
    
    func getAccessObjects(with tokenAuthentication: BlueTokenAuthentication) async throws -> BlueFetchResponse<BlueGetAccessObjectsResult> {
        return try await post(
            endpoint: .AccessObjects,
            request: BlueGetAccessObjectsRequest(tokenAuthentication: tokenAuthentication)
        )
    }
    
    func getBlacklistEntries(deviceID: String, with tokenAuthentication: BlueTokenAuthentication, limit: Int?) async throws -> BlueFetchResponse<BlueGetBlacklistEntriesResult> {
        return try await post(
            endpoint: .AccessBlacklistEntries,
            request: BlueGetBlacklistEntriesRequest(deviceId: deviceID, tokenAuthentication: tokenAuthentication, limit: limit)
        )
    }
    
    private func post<T>(endpoint: BlueAPIEndpoints, request: Encodable) async throws -> BlueFetchResponse<T> {
        return try await BlueFetch.post(
            url: endpoint.url,
            data: self.toData(request)
        )
    }
    
    private func toData<T>(_ data: T) throws -> Data where T: Encodable {
        return try JSONEncoder().encode(data)
    }
}

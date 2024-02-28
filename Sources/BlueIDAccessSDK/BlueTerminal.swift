import CBlueIDAccess
import Foundation
import SwiftProtobuf

internal let blueTerminalPublicKeysKeychain = BlueKeychain(attrService: "blueid.terminalKeys")
internal let blueTerminalRequestDataKeychain = BlueKeychain(attrService: "blueid.requestData")

private var blueSpTransponder: BlueSPTransponder? = nil
private var blueActiveDevice: BlueDevice? = nil

public var defaultTimeoutSec: Double = 10

internal func isActiveDevice(_ device: BlueDevice) -> Bool {
    guard let activeDevice = blueActiveDevice else {
        return false
    }
    
    return activeDevice.info.deviceID == device.info.deviceID
}

internal struct BlueSPTokenEntry: Codable {
    var credentialID: String
    var data: Data
}

internal func blueStoreSpToken(credential: BlueAccessCredential, deviceID: String, token: String) throws {
    guard let tokenData = Data(base64Encoded: token) else {
        throw BlueError(.invalidState)
    }
    
    let spToken: BlueSPToken = try blueDecodeMessage(tokenData)
    
    var action: String = ""
    
    switch (spToken.payload) {
        case .ossSo:
            action = "ossSoMobile"
            break;
        case .ossSid:
            action = "ossSidMobile"
            break;
        case .command(let spTokenCommand):
            action = spTokenCommand.command
            break;
        case .none:
            throw BlueError(.invalidState)
    }
    
    let entryID = "\(deviceID):\(action)"
    
    var spTokenEntries: [BlueSPTokenEntry] = []
    
    if let storedEntry = try blueGetSpTokenEntry(entryID) {
        if let entries = storedEntry as? [BlueSPTokenEntry] {
            spTokenEntries = entries
        }
    }
    
    // "Upsert" the new entry
    spTokenEntries.removeAll( where: { $0.credentialID == credential.credentialID.id } )
    spTokenEntries.append(BlueSPTokenEntry(credentialID: credential.credentialID.id, data: tokenData))
    
    try blueTerminalRequestDataKeychain.storeEntry(
        id: entryID,
        data: JSONEncoder().encode(spTokenEntries)
    )
}

/// Deletes all SP Tokens for a given credential.
///
/// - parameter credential: The credential.
/// - throws: An error is thrown if any error occurs during the retrieval of the entry IDs from the KeyChain.
internal func blueDeleteSpTokens(credential: BlueAccessCredential) throws {
    try blueTerminalRequestDataKeychain.getEntryIds().forEach { entryID in

        if let storedEntry = try? blueGetSpTokenEntry(entryID) {
            
            if var spTokenEntries = storedEntry as? [BlueSPTokenEntry] {
                
                let matchCredential = spTokenEntries.contains(where: { $0.credentialID == credential.credentialID.id })
                guard matchCredential else {
                    return
                }
                
                spTokenEntries.removeAll( where: { $0.credentialID == credential.credentialID.id } )
                
                if (spTokenEntries.isEmpty) {
                    _ = try? blueTerminalRequestDataKeychain.deleteEntry(id: entryID)
                } else {
                    try? blueTerminalRequestDataKeychain.storeEntry(
                        id: entryID,
                        data: JSONEncoder().encode(spTokenEntries)
                    )
                }
            }
            
            else if var _ = storedEntry as? Data {
                _ = try? blueTerminalRequestDataKeychain.deleteEntry(id: entryID)
            }
        }
    }
}

/// Returns all entry IDs for a given device.
///
/// - parameter deviceID: The Device ID.
/// - throws: An error is thrown if any error occurs during the retrieval of the entry IDs from the KeyChain.
internal func blueGetSpTokenEntryIds(deviceID: String) throws -> [String] {
    return try blueTerminalRequestDataKeychain.getEntryIds().compactMap{ entryId in
        if (entryId.hasPrefix(deviceID)) {
            return entryId
        }
        return nil
    }
}

/// Returns either an array of BlueSPTokenEntry or the Data itself.
/// This maintains compatibility with previous versions where tokens were being overwritten because the credential was not being taken into account.
/// Always allowing the tokens to be overwritten and creating a “special” logic to keep the token in case another credential still needs it is a bug, as the following scenario may happen: 
/// Credential A stores the token for a specific device, Credential B overrides the token for the same device, Credential B is revoked, but the token is kept.
/// The problem lies here: Credential B is added to the blacklist and once the device is updated with the most recent blacklist entries, Credential A will not be able to unlock the device until it has synced its tokens again, and this may take up to 30 days depending on the refresh rate.
///
/// - parameter entryID: The KeyChain Entry ID.
/// - throws: An error is thrown if any error occurs during the retrieval of the entry from the KeyChain.
internal func blueGetSpTokenEntry(_ entryID: String) throws -> Any? {
    if let data: Data = try blueTerminalRequestDataKeychain.getEntry(id: entryID) {
        if let spTokenEntries = try? JSONDecoder().decode([BlueSPTokenEntry].self, from: data) {
            return spTokenEntries
        }
        
        // To keep compatibility with the initial version of the SDK where tokens were being overwritten and stored as data, so we can simply return it.
        return data
    }
    
    return nil
}

/// Returns a BlueSPToken with compatibility with previous versions of the SDK.
/// In case the SDK is already storing tokens as an array of BlueSPTokenEntry, then the first BlueSPToken will be returned.
/// - parameter entryID: The KeyChain Entry ID.
/// - throws: An error is thrown if any error occurs during the retrieval of the entry from the KeyChain.
/// - throws: An error is thrown if any error occurs when decoding the token Data into a BlueSPToken.
internal func blueGetSpToken(_ entryID: String) throws -> BlueSPToken? {
    if let storedEntry = try blueGetSpTokenEntry(entryID) {
        if let spTokenEntries = storedEntry as? [BlueSPTokenEntry] {
            if let spTokenEntry = spTokenEntries.first {
                return try blueDecodeMessage(spTokenEntry.data)
            }
        }
        else if let spTokenData = storedEntry as? Data {
            return try blueDecodeMessage(spTokenData)
        }
    }
    
    return nil
}

internal func blueHasSpTokenForAction(device: BlueDevice, action: String) -> Bool {
    do {
        _ = try blueGetSpTokenForAction(device: device, action: action, data: nil)
        return true
    } catch {
        return false
    }
}

private func blueGetSpTokenForAction(device: BlueDevice, action: String, data: Data?) throws -> BlueSPToken {
    var token: BlueSPToken? = try blueGetSpToken("\(device.info.deviceID):\(action)")
    
    if token == nil {
        // Load the maintenance token if there is no available token for the given action.
        // Internally, the firmware allows maintenance tokens to execute a group of actions, including 'UPDATE,' 'PING,' and others.
        // This way enables us to avoid requesting a new token for every terminal command since we do not store the private key.
        token = try blueGetSpToken("\(device.info.deviceID):MAINTC")
    }
    
    if (token != nil) {
        if (token!.command.command == "MAINTC") {
            // We use the maintenance command along with the maintenance signature. Internally, the firmware handles it properly.
            // However, we need to indicate which command we want to execute here.
            token!.command.command = action
        }
    }
    
    switch action {
    case "ossSoMobile":
        if token == nil {
            if device.info.deviceID == blueDemoData.deviceID {
                token = try blueCreateSignedOssSoDemoToken()
            } else {
                throw BlueError(.invalidArguments)
            }
        }
        break
    case "ossSidMobile":
        if token == nil {
            if device.info.deviceID == blueDemoData.deviceID {
                token = try blueCreateSignedOssSidDemoToken()
            } else {
                throw BlueError(.invalidArguments)
            }
        }
        break
    default:
        // -- Assume regular command
        if token == nil {
            if device.info.deviceID == blueDemoData.deviceID {
                token = try blueCreateSignedCommandDemoToken(action)
            } else {
                throw BlueError(.invalidArguments)
            }
        }
        
        token!.command.data = Data()
        
        if let commandData = data, !commandData.isEmpty {
            token!.command.data.append(contentsOf: commandData)
        }
        
        break
    }
    
    guard let token = token else {
        throw BlueError(.invalidState)
    }
    
    return token
}

private func blueTerminalRequest(action: String, data: Data?) throws -> Data? {
    guard let blueActiveDevice = blueActiveDevice else {
        throw BlueError(.invalidState)
    }
    
    let token = try blueGetSpTokenForAction(device: blueActiveDevice, action: action, data: data)
    
    let statusCodePtr = UnsafeMutablePointer<Int16>.allocate(capacity: 1)
    statusCodePtr.pointee = Int16(blueAsClibReturnCode(.ok).rawValue)
    
    defer { statusCodePtr.deallocate() }
    
    do {
        let spResult: BlueSPResult = try blueClibFunctionInOut(
            message: token,
            { (spTokenPtr, spTokenSize, resultPtr, resultSize) in
                var returnCode: BlueReturnCode_t = blueAsClibReturnCode(.invalidState)
                
                returnCode = blueSPTransponder_SendRequest_Ext(
                    blueActiveDevice.info.deviceID, blueActiveDevice.spConnection.connectionPtr, spTokenPtr,
                    spTokenSize, resultPtr, resultSize, statusCodePtr, nil)
                
                return returnCode
            })
        
        return spResult.data
    } catch let error as BlueError {
        if error.returnCode == .sperrorStatusCode {
            let rawValue = Int(statusCodePtr.pointee)
            if let terminalStatusCode = BlueReturnCode(rawValue: rawValue) {
                throw BlueTerminalError(terminalStatusCode)
            } else {
                throw BlueError(.invalidState)
            }
        }
        
        throw error
    } catch let error {
        throw error
    }
}

public func blueTerminalRequest(action: String, data: Data? = nil) throws {
    let rawResult: Data? = try blueTerminalRequest(action: action, data: data)
    
    if let rawResult = rawResult {
        guard rawResult.isEmpty else {
            throw BlueError(.invalidState)
        }
    }
}

public func blueTerminalRequest<DataType: Message>(action: String, data: DataType) throws {
    let rawData = try blueEncodeMessage(data)
    return try blueTerminalRequest(action: action, data: rawData)
}

public func blueTerminalRequest<ResultType: Message>(action: String, data: Data? = nil) throws
-> ResultType
{
    let rawResult: Data? = try blueTerminalRequest(action: action, data: data)
    
    guard let rawResult = rawResult else {
        throw BlueError(.invalidState)
    }
    
    return try blueDecodeMessage(rawResult)
}

public func blueTerminalRequest<DataType: Message, ResultType: Message>(
    action: String, data: DataType
) throws -> ResultType {
    let rawData = try blueEncodeMessage(data)
    return try blueTerminalRequest(action: action, data: rawData)
}

public func blueTerminalRun<HandlerResult>(
    deviceID: String, timeoutSeconds: Double = defaultTimeoutSec,
    handler: @escaping () throws -> HandlerResult,
    completion: @escaping (Result<HandlerResult, Error>) -> Void, isTest: Bool = false
) {
    if !blueIsInitialized {
        return completion(.failure(BlueError(.unavailable)))
    }
    
    if blueSpTransponder == nil {
        do {
            blueSpTransponder = try BlueSPTransponder(
                terminalPublicKeysKeychain: blueTerminalPublicKeysKeychain)
        } catch let error {
            return completion(.failure(error))
        }
    }
    
    if isTest {
        return DispatchQueue.global(qos: .background).async {
            do {
                var handlerResult: HandlerResult? = nil
                
                try blueExecuteWithTimeout(
                    {
                        handlerResult = try handler()
                    }, timeoutSeconds: timeoutSeconds)
                
                guard let handlerResult = handlerResult else {
                    throw BlueError(.invalidState)
                }
                
                DispatchQueue.main.async {
                    completion(.success(handlerResult))
                }
            } catch let error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    guard blueActiveDevice == nil else {
        return completion(.failure(BlueError(.unavailable)))
    }
    
    guard let device = blueGetDevice(deviceID) else {
        return completion(.failure(BlueError(.sdkDeviceNotFound)))
    }
    
    return DispatchQueue.global(qos: .background).async {
        let wasConnected = device.isConnected
        
        do {
            var handlerResult: HandlerResult? = nil
            
            try blueExecuteWithTimeout(
                {
                    blueActiveDevice = device
                    
                    defer { blueActiveDevice = nil }
                    
                    if !wasConnected {
                        try device.connect()
                    }
                    
                    blueLogDebug("Connected to \(device.info.deviceID)")
                    
                    var errorThrown: Error? = nil
                    
                    do {
                        handlerResult = try handler()
                    } catch {
                        errorThrown = error
                    }
                    
                    if !wasConnected {
                        try device.disconnect()
                    }
                    
                    blueLogDebug("Disconnected to \(device.info.deviceID)")
                    
                    if let errorThrown = errorThrown {
                        throw errorThrown
                    }
                }, timeoutSeconds: timeoutSeconds)
            
            guard let handlerResult = handlerResult else {
                throw BlueError(.invalidState)
            }
            
            DispatchQueue.main.async {
                completion(.success(handlerResult))
            }
        } catch let error {
            if !wasConnected && device.isConnected {
                do {
                    try device.disconnect()
                } catch {
                    blueLogError("Unable to disconnect from peripheral after error")
                }
            }
            
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
}

@available(macOS 10.15, *)
public func blueTerminalRun<HandlerResult>(
    deviceID: String, timeoutSeconds: Double = defaultTimeoutSec,
    _ handler: @escaping () throws -> HandlerResult
) async throws -> HandlerResult {
    return try await withCheckedThrowingContinuation { continuation in
        blueTerminalRun(deviceID: deviceID, timeoutSeconds: timeoutSeconds, handler: handler) {
            result in
            continuation.resume(with: result)
        }
    }
}

@available(macOS 10.15, *)
public func blueTerminalRun(deviceID: String, timeoutSeconds: Double = 30.0, action: String)
async throws
{
    try await blueTerminalRun(
        deviceID: deviceID,
        {
            try blueTerminalRequest(action: action)
        })
}

@available(macOS 10.15, *)
public func blueTerminalRun<ResultType: Message>(
    deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, action: String
) async throws -> ResultType {
    return try await blueTerminalRun(
        deviceID: deviceID,
        {
            return try blueTerminalRequest(action: action)
        })
}

@available(macOS 10.15, *)
public func blueTerminalRun<DataType: Message>(
    deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, action: String, data: DataType
) async throws -> Void {
    try await blueTerminalRun(
        deviceID: deviceID,
        timeoutSeconds: timeoutSeconds,
        {
            try blueTerminalRequest(action: action, data: data)
        })
}

@available(macOS 10.15, *)
public func blueTerminalRun<DataType: Message, ResultType: Message>(
    deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, action: String, data: DataType
) async throws -> ResultType {
    return try await blueTerminalRun(
        deviceID: deviceID,
        timeoutSeconds: timeoutSeconds,
        {
            return try blueTerminalRequest(action: action, data: data)
        })
}

//
// Plugin interface
//

internal struct BlueTerminalRequest {
    public let action: String
    public let data: Data?
    
    public init(action: String, data: Data? = nil) {
        self.action = action
        self.data = data
    }
}

internal struct BlueTerminalResult {
    public let statusCode: BlueReturnCode
    public let data: Data?
    
    internal init(statusCode: BlueReturnCode, data: Data? = nil) {
        self.statusCode = statusCode
        self.data = data
    }
}

internal func blueTerminalRun(
    deviceID: String, timeoutSeconds: Double = 30.0, requests: [BlueTerminalRequest],
    completion: @escaping (Result<[BlueTerminalResult], Error>) -> Void, isTest: Bool = false
) {
    let handler: () throws -> [BlueTerminalResult] = {
        var results: [BlueTerminalResult] = []
        
        for request in requests {
            var result: BlueTerminalResult? = nil
            
            do {
                if isTest {
                    if request.action == "TEST_PING" {
                        let versionInfo = try BlueVersionInfoCommand().run()
                        let data = try blueEncodeMessage(versionInfo)
                        result = BlueTerminalResult(statusCode: .ok, data: data)
                    } else {
                        throw BlueTerminalError(.notSupported)
                    }
                } else {
                    let data: Data? = try blueTerminalRequest(action: request.action, data: request.data)
                    result = BlueTerminalResult(statusCode: .ok, data: data)
                }
            } catch let error as BlueTerminalError {
                result = BlueTerminalResult(statusCode: error.terminalError.returnCode)
            } catch {
                throw error
            }
            
            if let result = result {
                results.append(result)
                
                blueFireListeners(fireEvent: .terminalResult, data: result)
            }
        }
        
        return results
    }
    
    blueTerminalRun(
        deviceID: deviceID, timeoutSeconds: timeoutSeconds, handler: handler, completion: completion,
        isTest: isTest)
}

//
// Objective-C interface
//

@objc(BlueTerminalRequest)
public final class ObjC_BlueTerminalRequest: NSObject {
    @objc public let action: String
    @objc public let data: NSData?
    
    fileprivate init(action: String, data: NSData? = nil) {
        self.action = action
        self.data = data
    }
}

@objc(BlueTerminalResult)
public final class ObjC_BlueTerminalResult: NSObject {
    @objc public let error: Error?
    @objc public let statusCode: Int
    @objc public let data: NSData?
    
    internal init(error: Error? = nil, statusCode: Int, data: NSData? = nil) {
        self.error = error
        self.statusCode = statusCode
        self.data = data
    }
}

@objc(BlueTerminal)
public final class ObjC_BlueTerminal: NSObject {
    private override init() {}
    
    @objc public static func run(
        _ deviceID: String, timeoutSeconds: Double = 30.0, requests: [ObjC_BlueTerminalRequest],
        completion: (([ObjC_BlueTerminalResult]) -> Void)?
    ) {
        let objcRequests: [BlueTerminalRequest] = requests.map { request in
            return BlueTerminalRequest(
                action: request.action, data: request.data != nil ? Data(referencing: request.data!) : nil)
        }
        
        blueTerminalRun(deviceID: deviceID, timeoutSeconds: timeoutSeconds, requests: objcRequests) {
            result in
            guard let completion = completion else {
                return
            }
            
            switch result {
            case .success(let terminalResults):
                completion(
                    terminalResults.map({ terminalResult in
                        return ObjC_BlueTerminalResult(
                            error: nil, statusCode: terminalResult.statusCode.rawValue,
                            data: terminalResult.data != nil ? NSData(data: terminalResult.data!) : nil)
                    }))
            case .failure(let error):
                completion(
                    requests.map({ request in
                        return ObjC_BlueTerminalResult(error: error, statusCode: BlueReturnCode.error.rawValue)
                    }))
            }
        }
    }
}

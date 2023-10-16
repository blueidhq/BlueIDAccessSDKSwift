import Foundation
import SwiftProtobuf
import CBlueIDAccess

internal let blueTerminalPublicKeysKeychain = BlueKeychain(attrService: "blueid.terminalKeys")
internal let blueTerminalRequestDataKeychain = BlueKeychain(attrService: "blueid.requestData")

private var blueSpTransponder: BlueSPTransponder? = nil
private var blueActiveDevice: BlueDevice? = nil

public var defaultTimeoutSec: Double = 10

private func blueGetSpDataForAction(device: BlueDevice, action: String, data: Data?) throws -> BlueSPData {
    var spData: BlueSPData? = nil
    
    let storedSpData = try blueTerminalRequestDataKeychain.getEntry(id: "\(device.info.deviceID):\(action)")
    
    if let storedSpData = storedSpData {
        spData = try blueDecodeMessage(storedSpData)
    }
    
    switch action {
    case "ossSoMobile":
        if spData == nil {
            if device.info.deviceID == blueDemoData.deviceID {
                spData = try blueCreateSignedOssSoDemoData()
            } else {
                throw BlueError(.invalidArguments)
            }
        }
        break
    case "ossSidMobile":
        if spData == nil {
            if device.info.deviceID == blueDemoData.deviceID {
                spData = try blueCreateSignedOssSidDemoData()
            } else {
                throw BlueError(.invalidArguments)
            }
        }
        break
    default:
        // -- Assume regular command
        if spData == nil {
            if device.info.deviceID == blueDemoData.deviceID {
                spData = try blueCreateSignedCommandDemoData(action)
            } else {
                throw BlueError(.invalidArguments)
            }
        }
        
        spData!.command.data = Data()
            
        if let commandData = data, !commandData.isEmpty {
            spData!.command.data.append(contentsOf: commandData)
        }
        
        break
    }
    
    guard let spData = spData else {
        throw BlueError(.invalidState)
    }
    
    return spData
}

private func blueTerminalRequest(action: String, data: Data?) throws -> Data? {
    guard let blueActiveDevice = blueActiveDevice else {
        throw BlueError(.invalidState)
    }
    
    let spData = try blueGetSpDataForAction(device: blueActiveDevice, action: action, data: data)
    
    let statusCodePtr = UnsafeMutablePointer<Int16>.allocate(capacity: 1)
    statusCodePtr.pointee = Int16(blueAsClibReturnCode(.ok).rawValue)
    
    defer { statusCodePtr.deallocate() }
    
    do {
        let spResult: BlueSPResult = try blueClibFunctionInOut(message: spData, { (spDataPtr, spDataSize, resultPtr, resultSize) in
            var returnCode: BlueReturnCode_t = blueAsClibReturnCode(.invalidState)
            
            returnCode = blueSPTransponder_SendRequest_Ext(blueActiveDevice.info.deviceID, blueActiveDevice.spConnection.connectionPtr, spDataPtr, spDataSize, resultPtr, resultSize, statusCodePtr, nil)
            
            return returnCode
        })
        
        return spResult.data
    } catch let error as BlueError {
        if (error.returnCode == .sperrorStatusCode) {
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

public func blueTerminalRequest(action: String, data: Data? = nil) throws -> Void {
    let rawResult: Data? = try blueTerminalRequest(action: action, data: data)
    
    guard rawResult == nil else {
        throw BlueError(.invalidState)
    }
}

public func blueTerminalRequest<DataType: Message>(action: String, data: DataType) throws -> Void {
    let rawData = try blueEncodeMessage(data)
    return try blueTerminalRequest(action: action, data: rawData)
}

public func blueTerminalRequest<ResultType: Message>(action: String, data: Data? = nil) throws -> ResultType {
    let rawResult: Data? = try blueTerminalRequest(action: action, data: data)
    
    guard let rawResult = rawResult else {
        throw BlueError(.invalidState)
    }
    
    return try blueDecodeMessage(rawResult)
}

public func blueTerminalRequest<DataType: Message, ResultType: Message>(action: String, data: DataType) throws -> ResultType {
    let rawData = try blueEncodeMessage(data)
    return try blueTerminalRequest(action: action, data: rawData)
}


public func blueTerminalRun<HandlerResult>(deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, handler: @escaping () throws -> HandlerResult, completion: @escaping (Result<HandlerResult, Error>) -> Void) {
    if (!blueIsInitialized) {
        return completion(.failure(BlueError(.unavailable)))
    }
    
    guard blueActiveDevice == nil else {
        return completion(.failure(BlueError(.unavailable)))
    }
    
    if blueSpTransponder == nil {
        do {
            blueSpTransponder = try BlueSPTransponder(terminalPublicKeysKeychain: blueTerminalPublicKeysKeychain)
        } catch let error {
            return completion(.failure(error))
        }
    }
    
    guard let device = blueGetDevice(deviceID) else {
        return completion(.failure(BlueError(.notFound)))
    }
    
    return DispatchQueue.global(qos: .background).async {
        let wasConnected = device.isConnected
        
        do {
            var handlerResult: HandlerResult? = nil
            
            try blueExecuteWithTimeout({
                blueActiveDevice = device
                
                defer { blueActiveDevice = nil }
                
                if (!wasConnected) {
                    try device.connect()
                }
                
                blueLogDebug("Connected to \(device.info.deviceID)")
                
                var errorThrown: Error? = nil
                
                do
                {
                    handlerResult = try handler()
                } catch {
                    errorThrown = error
                }
                
                if (!wasConnected) {
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
            if (!wasConnected && device.isConnected) {
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

public func blueTerminalRun<HandlerResult>(deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, _ handler: @escaping () throws -> HandlerResult) async throws -> HandlerResult {
    return try await withCheckedThrowingContinuation { continuation in
        blueTerminalRun(deviceID: deviceID, timeoutSeconds: timeoutSeconds, handler: handler) { result in
            continuation.resume(with: result)
        }
    }
}

public func blueTerminalRun(deviceID: String, timeoutSeconds: Double = 30.0, action: String) async throws -> Void {
    try await blueTerminalRun(deviceID: deviceID, {
        try blueTerminalRequest(action: action)
    })
}

public func blueTerminalRun<ResultType: Message>(deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, action: String) async throws -> ResultType {
    return try await blueTerminalRun(deviceID: deviceID, {
        return try blueTerminalRequest(action: action)
    })
}

public func blueTerminalRun<DataType: Message, ResultType: Message>(deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, action: String, data: DataType) async throws -> ResultType {
    return try await blueTerminalRun(deviceID: deviceID, {
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

internal func blueTerminalRun(deviceID: String, timeoutSeconds: Double = 30.0, requests: [BlueTerminalRequest], completion: @escaping (Result<[BlueTerminalResult], Error>) -> Void) {
    let handler: () throws -> [BlueTerminalResult] = {
        var results: [BlueTerminalResult] = []
        
        for request in requests {
            do {
                let data: Data? = try blueTerminalRequest(action: request.action, data: request.data)
                results.append(BlueTerminalResult(statusCode: .ok, data: data))
            } catch let error as BlueTerminalError {
                results.append(BlueTerminalResult(statusCode: error.terminalError.returnCode))
            } catch {
                throw error
            }
        }
        
        return results
    }
    
    blueTerminalRun(deviceID: deviceID, timeoutSeconds: timeoutSeconds, handler: handler, completion: completion)
}

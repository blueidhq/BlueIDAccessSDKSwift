import CBlueIDAccess
import Foundation
import SwiftProtobuf

internal let blueTerminalPublicKeysKeychain = BlueKeychain(attrService: "blueid.terminalKeys")
internal let blueTerminalRequestDataKeychain = BlueKeychain(attrService: "blueid.requestData")

private var blueSpTransponder: BlueSPTransponder? = nil
private var blueActiveDevice: BlueDevice? = nil

public var defaultTimeoutSec: Double = 10

private func blueGetSpTokenForAction(device: BlueDevice, action: String, data: Data?) throws
  -> BlueSPToken
{
  var token: BlueSPToken? = nil

  let storedToken = try blueTerminalRequestDataKeychain.getEntry(
    id: "\(device.info.deviceID):\(action)")

  if let storedToken = storedToken {
    token = try blueDecodeMessage(storedToken)
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

  guard rawResult == nil else {
    throw BlueError(.invalidState)
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
    return completion(.failure(BlueError(.notFound)))
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
public func blueTerminalRun<DataType: Message, ResultType: Message>(
  deviceID: String, timeoutSeconds: Double = defaultTimeoutSec, action: String, data: DataType
) async throws -> ResultType {
  return try await blueTerminalRun(
    deviceID: deviceID,
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

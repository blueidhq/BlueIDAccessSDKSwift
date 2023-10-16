import Foundation
import SwiftProtobuf
import CBlueIDAccess

internal let blueI18n = BlueI18n()

internal func blueIsValidPublicDERKey(_ keyData: Data) -> Bool {
    if (keyData.count <= 0) {
        return false;
    }
    
    let pointer = (keyData as NSData).bytes.bindMemory(to: UInt8.self, capacity: keyData.count)
    
    let returnCode = blueFromClibReturnCode(blueUtils_IsValidPublicDERKey(pointer, UInt16(keyData.count)))
    
    return returnCode == .ok
}

internal func blueExecuteWithTimeout(_ handler: @escaping () throws -> Void, timeoutSeconds: Double = 0) throws -> Void {
    var error: Error? = nil
    
    let workItem = DispatchWorkItem {
        do {
            try handler()
        } catch let e {
            error = e
            return
        }
    }
    
    DispatchQueue.global().async(execute: workItem)
    
    if (timeoutSeconds <= 0) {
        workItem.wait()
    } else {
        if workItem.wait(timeout: DispatchTime.now() + timeoutSeconds) == .timedOut {
            throw BlueError(.timeout)
        }
    }
    
    if let error = error {
        throw error
    }
}

internal func blueAsClibReturnCode(_ returnCode: BlueReturnCode) -> BlueReturnCode_t {
    return BlueReturnCode_t(Int32(returnCode.rawValue))
}

internal func blueFromClibReturnCode(_ returnCode: BlueReturnCode_t) -> BlueReturnCode {
    return BlueReturnCode(rawValue: Int(returnCode.rawValue))!
}

internal func blueClibErrorCheck(_ returnCode: BlueReturnCode_t) throws -> Int32 {
    if (returnCode.rawValue < 0) {
        throw BlueError(blueFromClibReturnCode(returnCode))
    }
    
    return returnCode.rawValue
}

internal func blueClibFunctionIn<MessageType: Message>(message: MessageType, _ handler: (UnsafePointer<UInt8>, UInt16) throws -> BlueReturnCode_t) throws -> Void {
    let outputData: Data = try blueEncodeMessage(message)
    let outputDataSize = UInt16(outputData.count)
    
    try outputData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
        if let rawPtr = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            _ = try blueClibErrorCheck(try handler(rawPtr, outputDataSize));
        } else {
            throw BlueError(.pointerConversionFailed)
        }
    }
}

internal func blueClibFunctionOut<MessageType: Message>(_ handler: (UnsafeMutablePointer<UInt8>, UInt16) throws -> BlueReturnCode_t, maxDataSize: UInt16 = 4096) throws -> MessageType {
    var inputData: Data = Data(count: Int(maxDataSize));
    let inputDataSize: UInt16 = UInt16(inputData.count)
    
    try inputData.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
        if let rawPtr = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            _ = try blueClibErrorCheck(try handler(rawPtr, inputDataSize));
        } else {
            throw BlueError(.pointerConversionFailed)
        }
    }
    
    return try blueDecodeMessage(inputData);
}

internal func blueClibFunctionInOut<MessageType: Message, ResultType: Message>(message: MessageType, _ handler: (_ : UnsafePointer<UInt8>, _ : UInt16, _ : UnsafeMutablePointer<UInt8>, _ : UInt16) -> BlueReturnCode_t, maxDataSize: UInt16 = 4096) throws -> ResultType {
    let inputData: Data = try blueEncodeMessage(message)
    let inputDataSize: UInt16 = UInt16(inputData.count)
    
    var outputData: Data = Data(count: Int(maxDataSize));
    let outputDataSize = UInt16(outputData.count)
    
    try inputData.withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) in
        if let rawInputPtr = inputPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            try outputData.withUnsafeMutableBytes { (outputPointer: UnsafeMutableRawBufferPointer) in
                if let rawOutputPtr = outputPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    _ = try blueClibErrorCheck(handler(rawInputPtr, inputDataSize, rawOutputPtr, outputDataSize));
                } else {
                    throw BlueError(.pointerConversionFailed)
                }
            }
        } else {
            throw BlueError(.pointerConversionFailed)
        }
    }
    
    return try blueDecodeMessage(outputData);
}

internal func blueCopyDataToClib(data: Data, buffer: UnsafeMutablePointer<UInt8>!, bufferSize: UInt32!) throws -> Void {
    if (data.count > bufferSize) {
        throw BlueError(.overflow)
    }
    
    data.copyBytes(to: buffer, from: 0..<data.count)
}

internal func blueCopyDataFromClib(buffer: UnsafePointer<UInt8>!, bufferSize: UInt32) throws -> Data {
    guard buffer != nil && bufferSize > 0 else {
        throw BlueError(.invalidArguments)
    }
    
    let data = Data(bytes: buffer, count: Int(bufferSize))
    
    return data
}

internal func blueEncodeMessage(_ message: Message!, partial: Bool = false) throws -> Data {
    let outputStream = OutputStream(toMemory: ())
    outputStream.open()
    try BinaryDelimited.serialize(message: message, to: outputStream, partial: partial)
    return outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
}

internal func blueDecodeMessage<MessageType: Message>(_ data: Data) throws -> MessageType {
    let inputStream = InputStream(data: data)
    inputStream.open()
    return try! BinaryDelimited.parse(messageType: MessageType.self, from: inputStream, partial: true)
}

internal func blueIBeaconMajorMinorToId(major: Int16, minor: Int16) -> String {
    var buffer = [UInt8](repeating: 0, count: 4)
    
    buffer[0] = UInt8(major >> 8 & 0xFF) // Most significant byte of major (big endian)
    buffer[1] = UInt8(major & 0xFF)      // Least significant byte of major (big endian)
    buffer[2] = UInt8(minor >> 8 & 0xFF) // Most significant byte of minor (big endian)
    buffer[3] = UInt8(minor & 0xFF)      // Least significant byte of minor (big endian)
    
    var result = ""
    
    for byte in buffer {
        result += String(UnicodeScalar(byte))
    }
    
    return result
}

internal func blueCastArg<ArgumentType>(_ type: ArgumentType.Type, _ value: Any?, isOptional: Bool = false, result: inout ArgumentType?) throws {
    if value == nil {
        guard isOptional else {
            throw BlueError(.invalidArguments)
        }
        result = Optional<ArgumentType>.none
    } else if let value = value as? ArgumentType {
        result = value
    } else if let messageType = ArgumentType.self as? Message.Type, let value = value as? Data {
        let inputStream = InputStream(data: value)
        inputStream.open()
        result = try! BinaryDelimited.parse(messageType: messageType, from: inputStream, partial: true) as! ArgumentType
    } else {
        throw BlueError(.invalidArguments)
    }
}

internal func blueCastArg<ArgumentType: Message>(_ type: ArgumentType.Type, _ value: Any?, isOptional: Bool = false, result: inout ArgumentType?) throws {
    var dataResult: Data? = nil
    
    try blueCastArg(Data.self, value, isOptional: isOptional, result: &dataResult)
    
    if let dataResult = dataResult {
        result = try blueDecodeMessage(dataResult)
    } else {
        result = Optional<ArgumentType>.none
    }
}

internal func blueCastArg<ArgumentType>(_ type: ArgumentType.Type, _ value: Any?) throws -> ArgumentType? {
    var result: ArgumentType? = nil
    try blueCastArg(type, value, isOptional: true, result: &result)
    return result
}

internal func blueCastArg<ArgumentType>(_ type: ArgumentType.Type, _ value: Any?) throws -> ArgumentType {
    var result: ArgumentType? = nil
    try blueCastArg(type, value, isOptional: true, result: &result)
    
    guard let result = result else {
        throw BlueError(.invalidState)
    }
    
    return result
}

internal func blueCastArg<ArgumentType: Message>(_ type: ArgumentType.Type, _ value: Any?) throws -> ArgumentType? {
    var result: ArgumentType? = nil
    try blueCastArg(type, value, isOptional: true, result: &result)
    return result
}

internal func blueCastArg<ArgumentType: Message>(_ type: ArgumentType.Type, _ value: Any?) throws -> ArgumentType {
    var result: ArgumentType? = nil
    try blueCastArg(type, value, isOptional: true, result: &result)
    
    guard let result = result else {
        throw BlueError(.invalidState)
    }
    
    return result
}

internal func blueCastResult<ResultType>(_ result: ResultType?) throws -> Any {
    guard let result = result else {
        throw BlueError(.invalidState)
    }
    
    if let result = result as? Message {
        return try blueEncodeMessage(result)
    }
    
    return result
}



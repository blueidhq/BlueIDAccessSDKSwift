import Foundation
import CBlueIDAccess

internal func createSignature(inputData: Data, privateKey: Data) throws -> Data? {
    let dataSize: UInt16 = UInt16(inputData.count)
    let privateKeyBufferSize = UInt16(privateKey.count)
    
    var outputData: Data = Data(count: 4096)
    let signatureSize = UInt16(outputData.count)
    
    var pReturnedSignatureSize: UInt16 = 0
    
    try inputData.withUnsafeBytes { (inputPointer: UnsafeRawBufferPointer) in
        guard let pData = inputPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw BlueError(.pointerConversionFailed)
        }
        
        try privateKey.withUnsafeBytes { (inputPointer2: UnsafeRawBufferPointer) in
            guard let pPrivateKeyBuffer = inputPointer2.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw BlueError(.pointerConversionFailed)
            }
            
            try outputData.withUnsafeMutableBytes { (outputPointer: UnsafeMutableRawBufferPointer) in
                guard let pSignature = outputPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw BlueError(.pointerConversionFailed)
                }
                
                _ = try blueClibErrorCheck(
                    blueUtils_CreateSignature_Ext(
                        pData,
                        dataSize,
                        pSignature,
                        signatureSize,
                        &pReturnedSignatureSize,
                        pPrivateKeyBuffer,
                        privateKeyBufferSize
                    )
                )
            }
        }
    }
    
    return outputData.prefix(Int(pReturnedSignatureSize))
}

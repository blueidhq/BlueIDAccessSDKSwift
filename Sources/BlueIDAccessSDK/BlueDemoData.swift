import Foundation
import CBlueIDAccess

internal let blueDemoData = BlueSharedDemoData()

internal func blueCreateSignedCommandDemoData(_ command: String) throws -> BlueSPData {
    var spData = BlueSPData()
    spData.signature = Data()
    
    spData.command = BlueSPDataCommand()
    spData.command.credentialID = BlueCredentialId()
    spData.command.credentialID.id = "DEMOIDENTI"
    spData.command.command = command
    spData.command.validityStart = BlueLocalTimestamp(2000, 1, 1)
    spData.command.validityEnd = BlueLocalTimestamp(2100, 1, 1)
    spData.command.data = Data()
    
    return try blueCreateSignedDemoData(spData)
}

internal func blueCreateSignedOssSoDemoData() throws -> BlueSPData {
    var spData = BlueSPData()
    spData.signature = Data()
    
    let demoConfiguration = blueCreateOssSoDemoConfiguration()
    
    let provisioningData = try blueCommands.ossSoCreateStandardProvisioningData.run("SO12345678", 1)
    
    spData.ossSo = try blueCommands.ossSoCreateMobile.run(provisioningData, demoConfiguration)
    
    return try blueCreateSignedDemoData(spData)
}

internal func blueCreateSignedOssSidDemoData() throws -> BlueSPData {
    var spData = BlueSPData()
    spData.signature = Data()
    
    let provisioningData = try blueCommands.ossSidCreateProvisioningData.run("SID1234567")
    
    spData.ossSid = try blueCommands.ossSidCreateMobile.run(provisioningData)
    
    return try blueCreateSignedDemoData(spData)
}

private func blueCreateSignedDemoData(_ spData: BlueSPData) throws -> BlueSPData {
    let signaturePrivateKey = blueDemoData.signaturePrivateKey
    
    var result: BlueSPData? = nil
    
    try signaturePrivateKey.withUnsafeBytes { (signaturePrivateKeyPointer: UnsafeRawBufferPointer) in
        if let signaturePrivateKeyPtr = signaturePrivateKeyPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            result = try blueClibFunctionInOut(message: spData, { (inSpDataPtr, inSpDataSize, signedSpDataPtr, signedSpDataSize) in
                return blueSP_SignData_Ext(inSpDataPtr, inSpDataSize, signedSpDataPtr, signedSpDataSize, signaturePrivateKeyPtr, UInt16(signaturePrivateKey.count))
            })
        } else {
            throw BlueError(.pointerConversionFailed)
        }
    }
    
    guard let result = result else {
        throw BlueError(.invalidState)
    }
    
    return result
}

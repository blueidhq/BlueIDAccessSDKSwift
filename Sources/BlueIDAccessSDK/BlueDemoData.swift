import CBlueIDAccess
import Foundation

internal let blueDemoData = BlueSharedDemoData()

public func blueCreateAccessCredentialDemo() -> BlueAccessCredential {
    var credential = BlueAccessCredential()
    credential.name = "Someone's iPhone"
    credential.siteName = "Somwehere"
    credential.credentialID.id = "8M-1xA3oze"
    credential.credentialType = BlueCredentialType.regular
    credential.privateKey = Data([
        48,129,135,2,1,0,48,19,6,7,42,134,72,206,61,2,1,6,8,42,134,
        72,206,61,3,1,7,4,109,48,107,2,1,1,4,32,152,140,1,4,26,171,
        230,250,50,58,133,42,72,22,74,103,101,4,52,190,56,249,13,177,
        58,239,59,152,24,77,206,70,161,68,3,66,0,4,20,157,192,46,230,
        76,158,83,178,64,1,123,2,215,50,237,229,179,163,90,65,21,151,
        138,176,247,72,158,170,236,93,84,40,38,57,18,121,60,215,228,
        21,16,242,30,21,101,248,90,139,31,61,150,198,4,196,146,96,174,
        92,230,194,140,79,9
    ])

    return credential
}

internal func blueCreateSignedCommandDemoToken(_ command: String) throws -> BlueSPToken {
  var token = BlueSPToken()
  token.signature = Data()

  token.command = BlueSPTokenCommand()
  token.command.credentialID = BlueCredentialId()
  token.command.credentialID.id = "DEMOIDENTI"
  token.command.command = command
  token.command.validityStart = BlueLocalTimestamp(2000, 1, 1)
  token.command.validityEnd = BlueLocalTimestamp(2100, 1, 1)
  token.command.data = Data()

  return try blueCreateSignedDemoToken(token)
}

internal func blueCreateSignedOssSoDemoToken() throws -> BlueSPToken {
  var token = BlueSPToken()
  token.signature = Data()

  let demoConfiguration = blueCreateOssSoDemoConfiguration()

  let provisioningData = try blueCommands.ossSoCreateStandardProvisioningData.run("SO12345678", 1)

  token.ossSo = try blueCommands.ossSoCreateMobile.run(provisioningData, demoConfiguration)

  return try blueCreateSignedDemoToken(token)
}

internal func blueCreateSignedOssSidDemoToken() throws -> BlueSPToken {
  var token = BlueSPToken()
  token.signature = Data()

  let provisioningData = try blueCommands.ossSidCreateProvisioningData.run("SID1234567")

  token.ossSid = try blueCommands.ossSidCreateMobile.run(provisioningData)

  return try blueCreateSignedDemoToken(token)
}

private func blueCreateSignedDemoToken(_ token: BlueSPToken) throws -> BlueSPToken {
  let signaturePrivateKey = blueDemoData.signaturePrivateKey

  var result: BlueSPToken? = nil

  try signaturePrivateKey.withUnsafeBytes { (signaturePrivateKeyPointer: UnsafeRawBufferPointer) in
    if let signaturePrivateKeyPtr = signaturePrivateKeyPointer.baseAddress?.assumingMemoryBound(
      to: UInt8.self)
    {
      result = try blueClibFunctionInOut(
        message: token,
        { (inSpTokenPtr, inSpTokenSize, signedSpTokenPtr, signedSpTokenSize) in
          return blueSP_SignToken_Ext(
            inSpTokenPtr, inSpTokenSize, signedSpTokenPtr, signedSpTokenSize, signaturePrivateKeyPtr,
            UInt16(signaturePrivateKey.count))
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

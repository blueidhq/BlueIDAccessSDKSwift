import CBlueIDAccess
import Foundation

internal let blueDemoData = BlueSharedDemoData()

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

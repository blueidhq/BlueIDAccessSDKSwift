import Foundation
import CBlueIDAccess
import Dispatch

private func blueCreateOssSoDemoSettings() -> BlueOssSoSettings {
    var result = BlueOssSoSettings()
    
    let mfCfgDef = BlueOssSoMifareDesfireConfiguration()
    
    result.mifareDesfireConfig = BlueOssSoMifareDesfireConfiguration()
    result.mifareDesfireConfig.piccMasterKey = mfCfgDef.piccMasterKey
    result.mifareDesfireConfig.appMasterKey = mfCfgDef.appMasterKey
    result.mifareDesfireConfig.projectKey = mfCfgDef.projectKey
    result.mifareDesfireConfig.aid = mfCfgDef.aid
    
    return result
}

internal func blueCreateOssSoDemoConfiguration() -> BlueOssSoConfiguration {
    var configuration = BlueOssSoConfiguration()
    
    configuration.data = BlueOssSoFileData()
    configuration.data.validity = BlueLocalTimestamp(2100, 1, 1)
    configuration.data.siteID = 1
    configuration.data.numberOfDayIdsPerDtschedule = 0
    configuration.data.numberOfTimePeriodsPerDayID = 0
    configuration.data.hasExtensions_p = true
    configuration.data.doorInfoEntries = []
    configuration.data.dtSchedules = []
    
    var doorInfo = BlueOssSoDoorInfo()
    doorInfo.id = 1
    doorInfo.accessBy = .doorID
    doorInfo.dtScheduleNumber = 0
    doorInfo.accessType = .defaultTime
    
    configuration.data.doorInfoEntries.append(doorInfo)
    
    return configuration
}

public struct BlueOssSoCreateMobileCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoProvisioningData.self, arg0),
            try blueCastArg(BlueOssSoConfiguration.self, arg1)
        ))
    }
    
    public func run(_ provisioningData: BlueOssSoProvisioningData, _ configuration: BlueOssSoConfiguration) throws -> BlueOssSoMobile {
        let pStorage = UnsafeMutablePointer<BlueOssSoStorage_t>.allocate(capacity: 1)
        
        defer {
            pStorage.deallocate()
        }
        
        return try blueClibFunctionOut({ ossSoMobileOutputPtr, ossSoMobileOutputSize in
            let ossSoMobileOutputSizeMutable = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
            
            defer { ossSoMobileOutputSizeMutable.deallocate() }
            
            ossSoMobileOutputSizeMutable.pointee = ossSoMobileOutputSize
            
            _ = try blueClibErrorCheck(blueOssSo_GetStorage_Ext(BlueTransponderType_t(UInt32(BlueTransponderType.mobileTransponder.rawValue)), pStorage, nil, 0, ossSoMobileOutputPtr, ossSoMobileOutputSizeMutable))
            
            // Clear configuration as we always want to use the default one for mobile
            var usedProvisioningData = provisioningData
            usedProvisioningData.clearConfiguration()
            
            try blueClibFunctionIn(message: usedProvisioningData, { dataPtr, dataSize in
                return blueOssSo_Provision_Ext(pStorage, dataPtr, dataSize)
            })
            
            try blueClibFunctionIn(message: configuration, { (configPtr, configSize) in
                return blueOssSo_UpdateConfiguration_Ext(pStorage, configPtr, configSize, false)
            })
            
            return blueAsClibReturnCode(.ok)
        })
    }
}


fileprivate func executeOssSoNfc<ResultType>(
    settings: BlueOssSoSettings?,
    successMessage: String,
    handler: @escaping (_: UnsafeMutablePointer<BlueOssSoStorage_t>) throws -> ResultType,
    errorHandler: ((_: Error) -> String?)? = nil) throws -> ResultType {
    
    var result: ResultType? = nil
    
    let settingsInUse: BlueOssSoSettings = settings ?? blueCreateOssSoDemoSettings()
    
    try blueNfcExecute(
        { transponderType in
            let pStorage = UnsafeMutablePointer<BlueOssSoStorage_t>.allocate(capacity: 1)
            
            defer {
                pStorage.deallocate()
            }
            
            try blueClibFunctionIn(message: settingsInUse, { (dataPtr, dataSize) in
                return blueOssSo_GetStorage_Ext(BlueTransponderType_t(UInt32(transponderType.rawValue)), pStorage, dataPtr, dataSize, nil, nil)
            })
            
            result = try handler(pStorage)
            
            return successMessage
        }, 
        errorHandler: errorHandler
    )
    
    guard let result = result else {
        throw BlueError(.invalidState)
    }
    
    return result
}

public struct BlueOssSoFormatCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoSettings.self, arg0),
            try blueCastArg(Bool.self, arg1) ?? false
        ))
    }
    
    public func run(_ settings: BlueOssSoSettings?, _ factoryReset: Bool = false) throws -> Void {
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessFormatMessage, handler: { pStorage in
            _ = try blueClibErrorCheck(blueOssSo_Format(pStorage, factoryReset))
        })
    }
}

public struct BlueOssSoGetStorageProfileCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueTransponderType.self, arg0),
            try blueCastArg(BlueOssSoProvisioningConfiguration.self, arg1)
        ))
    }
    
    public func run(_ transponderType: BlueTransponderType, _ provisioningConfig: BlueOssSoProvisioningConfiguration?) throws -> BlueOssSoStorageProfile {
        let pStorage = UnsafeMutablePointer<BlueOssSoStorage_t>.allocate(capacity: 1)
        
        defer {
            pStorage.deallocate()
        }
        
        _ = try blueClibErrorCheck(blueOssSo_GetStorage(BlueTransponderType_t(UInt32(transponderType.rawValue)), pStorage, nil, nil, nil))
        
        if let provisioningConfig = provisioningConfig {
            return try blueClibFunctionInOut(message: provisioningConfig, { (configDataPtr, configDataSize, dataPtr, dataSize) in
                return blueOssSo_GetStorageProfile_Ext(pStorage, configDataPtr, configDataSize, dataPtr, dataSize)
            })
        } else {
            return try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSo_GetStorageProfile_Ext(pStorage, nil, 0, dataPtr, dataSize)
            })
        }
    }
}

internal func createOssProvisioningData(_ intervention: Bool, _ credentialId: String, _ siteId: Int, _ configuration: BlueOssSoProvisioningConfiguration? = nil) throws -> BlueOssSoProvisioningData {
    if (siteId <= 0) {
        throw BlueError(.invalidArguments)
    }
    
    var result = BlueOssSoProvisioningData()
    
    if let configuration = configuration {
        result.configuration = configuration
    }
    
    result.credentialType.typeSource = .oss
    result.credentialType.oss = BlueOssSoCredentialTypeOss()
    result.credentialType.oss.credential = intervention ? .interventionMedia : .standard
    result.credentialID.id = credentialId
    result.siteID = UInt32(siteId)
    
    return result
}

public struct BlueOssSoCreateStandardProvisioningDataCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(String.self, arg0),
            try blueCastArg(Int.self, arg1),
            try blueCastArg(BlueOssSoProvisioningConfiguration.self, arg1)
        ))
    }
    
    public func run(_ credentialId: String, _ siteId: Int, _ configuration: BlueOssSoProvisioningConfiguration? = nil) throws -> BlueOssSoProvisioningData {
        return try createOssProvisioningData(false, credentialId, siteId, configuration)
    }
}

public struct BlueOssSoCreateInterventionProvisioningDataCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(String.self, arg0),
            try blueCastArg(Int.self, arg1),
            try blueCastArg(BlueOssSoProvisioningConfiguration.self, arg1)
        ))
    }
    
    public func run(_ credentialId: String, _ siteId: Int, _ configuration: BlueOssSoProvisioningConfiguration? = nil) throws -> BlueOssSoProvisioningData {
        return try createOssProvisioningData(true, credentialId, siteId, configuration)
    }
}

public struct BlueOssSoIsProvisionedCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoSettings.self, arg0)
        ))
    }
    
    public func run(_ settings: BlueOssSoSettings?) throws -> Bool {
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessIsProvisionedMessage, handler: { pStorage in
            return blueOssSo_IsProvisioned(pStorage) == BlueReturnCode_Ok
        })
    }
}

public struct BlueOssSoProvisionCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoSettings.self, arg0),
            try blueCastArg(BlueOssSoProvisioningData.self, arg1)
        ))
    }
    
    public func run(_ settings: BlueOssSoSettings?, _ provisioningData: BlueOssSoProvisioningData) throws -> Void {
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessProvisionMessage, handler: { pStorage in
            return try blueClibFunctionIn(message: provisioningData, { (dataPtr, dataSize) in
                return blueOssSo_Provision_Ext(pStorage, dataPtr, dataSize)
            })
        })
    }
}

public struct BlueOssSoUnprovisionCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoSettings.self, arg0)
        ))
    }
    
    public func run(_ settings: BlueOssSoSettings?) throws -> Void {
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessUnprovisionMessage, handler: { pStorage in
            _ = try blueClibErrorCheck(blueOssSo_Unprovision(pStorage))
        })
    }
}

public struct BlueOssSoReadConfigurationCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoSettings.self, arg0)
        ))
    }
    
    public func run(_ settings: BlueOssSoSettings?, errorHandler: ((_: Error) -> String?)? = nil) throws -> BlueOssSoConfiguration {
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessReadConfigurationMessage, handler: { pStorage in
            return try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
            })
        }, errorHandler: errorHandler)
    }
}

public struct BlueOssSoUpdateConfigurationCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSoSettings.self, arg0),
            try blueCastArg(BlueOssSoConfiguration.self, arg1),
            try blueCastArg(Bool.self, arg2)
        ))
    }
    
    public func run(_ settings: BlueOssSoSettings?, _ newConfiguration: BlueOssSoConfiguration?, _ clearEvents: Bool) throws -> Void {
        let usedNewConfiguration = newConfiguration ?? blueCreateOssSoDemoConfiguration()
        
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessUpdateConfigurationMessage, handler: { pStorage in
            try blueClibFunctionIn(message: usedNewConfiguration, { (newConfigPtr, newConfigSize) in
                return blueOssSo_UpdateConfiguration_Ext(pStorage, newConfigPtr, newConfigSize, clearEvents)
            })
        })
    }
}

public struct BlueFormatOssSoCredentialCommand: BlueCommand {
    func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any? {
        return try run(
            organisation: blueCastArg(String.self, arg0),
            siteID: blueCastArg(Int.self, arg1)
        )
    }
    
    public func run(organisation: String, siteID: Int) throws {
        guard let credential = blueGetAccessCredential(organisation: organisation, siteID: siteID, credentialType: .nfcWriter) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let ossSoSettings = try blueGetOssSoSettings(credentialID: credential.credentialID.id)
        
        try BlueOssSoFormatCommand().run(ossSoSettings, true)
    }
}

public struct BlueReadOssSoCredentialCommand: BlueCommand {
    func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any? {
        return try run(
            organisation: blueCastArg(String.self, arg0),
            siteID: blueCastArg(Int.self, arg1)
        )
    }
    
    public func run(organisation: String, siteID: Int) throws -> BlueOssSoConfiguration {
        guard let credential = blueGetAccessCredential(organisation: organisation, siteID: siteID, credentialType: .nfcWriter) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let ossSoSettings = try blueGetOssSoSettings(credentialID: credential.credentialID.id)
        
        return try BlueOssSoReadConfigurationCommand().run(ossSoSettings) { error in
            if let blueError = error as? BlueError {
                if (blueError.returnCode == .notFound) {
                    return blueI18n.nfcInitializingWritingProcess
                }
            }
            
            return nil
        }
    }
}

/**
 * @class BlueWriteOssSoCredentialCommand represents a command to write/update a credential for a transponder using NFC communication.
 */
public class BlueWriteOssSoCredentialCommand: BlueAPIAsyncCommand {
    override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: blueCastArg(String.self, arg0),
            organisation: blueCastArg(String.self, arg1),
            siteID: blueCastArg(Int.self, arg2)
        )
    }
    
    /// Tries to write/update a transponder's credential.
    ///
    /// - parameter credentialID: The credential ID to be written in the Transponder.
    /// - parameter organisation: The organization to which the credential belongs.
    /// - parameter siteID: The site ID to which the credential belongs.
    /// - throws: Throws an error of type `BlueError(.notFound)` If no NFC Writer credentials match the given organisation and site ID.
    /// - throws: Throws an error of type `BlueError(.notSuported)` If the macOS version is earlier than 10.15.
    /// - returns: A boolean indicating whether a new configuration has been written in the Transponder or not.
    public func runAsync(credentialID: String, organisation: String, siteID: Int) async throws -> Bool {
        guard #available(macOS 10.15, *) else {
            throw BlueError(.sdkUnsupportedPlatform)
        }
        
        guard let credential = blueGetAccessCredential(organisation: organisation, siteID: siteID, credentialType: .nfcWriter) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let ossSoSettings = try blueGetOssSoSettings(credentialID: credential.credentialID.id)
        let ossSoProvisioningData = try BlueOssSoCreateStandardProvisioningDataCommand().run(credentialID, siteID)
        
        let newConfiguration: BlueOssSoConfiguration? = try executeOssSoNfc(settings: ossSoSettings, successMessage: blueI18n.nfcOssSuccessUpdateConfigurationMessage, handler: { pStorage in
            
            let isProvisioned = blueOssSo_IsProvisioned(pStorage) == BlueReturnCode_Ok
            if (!isProvisioned) {
                
                // provision
                try blueClibFunctionIn(message: ossSoProvisioningData, { (dataPtr, dataSize) in
                    return blueOssSo_Provision_Ext(pStorage, dataPtr, dataSize)
                })
            } else {
                // get current configuration
                let transponderConfiguration: BlueOssSoConfiguration = try blueClibFunctionOut({ (dataPtr, dataSize) in
                    return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
                })
                
                // There can only be one credential per site per transponder, but there can be multiple credentials on the same transponder for different sites.
                guard transponderConfiguration.info.credentialID.id == credentialID else {
                    throw BlueError(.alreadyExists)
                }
                
                // push transponder's events to the backend
                try blueRunAsyncBlocking {
                    try await BlueOssSoAPIHelper(self.blueAPI!)
                        .pushEventLogs(nfcCredential: credential, ossSoConfiguration: transponderConfiguration)
                }
                
                // clear transponders's events
                _ = try blueClibErrorCheck(blueOssSo_ClearEvents(pStorage))
            }
            
            // sync and get configuration, if any
            let newConfiguration = try blueRunAsyncBlocking {
                return try await BlueOssSoAPIHelper(self.blueAPI!)
                    .synchronizeOfflineCredential(nfcCredential: credential, offlineCredentialID: credentialID)
            }
            
            // no configuration means that the credential has not been refreshed in the backend and there is nothing to be updated here
            if let newConfiguration = newConfiguration {
                
                // update
                try blueClibFunctionIn(message: newConfiguration, { (newConfigPtr, newConfigSize) in
                    return blueOssSo_UpdateConfiguration_Ext(pStorage, newConfigPtr, newConfigSize, false)
                })
            }
            
            return newConfiguration
        })
        
        return newConfiguration != nil
    }
}

/**
 * @class BlueRefreshOssSoCredentialCommand represents a command to refresh credentials for a transponder using NFC communication.
 * This class encapsulates the process of starting an NFC session, reading the transponder configuration, retrieving a fresh configuration from the backend, and writing it back to the transponder.
 * Subsequently, transponder events are pushed to the backend.
 */
public class BlueRefreshOssSoCredentialCommand: BlueAPIAsyncCommand {
    override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            organisation: blueCastArg(String.self, arg0),
            siteID: blueCastArg(Int.self, arg1)
        )
    }
    
    /// Tries to refresh the transponder's credential.
    ///
    /// - parameter organisation: The organization to which the transponder belongs.
    /// - parameter siteID: The site ID to which the transponder belongs.
    /// - throws: Throws an error of type `BlueError(.notFound)` If no NFC Writer credentials match the given organisation and site ID.
    /// - throws: Throws an error of type `BlueError(.notSuported)` If the macOS version is earlier than 10.15.
    /// - returns: The configuration stored in the transponder.
    public func runAsync(organisation: String, siteID: Int) async throws -> BlueOssSoConfiguration {
        guard #available(macOS 10.15, *) else {
            throw BlueError(.sdkUnsupportedPlatform)
        }
        
        guard let credential = blueGetAccessCredential(organisation: organisation, siteID: siteID, credentialType: .nfcWriter) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        let ossSoSettings = try blueGetOssSoSettings(credentialID: credential.credentialID.id)
        
        return try executeOssSoNfc(settings: ossSoSettings, successMessage: blueI18n.nfcOssSuccessUpdateConfigurationMessage, handler: { pStorage in
            
            // get current configuration
            let transponderConfiguration: BlueOssSoConfiguration = try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
            })
            
            // push transponder's events to the backend
            try blueRunAsyncBlocking {
                try await BlueOssSoAPIHelper(self.blueAPI!)
                    .pushEventLogs(nfcCredential: credential, ossSoConfiguration: transponderConfiguration)
            }
            
            // clear transponders's events
            _ = try blueClibErrorCheck(blueOssSo_ClearEvents(pStorage))
            
            // sync and get configuration, if any
            let newConfiguration: BlueOssSoConfiguration? = try blueRunAsyncBlocking {
                return try await BlueOssSoAPIHelper(self.blueAPI!)
                    .synchronizeOfflineCredential(nfcCredential: credential, offlineCredentialID: transponderConfiguration.info.credentialID.id)
            }
            
            // no configuration means that the credential has not been refreshed in the backend and there is nothing to be updated here
            if let newConfiguration = newConfiguration {
                
                // update
                try blueClibFunctionIn(message: newConfiguration, { (newConfigPtr, newConfigSize) in
                    return blueOssSo_UpdateConfiguration_Ext(pStorage, newConfigPtr, newConfigSize, false)
                })
            }
            
            // return updated configuration
            return try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
            })
        })
    }
}

/**
 * @class BlueRefreshOssSoCredentialsCommand represents a command to refresh all credentials for a transponder using NFC communication.
 * This class encapsulates the process of starting an NFC session, reading each transponder configuration, retrieving a fresh configuration from the backend, and writing it back to the transponder.
 * Subsequently, transponder events are pushed to the backend.
 */
public class BlueRefreshOssSoCredentialsCommand: BlueAPIAsyncCommand {
    
    override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync()
    }
    
    /// Tries to refresh each transponder's credential.
    ///
    /// - throws: Throws an error of type `BlueError(.notFound)` If no NFC Writer credentials are found.
    /// - throws: Throws an error of type `BlueError(.notSuported)` If the macOS version is earlier than 10.15.
    /// - returns: The status of each NFC credential, and in the case of success, the configuration stored in the transponder.
    public func runAsync() async throws -> BlueRefreshOssSoCredentials {
        guard #available(macOS 10.15, *) else {
            throw BlueError(.sdkUnsupportedPlatform)
        }
        
        let credentials = try await BlueGetAccessCredentialsCommand().runAsync(credentialType: .nfcWriter, includePrivateKey: true).credentials
        
        guard !credentials.isEmpty else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        var refreshResult = BlueRefreshOssSoCredentials()
        
        try? blueNfcExecute({ transponderType in
            refreshResult.credentials = credentials.map{ credential in
                
                var refreshResultItem = BlueRefreshOssSoCredential()
                refreshResultItem.credentialID = credential.credentialID
                
                let pStorage = UnsafeMutablePointer<BlueOssSoStorage_t>.allocate(capacity: 1)
                
                defer {
                    pStorage.deallocate()
                }
                
                do {
                    let ossSoSettings = try blueGetOssSoSettings(credentialID: credential.credentialID.id)
                    
                    try blueClibFunctionIn(message: ossSoSettings, { (dataPtr, dataSize) in
                        return blueOssSo_GetStorage_Ext(BlueTransponderType_t(UInt32(transponderType.rawValue)), pStorage, dataPtr, dataSize, nil, nil)
                    })
                    
                    let isProvisioned = blueOssSo_IsProvisioned(pStorage) == BlueReturnCode_Ok
                    if (!isProvisioned) {
                        refreshResultItem.status = .unsupported
                    } else {
                        do {
                            // get current configuration
                            let transponderConfiguration: BlueOssSoConfiguration = try blueClibFunctionOut({ (dataPtr, dataSize) in
                                return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
                            })
                            
                            // push transponder's events to the backend
                            try blueRunAsyncBlocking {
                                try await BlueOssSoAPIHelper(self.blueAPI!)
                                    .pushEventLogs(nfcCredential: credential, ossSoConfiguration: transponderConfiguration)
                            }
                            
                            // clear transponders's events
                            _ = try blueClibErrorCheck(blueOssSo_ClearEvents(pStorage))
                            
                            // sync and get configuration, if any
                            let newConfiguration: BlueOssSoConfiguration? = try blueRunAsyncBlocking {
                                return try await BlueOssSoAPIHelper(self.blueAPI!)
                                    .synchronizeOfflineCredential(nfcCredential: credential, offlineCredentialID: transponderConfiguration.info.credentialID.id)
                            }
                            
                            // no configuration means that the credential has not been refreshed in the backend and there is nothing to be updated here
                            if let newConfiguration = newConfiguration {
                                
                                // update
                                try blueClibFunctionIn(message: newConfiguration, { (newConfigPtr, newConfigSize) in
                                    return blueOssSo_UpdateConfiguration_Ext(pStorage, newConfigPtr, newConfigSize, false)
                                })
                                
                                refreshResultItem.status = .succeeded
                            } else {
                                refreshResultItem.status = .notNeeded
                            }
                            
                            let configuration: BlueOssSoConfiguration? = try? blueClibFunctionOut({ (dataPtr, dataSize) in
                                return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
                            })
                            
                            if let configuration = configuration {
                                refreshResultItem.configuration = configuration
                            }
                        } catch {
                            refreshResultItem.status = .failed
                            
                            blueLogError(error.localizedDescription)
                        }
                    }
                } catch {
                    refreshResultItem.status = .unsupported
                    
                    blueLogError(error.localizedDescription)
                }
                
                return refreshResultItem
            }
            
            if (refreshResult.hasFailedItems()) {
                throw BlueError(.error)
            }
            
            return blueI18n.nfcOssSuccessUpdateConfigurationMessage
        })
        
        return refreshResult
    }
}

private func blueGetOssSoSettings(credentialID: String) throws -> BlueOssSoSettings {
    guard let ossSoEntry: BlueOssEntry = try blueAccessOssSettingsKeyChain.getCodableEntry(id: credentialID) else {
        throw BlueError(.sdkOssEntryNotFound)
    }
    
    guard let ossSoSettingsData = ossSoEntry.ossSo else {
        throw BlueError(.sdkOssSoSettingsNotFound)
    }
    
    return try blueDecodeMessage(ossSoSettingsData)
}

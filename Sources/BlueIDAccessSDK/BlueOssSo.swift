import Foundation
import CBlueIDAccess

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

fileprivate func executeOssSoNfc<ResultType>(settings: BlueOssSoSettings?, successMessage: String, handler: @escaping (_: UnsafeMutablePointer<BlueOssSoStorage_t>) throws -> ResultType) throws -> ResultType {
    var result: ResultType? = nil
    
    let settingsInUse: BlueOssSoSettings = settings ?? blueCreateOssSoDemoSettings()
    
    try blueNfcExecute({ transponderType in
        let pStorage = UnsafeMutablePointer<BlueOssSoStorage_t>.allocate(capacity: 1)
        
        defer {
            pStorage.deallocate()
        }
        
        try blueClibFunctionIn(message: settingsInUse, { (dataPtr, dataSize) in
            return blueOssSo_GetStorage_Ext(BlueTransponderType_t(UInt32(transponderType.rawValue)), pStorage, dataPtr, dataSize, nil, nil)
        })
        
        result = try handler(pStorage)
        
        return successMessage
    })
    
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
    
    public func run(_ settings: BlueOssSoSettings?) throws -> BlueOssSoConfiguration {
        return try executeOssSoNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessReadConfigurationMessage, handler: { pStorage in
            return try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSo_ReadConfiguration_Ext(pStorage, dataPtr, dataSize, BlueOssSoReadWriteFlags_t(rawValue: BlueOssSoReadWriteFlags_All.rawValue))
            })
        })
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


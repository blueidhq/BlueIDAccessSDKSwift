import Foundation
import CBlueIDAccess

private func blueCreateOssSidDemoSettings() -> BlueOssSidSettings {
    var result = BlueOssSidSettings()
    
    let mfCfgDef = BlueOssSidMifareDesfireConfiguration()
    
    result.mifareDesfireConfig = BlueOssSidMifareDesfireConfiguration()
    result.mifareDesfireConfig.piccMasterKey = mfCfgDef.piccMasterKey
    result.mifareDesfireConfig.appMasterKey = mfCfgDef.appMasterKey
    result.mifareDesfireConfig.projectKey = mfCfgDef.projectKey
    result.mifareDesfireConfig.aid = mfCfgDef.aid
    
    return result
}

public struct BlueOssSidCreateMobileCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSidProvisioningData.self, arg0)
        ))
    }
    
    public func run(_ provisioningData: BlueOssSidProvisioningData) throws -> BlueOssSidMobile {
        let pStorage = UnsafeMutablePointer<BlueOssSidStorage_t>.allocate(capacity: 1)
        
        defer {
            pStorage.deallocate()
        }
        
        return try blueClibFunctionOut({ ossSidMobileOutputPtr, ossSidMobileOutputSize in
            let ossSidMobileOutputSizeMutable = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)

            defer { ossSidMobileOutputSizeMutable.deallocate() }
            
            ossSidMobileOutputSizeMutable.pointee = ossSidMobileOutputSize
            
            _ = try blueClibErrorCheck(blueOssSid_GetStorage_Ext(BlueTransponderType_t(UInt32(BlueTransponderType.mobileTransponder.rawValue)), pStorage, nil, 0, ossSidMobileOutputPtr, ossSidMobileOutputSizeMutable))
            
            // Clear configuration as we always want to use the default one for mobile
            var usedProvisioningData = provisioningData
            usedProvisioningData.clearConfiguration()
            
            try blueClibFunctionIn(message: usedProvisioningData, { dataPtr, dataSize in
                return blueOssSid_Provision_Ext(pStorage, dataPtr, dataSize)
            })
            
            return blueAsClibReturnCode(.ok)
        })
    }
}

fileprivate func executeOssSidNfc<ResultType>(settings: BlueOssSidSettings?, successMessage: String, handler: @escaping (_: UnsafeMutablePointer<BlueOssSidStorage_t>) throws -> ResultType) throws -> ResultType {
    var result: ResultType? = nil
    
    let settingsInUse: BlueOssSidSettings = settings ?? blueCreateOssSidDemoSettings()
    
    try blueNfcExecute({ transponderType in
        let pStorage = UnsafeMutablePointer<BlueOssSidStorage_t>.allocate(capacity: 1)
        
        defer {
            pStorage.deallocate()
        }
        
        try blueClibFunctionIn(message: settingsInUse, { (dataPtr, dataSize) in
            return blueOssSid_GetStorage_Ext(BlueTransponderType_t(UInt32(transponderType.rawValue)), pStorage, dataPtr, dataSize, nil, nil)
        })
        
        result = try handler(pStorage)
        
        return successMessage
    })
    
    guard let result = result else {
        throw BlueError(.invalidState)
    }
    
    return result
}

public struct BlueOssSidFormatCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSidSettings.self, arg0),
            try blueCastArg(Bool.self, arg1) ?? false
        ))
    }
    
    public func run(_ settings: BlueOssSidSettings?, _ factoryReset: Bool = false) throws -> Void {
        return try executeOssSidNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessFormatMessage, handler: { pStorage in
            _ = try blueClibErrorCheck(blueOssSid_Format(pStorage, factoryReset))
        })
    }
}

public struct BlueOssSidGetStorageProfileCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueTransponderType.self, arg0),
            try blueCastArg(BlueOssSidProvisioningConfiguration.self, arg1)
        ))
    }
    
    public func run(_ transponderType: BlueTransponderType, _ provisioningConfig: BlueOssSidProvisioningConfiguration?) throws -> BlueOssSidStorageProfile {
        let pStorage = UnsafeMutablePointer<BlueOssSidStorage_t>.allocate(capacity: 1)
        
        defer {
            pStorage.deallocate()
        }
        
        _ = try blueClibErrorCheck(blueOssSid_GetStorage(BlueTransponderType_t(UInt32(transponderType.rawValue)), pStorage, nil, nil, nil))
        
        if let provisioningConfig = provisioningConfig {
            return try blueClibFunctionInOut(message: provisioningConfig, { (configDataPtr, configDataSize, dataPtr, dataSize) in
                return blueOssSid_GetStorageProfile_Ext(pStorage, configDataPtr, configDataSize, dataPtr, dataSize)
            })
        } else {
            return try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSid_GetStorageProfile_Ext(pStorage, nil, 0, dataPtr, dataSize)
            })
        }
    }
}

public struct BlueOssSidCreateProvisioningDataCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(String.self, arg0),
            try blueCastArg(BlueOssSidProvisioningConfiguration.self, arg1)
        ))
    }
    
    public func run(_ credentialId: String, _ configuration: BlueOssSidProvisioningConfiguration? = nil) throws -> BlueOssSidProvisioningData {
        var result = BlueOssSidProvisioningData()
        
        if let configuration = configuration {
            result.configuration = configuration
        }
        
        result.credentialType.typeSource = .oss
        result.credentialType.oss = BlueOssSidCredentialTypeOss()
        result.credentialID.id = credentialId
        
        return result
    }
}

public struct BlueOssSidIsProvisionedCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSidSettings.self, arg0)
        ))
    }
    
    public func run(_ settings: BlueOssSidSettings?) throws -> Bool {
        return try executeOssSidNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessIsProvisionedMessage, handler: { pStorage in
            return blueOssSid_IsProvisioned(pStorage) == BlueReturnCode_Ok
        })
    }
}

public struct BlueOssSidProvisionCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSidSettings.self, arg0),
            try blueCastArg(BlueOssSidProvisioningData.self, arg1)
        ))
    }
    
    public func run(_ settings: BlueOssSidSettings?, _ provisioningData: BlueOssSidProvisioningData) throws -> Void {
        return try executeOssSidNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessProvisionMessage, handler: { pStorage in
            return try blueClibFunctionIn(message: provisioningData, { (dataPtr, dataSize) in
                return blueOssSid_Provision_Ext(pStorage, dataPtr, dataSize)
            })
        })
    }
}

public struct BlueOssSidUnprovisionCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSidSettings.self, arg0)
        ))
    }
    
    public func run(_ settings: BlueOssSidSettings?) throws -> Void {
        return try executeOssSidNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessUnprovisionMessage, handler: { pStorage in
            _ = try blueClibErrorCheck(blueOssSid_Unprovision(pStorage))
        })
    }
}

public struct BlueOssSidReadConfigurationCommand: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        return try blueCastResult(try run(
            try blueCastArg(BlueOssSidSettings.self, arg0)
        ))
    }
    
    public func run(_ settings: BlueOssSidSettings?) throws -> BlueOssSidConfiguration {
        return try executeOssSidNfc(settings: settings, successMessage: blueI18n.nfcOssSuccessReadConfigurationMessage, handler: { pStorage in
            return try blueClibFunctionOut({ (dataPtr, dataSize) in
                return blueOssSid_ReadConfiguration_Ext(pStorage, dataPtr, dataSize)
            })
        })
    }
}

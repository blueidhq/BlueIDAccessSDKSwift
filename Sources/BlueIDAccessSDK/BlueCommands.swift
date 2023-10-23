import Foundation
import SwiftProtobuf

internal protocol BlueCommand {
    func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any?
}

public struct BlueCommands {
    public let initialize = BlueInitializeCommand()
    public let release = BlueReleaseCommand()
    
    public let test = BlueTestCommand()
    public let versionInfo = BlueVersionInfoCommand()
    
    public let bluetoothActivate = BlueBluetoothActivate()
    public let bluetoothDeactivate = BlueBluetoothDeactivate()
    
#if os(iOS) || os(watchOS)
    public let nearByActivate = BlueNearByActivate()
    public let nearByDeactivate = BlueNearByDeactivate()
#endif
    
    public let ossSoCreateMobile = BlueOssSoCreateMobileCommand()
    public let ossSoFormat = BlueOssSoFormatCommand()
    public let ossSoGetStorageProfile = BlueOssSoGetStorageProfileCommand()
    public let ossSoCreateStandardProvisioningData = BlueOssSoCreateStandardProvisioningDataCommand()
    public let ossSoCreateInterventionProvisioningData = BlueOssSoCreateInterventionProvisioningDataCommand()
    public let ossSoIsProvisioned = BlueOssSoIsProvisionedCommand()
    public let ossSoProvision = BlueOssSoProvisionCommand()
    public let ossSoUnprovision = BlueOssSoUnprovisionCommand()
    public let ossSoReadConfiguration = BlueOssSoReadConfigurationCommand()
    public let ossSoUpdateConfiguration = BlueOssSoUpdateConfigurationCommand()
    
    public let ossSidCreateMobile = BlueOssSidCreateMobileCommand()
    public let ossSidFormat = BlueOssSidFormatCommand()
    public let ossSidGetStorageProfile = BlueOssSidGetStorageProfileCommand()
    public let ossSidCreateProvisioningData = BlueOssSidCreateProvisioningDataCommand()
    public let ossSidIsProvisioned = BlueOssSidIsProvisionedCommand()
    public let ossSidProvision = BlueOssSidProvisionCommand()
    public let ossSidUnprovision = BlueOssSidUnprovisionCommand()
    public let ossSidReadConfiguration = BlueOssSidReadConfigurationCommand()
    
    fileprivate init() {}
}

public let blueCommands = BlueCommands()

//
// Plugin interface
//

private var blueCommandsMap: [String: BlueCommand] = [:]

internal struct BlueCommandResult {
    public let data: Any?
    public let messageTypeName: String?
    
    internal init(data: Any? = nil, messageTypeName: String? = nil) {
        self.data = data
        self.messageTypeName = messageTypeName
    }
}

internal func blueRunCommand(_ command: String, arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil, completion: @escaping (Result<BlueCommandResult, Error>) -> Void) {
    if (command != "initialize" && command != "release") {
        if (!blueIsInitialized) {
            return completion(.failure(BlueError(.unavailable)))
        }
    }
    
    // Fill the map initially if first time call
    if (blueCommandsMap.isEmpty) {
        let mirror = Mirror(reflecting: blueCommands)
        for case let (commandName?, value) in mirror.children {
            if let value = value as? BlueCommand {
                blueCommandsMap[commandName] = value
            }
        }
    }
    
    do {
        guard let commandInstance = blueCommandsMap[command] else {
            throw BlueError(.notFound)
        }
        
        let result = try commandInstance.run(arg0: arg0, arg1: arg1, arg2: arg2)
        
        var data: Any? = result
        var messageTypeName: String? = nil
        
        if let result = result as? Message {
            messageTypeName = String(describing: Mirror(reflecting: result).subjectType)
            data = try blueEncodeMessage(result)
        }
        
        completion(.success(BlueCommandResult(data: data, messageTypeName: messageTypeName)))
    } catch {
        completion(.failure(error))
    }
}

internal func blueRunCommand(_ command: String, arg0: Any? = nil, arg1: Data? = nil, arg2: Data? = nil) async throws -> BlueCommandResult {
    return try await withCheckedThrowingContinuation { continuation in
        blueRunCommand(command, arg0: arg0, arg1: arg1, arg2: arg2) { result in
            continuation.resume(with: result)
        }
    }
}

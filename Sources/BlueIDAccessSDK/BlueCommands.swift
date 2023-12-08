import Foundation
import SwiftProtobuf

protocol Command {}

internal protocol BlueCommand: Command {
    func run(arg0: Any?, arg1: Any?, arg2: Any?) throws -> Any?
}

protocol BlueAsyncCommand: Command {
    func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any?
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
    
    public let addAccessCredential = BlueAddAccessCredentialCommand()
    public let getAccessCredentials = BlueGetAccessCredentialsCommand()
    public let synchronizeMobileAccess = BlueSynchronizeMobileAccessCommand()
    public let getAccessDevices = BlueGetAccessDevicesCommand()
    public let updateDeviceConfiguration = BlueUpdateDeviceConfigurationCommand()
    
    fileprivate init() {}
}

public let blueCommands = BlueCommands()

//
// Plugin interface
//

private var blueCommandsMap: [String: Command] = [:]

internal struct BlueCommandResult {
    public let data: Any?
    public let messageTypeName: String?
    
    fileprivate init(data: Any? = nil, messageTypeName: String? = nil) {
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
            if let value = value as? Command {
                blueCommandsMap[commandName] = value
            }
        }
    }
    
    do {
        guard let commandInstance = blueCommandsMap[command] else {
            throw BlueError(.notFound)
        }
        
        let handleCommandResult: (Any?) -> Void = { result in
            do {
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
        
        if let asyncBlueCommandInstance = commandInstance as? BlueAsyncCommand {
            blueRunAsyncCommand(command: asyncBlueCommandInstance, arg0: arg0, arg1: arg1, arg2: arg2) { result in
                switch(result) {
                case .success(let commandResult):
                    handleCommandResult(commandResult)
                    break
                case .failure(let error):
                    completion(.failure(error))
                    break
                }
            }
        } else if let blueCommandInstance = commandInstance as? BlueCommand {
            let result = try blueCommandInstance.run(arg0: arg0, arg1: arg1, arg2: arg2)
            
            handleCommandResult(result)
        } else {
            throw BlueError(.notSupported)
        }
    } catch {
        completion(.failure(error))
    }
}

internal func blueRunAsyncCommand(command: BlueAsyncCommand, arg0: Any?, arg1: Any?, arg2: Any?, completion: @escaping (Result<Any?, Error>) -> Void) {
    if #available(macOS 10.15, *) {
        DispatchQueue.global().async {
            Task {
                do {
                    let result = try await command.runAsync(arg0: arg0, arg1: arg1, arg2: arg2)
                    
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
            
        }
    } else {
        completion(.failure(BlueError(.unavailable)))
    }
}

@available(macOS 10.15, *)
internal func blueRunCommand(_ command: String, arg0: Any? = nil, arg1: Data? = nil, arg2: Data? = nil) async throws -> BlueCommandResult {
    return try await withCheckedThrowingContinuation { continuation in
        blueRunCommand(command, arg0: arg0, arg1: arg1, arg2: arg2) { result in
            continuation.resume(with: result)
        }
    }
}

//
// Objective-C interface
//

@objc(BlueCommandResult)
public final class ObjC_BlueCommandResult: NSObject {
    @objc public let error: Error?
    @objc public let data: AnyObject?
    @objc public let messageTypeName: String?
    
    fileprivate init(error: Error? = nil, data: AnyObject? = nil, messageTypeName: String? = nil) {
        self.error = error
        self.data = data
        self.messageTypeName = messageTypeName
    }
}

@objc(BlueCommands)
public final class ObjC_BlueCommands: NSObject {
    private override init() {}
    
    @objc public static func run(_ command: String, arg0: AnyObject?, arg1: AnyObject?, arg2: AnyObject?, completion: ( (ObjC_BlueCommandResult) -> Void)?) -> Void {
        blueRunCommand(command, arg0: arg0, arg1: arg1, arg2: arg2) { result in
            guard let completion = completion else {
                return
            }
            
            switch result {
            case .success(let commandResult):
                var objcData: AnyObject? = nil
                if let data = commandResult.data as? Data {
                    objcData = NSData(data: data)
                } else if let data = commandResult.data as? AnyObject {
                    objcData = data
                }
                completion(ObjC_BlueCommandResult(error: nil, data: objcData, messageTypeName: commandResult.messageTypeName))
            case .failure(let error):
                completion(ObjC_BlueCommandResult(error: error))
            }
        }
    }
    
    @objc public static func run(_ command: String, arg0: AnyObject, arg1: AnyObject, completion: ( (ObjC_BlueCommandResult) -> Void)?) -> Void {
        run(command, arg0: arg0, arg1: arg1, arg2: nil, completion: completion)
    }
    
    @objc public static func run(_ command: String, arg0: AnyObject, completion: ( (ObjC_BlueCommandResult) -> Void)?) -> Void {
        run(command, arg0: arg0, arg1: nil, arg2: nil, completion: completion)
    }
    
    @objc public static func run(_ command: String, completion: ( (ObjC_BlueCommandResult) -> Void)?) -> Void {
        run(command, arg0: nil, arg1: nil, arg2: nil, completion: completion)
    }
}

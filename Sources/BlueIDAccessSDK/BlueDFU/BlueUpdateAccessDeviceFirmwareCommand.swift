import CoreBluetooth
import Foundation
import NordicDFU

/**
 * @class BlueUpdateAccessDeviceFirmwareCommand
 * A SDK command for updating firmware of nRF51 and nRF52 devices over Bluetooth LE.
 */
public class BlueUpdateAccessDeviceFirmwareCommand: BlueSdkAsyncCommand {
    override func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        return try await runAsync(
            credentialID: blueCastArg(String.self, arg0),
            deviceID: blueCastArg(String.self, arg1)
        )
    }
    
    public func runAsync(credentialID: String, deviceID: String) async throws {
        guard let credential = blueGetAccessCredential(credentialID: credentialID) else {
            throw BlueError(.sdkCredentialNotFound)
        }
        
        guard blueGetDevice(deviceID) != nil else {
            throw BlueError(.sdkDeviceNotFound)
        }
        
        try await BlueUpdateAccessDeviceFirmware(sdkService)
            .update(credential, deviceID)
    }
}

internal class BlueUpdateAccessDeviceFirmware: LoggerDelegate, DFUServiceDelegate, DFUProgressDelegate {
    public enum BlueUpdateAccessDeviceFirmwareTaskId {
        case getAuthenticationToken
        case checkLatestFirmware
        case downloadLatestFirmware
        case prepareUpdate
        case startBootloader
        case findDFUPeripheral
        case updateFirmware
        case waitRestart
    }
    
    private let sdkService: BlueSdkService
    
    private var semaphore: DispatchSemaphore?
    private var controller: DFUServiceController?
    private var task: BlueTask?
    private var error: BlueError? = nil
    
    init(_ sdkService: BlueSdkService) {
        self.sdkService = sdkService
    }
    
    public func update(_ credential: BlueAccessCredential, _ deviceID: String) async throws {
        
        let tasks = [
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.getAuthenticationToken,
                label: blueI18n.dfuGetAuthenticationTokenTaskLabel
            ) { _, _ in
                .result(try await self.sdkService.authenticationTokenService.getTokenAuthentication(credential: credential))
            },
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.checkLatestFirmware,
                label: blueI18n.dfuCheckLatestFwlabel
            ) { _, runner in
                let tokenAuthentication: BlueTokenAuthentication = try runner.getResult(BlueUpdateAccessDeviceFirmwareTaskId.getAuthenticationToken)
                
                return .result(try await self.sdkService.apiService.getLatestFirmware(deviceID: deviceID, with: tokenAuthentication).getData())
            },
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.downloadLatestFirmware,
                label: blueI18n.dfuDownloadLatestFwlabel
            ) { _, runner in
                let latestFW: BlueGetLatestFirmwareResult = try runner.getResult(BlueUpdateAccessDeviceFirmwareTaskId.checkLatestFirmware)
                
                return .result(try await self.downloadLatestFirmware(url: latestFW.url))
            },
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.prepareUpdate,
                label: blueI18n.dfuPrepareUpdateLabel
            ) { _, runner in
                let zip: Data = try runner.getResult(BlueUpdateAccessDeviceFirmwareTaskId.downloadLatestFirmware)
                
                return .result(try self.prepareUpdate(zip))
            },
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.startBootloader,
                label: blueI18n.dfuStartBootloaderLabel
            ) { _, _ in
                return .result(try await self.startBootloader(deviceID))
            },
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.findDFUPeripheral,
                label: blueI18n.dfuFindDfuperipheralLabel
            ) { _, _ in
                return .result(try await self.findPeripheral())
            },
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.updateFirmware,
                label: blueI18n.dfuUpdateFwlabel,
                progress: 0,
                cancelHandler: {
                    _ = self.controller?.abort()
                },
                handler: { task, runner in
                    let urlToZipFile: URL = try runner.getResult(BlueUpdateAccessDeviceFirmwareTaskId.prepareUpdate)
                    let peripheral: CBPeripheral = try runner.getResult(BlueUpdateAccessDeviceFirmwareTaskId.findDFUPeripheral)
                    
                    self.task = task
                    
                    return .result(try self.update(peripheral, urlToZipFile))
                }
            ),
            
            BlueTask(
                id: BlueUpdateAccessDeviceFirmwareTaskId.waitRestart,
                label: blueI18n.dfuWaitForDeviceToRestartTaskLabel
            ) { _, _ in
                return .result(try await waitForDeviceAvailability(deviceID, timeout: 5, maxRetries: 6))
            }
        ]
        
        let runner = BlueSerialTaskRunner(tasks)
        
#if os(iOS) || os(watchOS)
        try await blueShowUpdateAccessDeviceFirmwareModal(runner)
#else
        try await runner.execute(true)
#endif
    }
    
    private func downloadLatestFirmware(url string: String) async throws -> Data {
        guard let url = URL(string: string) else {
            throw BlueError(.sdkInvalidFirmwareURL)
        }
        
        return try await BlueFetch.get(url: url).getData()
    }
    
    private func prepareUpdate(_ zip: Data) throws -> URL {
        let extractedURL = try BlueZip.extract(data: zip)
        
        return extractedURL.appendingPathComponent("dfu_application.zip")
    }
    
    private func startBootloader(_ deviceID: String) async throws {
        try await blueTerminalRun(deviceID: deviceID, action: "BOOTLD")
    }
    
    private func findPeripheral() async throws -> CBPeripheral {
        let service = BlueDFUPeripheralService()
        
        defer {
            service.destroy()
        }
        
        return try await service.find()
    }
    
    private func update(_ peripheral: CBPeripheral, _ urlToZipFile: URL) throws {
        self.semaphore = DispatchSemaphore(value: 0)
        
        let firmware = try DFUFirmware(urlToZipFile: urlToZipFile)
        
        let initiator = DFUServiceInitiator()
        initiator.logger = self
        initiator.delegate = self
        initiator.progressDelegate = self

        self.controller = initiator
            .with(firmware: firmware)
            .start(targetWithIdentifier: peripheral.identifier)
        
        self.semaphore?.wait()
        
        if let error = error {
            throw error
        }
    }
    
    // MARK: - LoggerDelegate API
    
    public func logWith(_ level: NordicDFU.LogLevel, message: String) {
        switch (level) {
            case .debug, .application, .verbose:
                blueLogDebug(message)
                break
            case .info:
                blueLogInfo(message)
                break
            case .warning:
                blueLogWarn(message)
                break
            case .error:
                blueLogError(message)
                break
        }
    }
    
    // MARK: - DFUServiceDelegate API
    
    public func dfuStateDidChange(to state: NordicDFU.DFUState) {        
        if state == .completed || state == .aborted {
            semaphore?.signal()
        }
    }
    
    public func dfuError(_ error: NordicDFU.DFUError, didOccurWithMessage message: String) {
        self.error = BlueError(.error, detail: message)
        
        semaphore?.signal()
    }
    
    // MARK: - DFUProgressDelegate API
    
    public func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        self.task?.updateProgress(Float(progress))
    }
}

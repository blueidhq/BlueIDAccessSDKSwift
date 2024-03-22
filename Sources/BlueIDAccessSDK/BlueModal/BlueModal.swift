#if os(iOS) || os(watchOS)
import Foundation

/// Displays a modal view (sheet) which performs a scoped task related to accessing a device via OSS.
/// - parameter task: The OSS task to be performed.
public func blueShowAccessDeviceModal(_ task: @escaping () async throws -> BlueOssAccessResult) async throws -> BlueOssAccessResult {
    let session = BlueAccessDeviceModalSession()

    blueRunInMainThread {
        session.begin(title: blueI18n.openViaOssTitle, message: blueI18n.openViaOssWaitMessage)
    }
    
    do {
        let result = try await task()
        
        blueRunInMainThread {
            if (!result.accessGranted) {
                if (result.hasScheduleMissmatch && result.scheduleMissmatch) {
                    session.invalidate(
                        title: blueI18n.openViaOssAccessDeniedTitle,
                        errorMessage: blueI18n.openViaOssAccessDeniedScheduleMismatchMessage
                    )
                }
                else {
                    session.invalidate(
                        title: blueI18n.openViaOssAccessDeniedTitle,
                        errorMessage: blueI18n.openViaOssAccessDeniedMessage
                    )
                }
            } else {
                session.invalidate(
                    title: blueI18n.openViaOssAccessGrantedTitle,
                    successMessage: blueI18n.openViaOssAccessGrantedMessage
                )
            }
        }
        
        return result
    } catch {
        var errorMessage = error.localizedDescription
        
        if let blueError = error as? BlueError {
            errorMessage = "Error: \(String(describing: blueError.returnCode)). Code: \(blueError.returnCode.rawValue)"
        }
        else if let terminalError = error as? BlueTerminalError {
            errorMessage = "Error: \(String(describing: terminalError.terminalError.returnCode)). Code: \(terminalError.terminalError.returnCode.rawValue)"
        }
        
        blueRunInMainThread {
            session.invalidate(
                title: blueI18n.openViaOssErrorTitle,
                errorMessage: errorMessage
            )
        }
        
        throw error
    }
}

/// Displays a modal view (sheet) which performs tasks related to synchronizing a device.
/// - parameter runner: The Task Runner.
public func blueShowSynchronizeAccessDeviceModal(_ runner: BlueTaskRunner) async throws {
    try await blueShowStepProgressModal(
        title: blueI18n.syncDeviceInProgressTitle,
        failedTitle: blueI18n.syncDeviceFailedTitle,
        completedTitle: blueI18n.syncDeviceCompletedTitle,
        runner: runner
    )
}

/// Displays a modal view (sheet) which performs tasks related to updating a device firmware.
/// - parameter runner: The Task Runner.
public func blueShowUpdateAccessDeviceFirmwareModal(_ runner: BlueTaskRunner) async throws {
    try await blueShowStepProgressModal(
        title: blueI18n.dfuInProgressTitle,
        failedTitle: blueI18n.dfuFailedTitle,
        completedTitle: blueI18n.dfuCompletedTitle,
        runner: runner
    )
}

private func blueShowStepProgressModal(
    title: String,
    failedTitle: String,
    completedTitle: String,
    runner: BlueTaskRunner
) async throws {
    let session = BlueStepProgressModalSession()

    blueRunInMainThread {
        session.begin(
            title: title,
            tasks: runner.getTasks(),
            dismiss: blueI18n.cmnCancelLabel
        ) {
            if runner.cancel() {
                session.disableDismiss()
                session.updateTitle(blueI18n.syncDeviceCancellingTitle)
            } else {
                session.invalidate()
            }
        }
    }
    
    do {
        try await runner.execute(false)
        
        blueRunInMainThread {
            if runner.isCancelled() {
                session.invalidate()
            } else {
                session.updateDismiss(blueI18n.cmnCloseLabel)
                
                if runner.isFailed() {
                    session.updateTitle(failedTitle)
                    BlueSound.shared.play(BlueNegativeSoundSystemID)
                } else {
                    session.updateTitle(completedTitle)
                    BlueSound.shared.play(BluePositiveSoundSystemID)
                }
            }
        }
    } catch {
        blueRunInMainThread {
            session.updateTitle(failedTitle)
            session.updateDismiss(blueI18n.cmnCloseLabel)
            BlueSound.shared.play(BlueNegativeSoundSystemID)
        }
        
        throw error
    }
}
#endif

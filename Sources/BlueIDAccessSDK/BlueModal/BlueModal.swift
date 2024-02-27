#if os(iOS) || os(watchOS)
import Foundation

/// Displays a modal view (sheet) which performs a scoped task related to accessing an device via OSS.
/// - parameter task: The OSS task to be performed.
public func blueShowAccessDeviceModal(_ task: @escaping () async throws -> BlueOssAccessResult) async throws -> BlueOssAccessResult {
    let session = BlueModalSession()

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
#endif

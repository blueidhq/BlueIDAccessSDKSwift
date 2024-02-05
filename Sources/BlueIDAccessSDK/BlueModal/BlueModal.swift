#if os(iOS) || os(watchOS)
import Foundation

/// Displays a modal view (sheet) which performs a scoped task related to accessing an device via OSS.
/// - parameter title: The  modal title.
/// - parameter message: The modal message.
/// - parameter successfulMessage: A successful message to be shown in case the OSS task grants access successfully.
/// - parameter unsuccessfulMessage: An unsuccessful message to be shown in case the OSS task does not grant access successfully.
/// - parameter task: The OSS task to be performed.
public func blueShowAccessDeviceModal(
    title: String,
    message: String? = nil,
    successfulMessage: String? = nil,
    unsuccessfulMessage: String? = nil,
    _ task: @escaping () async throws -> BlueOssAccessResult)
async throws -> BlueOssAccessResult {
    let session = BlueModalSession()

    blueRunInMainThread {
        session.begin(title: title, message: message)
    }
    
    do {
        let result = try await task()
        
        if (!result.accessGranted) {
            blueRunInMainThread {
                session.invalidate(errorMessage: unsuccessfulMessage ?? "")
            }
        } else {
            blueRunInMainThread {
                session.invalidate(successMessage: successfulMessage ?? "")
            }
        }
        
        return result
    } catch {
        blueRunInMainThread {
            session.invalidate(errorMessage: error.localizedDescription)
        }
        
        throw error
    }
}
#endif

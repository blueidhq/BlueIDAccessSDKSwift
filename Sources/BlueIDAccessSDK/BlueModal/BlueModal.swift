#if os(iOS) || os(watchOS)
import Foundation

/// Displays a modal view (sheet) which performs a scoped task that’s closely related to the current context.
/// - parameter title: The  modal title.
/// - parameter message: The modal message.
/// - parameter successMessage: A success message to be shown in case the task is finished successfully.
/// - parameter task: The task to be performed .
public func blueShowModal<T>(
    title: String,
    message: String? = nil,
    successMessage: String? = nil,
    _ task: @escaping () async throws -> T)
async throws -> T {
    let session = BlueModalSession()

    blueRunInMainThread {
        session.begin(title: title, message: message)
    }
    
    do {
        let result = try await task()
        
        blueRunInMainThread {
            session.invalidate(successMessage: successMessage ?? "")
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

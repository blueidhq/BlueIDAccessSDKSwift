import Foundation
import SwiftUI

public struct BlueOpenAppSettingsCommand: BlueAsyncCommand {
    func runAsync(arg0: Any?, arg1: Any?, arg2: Any?) async throws -> Any? {
        if #available(macOS 10.15, *) {
            return try await withCheckedThrowingContinuation { continuation in
                run() { result in
                    continuation.resume(with: .success(result))
                }
            }
        }
        
        return false
    }
    
    public func run(completionHandler: @escaping (Bool) -> Void) {
        #if os(iOS) || os(watchOS)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(settingsUrl) {
                blueRunInMainThread {
                    UIApplication.shared.open(settingsUrl, completionHandler: completionHandler)
                }
                return
            }
        }
        #else
        if let securityPrivacyUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            blueRunInMainThread {
                completionHandler(NSWorkspace.shared.open(securityPrivacyUrl))
            }
            return
        }
        #endif
        
        completionHandler(false)
    }
}

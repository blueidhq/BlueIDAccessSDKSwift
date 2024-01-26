#if os(iOS) || os(watchOS)
import AVFoundation
import SwiftUI

/**
 * @class BlueModalSession
 *
 * Modal session for processing BlueModal.
 * BlueModal (sheet) helps people perform a scoped task that’s closely related to their current context.
 */
internal class BlueModalSession {
    private var viewModel = BlueModalViewModel()
    private var controller: UIHostingController<BlueModalView>? = nil
    private var isInvalidated: Bool = false
    
    /// Starts the modal session.
    /// - parameter title: The initial title.
    /// - parameter message: The initial message.
    func begin(title: String? = nil, message: String? = nil) {
        viewModel.title = title ?? ""
        viewModel.message = message ?? ""
        
        let hostingController = UIHostingController(
            rootView: BlueModalView(viewModel) {
                self.invalidate()
            }
        )
        
        hostingController.view.backgroundColor = .clear
        hostingController.modalPresentationStyle = .overCurrentContext
        
        blueGetKeyWindow()?.rootViewController?.present(hostingController, animated: true)
    }
    
    /// Closes the modal session.  The session cannot be re-used.
    /// - parameter errorMessage: The specified error message and an error symbol will be displayed momentarily on the modal before it is automatically dismissed.
    /// - parameter successMessage: The specified success message and an success symbol will be displayed momentarily on the modal before it is automatically dismissed.
    func invalidate(errorMessage: String? = nil, successMessage: String? = nil) {
        if (isInvalidated)  {
            return
        }
        
        isInvalidated = true
        
        var delay: TimeInterval? = nil
        
        viewModel.showDismissButton = false
        
        if let errorMessage = errorMessage {
            viewModel.title = ""
            viewModel.message = errorMessage
            viewModel.status = .Failed
            delay = 2
            
            BlueSound.shared.play(BlueNegativeSoundSystemID)
        }
        
        if let successMessage = successMessage {
            viewModel.title = ""
            viewModel.message = successMessage
            viewModel.status = .Success
            delay = 2
            
            BlueSound.shared.play(BluePositiveSoundSystemID)
        }
        
        dismiss(delay)
    }
    
    private func dismiss(_ delay: TimeInterval? = nil) {
        if let delay = delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.blueGetKeyWindow()?.rootViewController?.dismiss(animated: true)
            }
        } else {
            blueGetKeyWindow()?.rootViewController?.dismiss(animated: true)
        }
    }
    
    private func blueGetKeyWindow() -> UIWindow? {
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    }
}
#endif

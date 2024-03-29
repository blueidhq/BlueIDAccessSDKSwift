#if os(iOS) || os(watchOS)
import AVFoundation
import SwiftUI

private class HostingController: UIHostingController<BlueAccessDeviceModalView> {
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
}

/**
 * @class BlueAccessDeviceModalSession
 *
 * Modal session for processing BlueModal.
 * BlueModal (sheet) helps people perform a scoped task that’s closely related to their current context.
 */
internal class BlueAccessDeviceModalSession {
    private var viewModel = BlueAccessDeviceModalViewModel()
    private var isInvalidated: Bool = false
    
    /// Starts the modal session.
    /// - parameter title: The initial title.
    /// - parameter message: The initial message.
    func begin(title: String? = nil, message: String? = nil) {
        viewModel.title = title ?? ""
        viewModel.message = message ?? ""
        
        let hostingController = HostingController(
            rootView: BlueAccessDeviceModalView(viewModel) { self.invalidate() }
        )
        
        hostingController.view.backgroundColor = .clear
        hostingController.modalPresentationStyle = .overCurrentContext
        
        blueGetKeyWindow()?.rootViewController?.present(hostingController, animated: true)
    }
    
    /// Closes the modal session.  The session cannot be re-used.
    /// - parameter title: Optional title.
    /// - parameter errorMessage: The specified error message and an error symbol will be displayed momentarily on the modal before it is automatically dismissed.
    /// - parameter successMessage: The specified success message and an success symbol will be displayed momentarily on the modal before it is automatically dismissed.
    func invalidate(
        title: String? = nil,
        errorMessage: String? = nil,
        successMessage: String? = nil
    ) {
        if (isInvalidated)  {
            return
        }
        
        isInvalidated = true
        
        var delay: TimeInterval? = nil
        
        viewModel.showDismissButton = false
        
        if let errorMessage = errorMessage {
            viewModel.title = title ?? ""
            viewModel.message = errorMessage
            viewModel.status = .Failed
            delay = 3
            
            BlueSound.shared.play(BlueNegativeSoundSystemID)
        }
        
        if let successMessage = successMessage {
            viewModel.title = title ?? ""
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

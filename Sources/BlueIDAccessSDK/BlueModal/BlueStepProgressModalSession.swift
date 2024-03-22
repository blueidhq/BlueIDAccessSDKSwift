#if os(iOS) || os(watchOS)
import AVFoundation
import SwiftUI

private class HostingController: UIHostingController<BlueStepProgressModalView> {
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
}

internal class BlueStepProgressModalSession {
    private let viewModel = BlueStepProgressModalViewModel()
    private var isInvalidated: Bool = false
    
    func begin(title: String, tasks: [BlueTask], dismiss: String, _ onDismiss: @escaping () -> Void) {
        viewModel.title = title
        viewModel.tasks = tasks
        viewModel.dismiss = dismiss
        
        let hostingController = HostingController(
            rootView: BlueStepProgressModalView(viewModel) { onDismiss() }
        )
        
        hostingController.view.backgroundColor = .clear
        hostingController.modalPresentationStyle = .overCurrentContext
        
        blueGetKeyWindow()?.rootViewController?.present(hostingController, animated: true)
    }
    
    func updateTitle(_ title: String) {
        viewModel.title = title
    }
    
    func updateDismiss(_ label: String) {
        viewModel.dismiss = label
    }
    
    func disableDismiss() {
        viewModel.dismissEnabled = false
    }
    
    func invalidate() {
        if (isInvalidated)  {
            return
        }
        
        isInvalidated = true
        
        blueGetKeyWindow()?.rootViewController?.dismiss(animated: true)
    }
    
    private func blueGetKeyWindow() -> UIWindow? {
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    }
}
#endif

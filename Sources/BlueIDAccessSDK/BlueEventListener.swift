import Foundation
import SwiftProtobuf

private var blueEventListeners: [(BlueEventType?, any BlueEventListener)] = []

public enum BlueEventType: String, CaseIterable {
    // data = BlueDeviceInfo
    case deviceAdded
    // data = BlueDeviceInfo
    case deviceUpdated
    // data = BlueDeviceInfo
    case deviceRemoved
    // data = BlueDeviceInfo
    case deviceNearByDetected
    // data = BlueDeviceInfo
    case deviceNearByLost
    // data = BlueTerminalResult
    case terminalResult
    // data = nil
    case accessCredentialAdded
    // data = nil
    case accessDeviceClaimed
    // data = nil
    case tokenSyncStarted
    // data = nil
    case tokenSyncFinished
    // data = Bool
    case bluetoothStateChanged
}

public protocol BlueEventListener: AnyObject {
    func blueEvent(event: BlueEventType, data: Any?)
}

public func blueAddEventListener(event: BlueEventType? = nil, listener: any BlueEventListener) {
    blueEventListeners.append((event, listener))
}

public func blueRemoveEventListener(listener: any BlueEventListener) {
    blueEventListeners = blueEventListeners.filter({ $0.1 !== listener})
}

internal func blueFireListeners(fireEvent: BlueEventType, data: Any?) {
    let handler: () -> Void = {
        for (event, listener) in blueEventListeners {
            if let event = event {
                if event == fireEvent {
                    listener.blueEvent(event: fireEvent, data: data)
                }
            } else {
                listener.blueEvent(event: fireEvent, data: data)
            }
        }
    }
    
    if Thread.isMainThread {
        handler()
    } else {
        DispatchQueue.main.async {
            handler()
        }
    }
}

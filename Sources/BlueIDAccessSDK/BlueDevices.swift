import Foundation

internal var maxDeviceAgeSeconds = 10.0

private var blueDevices: [BlueDevice] = []
private var bluePurgeDevicesTimer: Timer? = nil
private var blueDeviceScannersCount = 0

internal func blueSetMaxDeviceAgeSeconds(_ newMaxDeviceAgeSeconds: Double) {
    maxDeviceAgeSeconds = max(newMaxDeviceAgeSeconds, 1)
}

internal func blueGetDevice(_ deviceID: String) -> BlueDevice? {
    for device in blueDevices {
        if (device.info.deviceID == deviceID) {
            return device
        }
    }
    
    return nil
}

internal func blueAddDevice(_ device: BlueDevice) {
    if blueGetDevice(device.info.deviceID) == nil {
        blueDevices.append(device)
        blueNotifyAddeddDevice(device)
    }
}

internal func bluePurgeOldDevices() {
    let now = Date()
    
    var newDevices: [BlueDevice] = []
    
    for device in blueDevices {
        if (now.timeIntervalSince(device.lastSeenAt) >= maxDeviceAgeSeconds) {
            blueNotifyRemovedDevice(device)
        } else {
            newDevices.append(device)
        }
    }
    
    blueDevices = newDevices
}

internal func bluePurgeDevicesByType(_ deviceType: BlueDeviceType) {
    var newDevices: [BlueDevice] = []
    
    for device in blueDevices {
        if (device.info.deviceType == deviceType) {
            blueNotifyRemovedDevice(device)
        } else {
            newDevices.append(device)
        }
    }
    
    blueDevices = newDevices
}

internal func blueAddDeviceScanner() {
    blueDeviceScannersCount += 1
    
    if (blueDeviceScannersCount == 1) {
        // Init our purge timer
        bluePurgeDevicesTimer = Timer.scheduledTimer(withTimeInterval: maxDeviceAgeSeconds, repeats: true) { _ in
            bluePurgeOldDevices()
        }
    }
}

internal func blueClearDeviceScanner() {
    blueDeviceScannersCount -= 1
    
    if (blueDeviceScannersCount == 0) {
        // Stop our purge timer
        bluePurgeDevicesTimer?.invalidate()
        bluePurgeDevicesTimer = nil
    }
}

internal func blueNotifyAddeddDevice(_ device: BlueDevice) {
    blueFireListeners(fireEvent: BlueEventType.deviceAdded, data: device.info)
}

internal func blueNotifyUpdatedDevice(_ device: BlueDevice) {
    blueFireListeners(fireEvent: BlueEventType.deviceUpdated, data: device.info)
}

internal func blueNotifyRemovedDevice(_ device: BlueDevice) {
    blueFireListeners(fireEvent: BlueEventType.deviceRemoved, data: device.info)
}

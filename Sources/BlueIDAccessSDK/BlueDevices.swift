import Foundation

internal var maxDeviceAgeSeconds = 10.0

private var blueDevices: [BlueDevice] = []
private var bluePurgeDevicesTimer: Timer? = nil
private var blueDeviceScannersCount = 0

internal func blueSetMaxDeviceAgeSeconds(_ newMaxDeviceAgeSeconds: Double) {
    maxDeviceAgeSeconds = max(newMaxDeviceAgeSeconds, 1)
}

/// Waits asynchronously for a device with the specified ID to become available.
/// This function waits for a device with the given ID to be discovered within a predefined timeout period, with a maximum number of retries.
/// - parameters:
///   - deviceID: The ID of the device to wait for.
///   - timeout: The duration in seconds to wait for the device to be discovered each time. Default value is 10 seconds.
///   - maxRetries: The maximum number of retries before giving up. Default value is 3.
/// - throws: An error of type `BlueError` if the device is not found within the specified timeout period and maximum retries.

internal func waitForDeviceAvailability(_ deviceID: String, timeout: Int = 10, maxRetries: Int = 3) async throws {
    var attempts = 0
    
    while attempts < maxRetries {
        try? await Task.sleep(nanoseconds: UInt64(blueSecondsToNanoseconds(timeout)))
        
        if blueGetDevice(deviceID) != nil {
            return
        }
        
        attempts += 1
    }
    
    throw BlueError(.sdkDeviceNotFound)
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
        let shouldPurge = now.timeIntervalSince(device.lastSeenAt) >= maxDeviceAgeSeconds && !isActiveDevice(device)
        if (shouldPurge) {
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
        blueRunInMainThread {
            // Init our purge timer
            bluePurgeDevicesTimer = Timer.scheduledTimer(withTimeInterval: maxDeviceAgeSeconds, repeats: true) { _ in
                bluePurgeOldDevices()
            }
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

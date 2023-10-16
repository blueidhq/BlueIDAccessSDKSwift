#if os(iOS) || os(watchOS)
import Foundation
import SwiftUI
import CBlueIDAccess
import CoreLocation

private let blueIBeaconUUID = UUID(uuidString: BLUE_BLE_BEACON_UUID)!
private let blueBeaconRegion = CLBeaconRegion(uuid: blueIBeaconUUID, identifier: blueIBeaconUUID.uuidString)

private var blueNearByIsActive = false
private var blueMinDistanceMeters = 0.50
private var blueClosestDeviceInfo: BlueDeviceInfo? = nil
private var blueLocationManager: CLLocationManager? = nil
private var blueLocationManagerListener: BlueLocationManagerListener? = nil

private final class BlueLocationManagerListener: NSObject, CLLocationManagerDelegate {
    //
    // Delegate method implementations for CLLocationManagerDelegate
    //
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        blueUpdateLocationMonitoring()
    }
    
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        manager.requestState(for: region)
    }
    
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if (state == .inside) {
            blueStartLocationRanging()
            blueLogDebug("Entered region, started ranging beacons")
        } else {
            blueStopLocationRanging()
            blueLogDebug("Left region, stopped ranging beacons")
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        // Try to find the closest beacon
        var closestBeacon: CLBeacon? = nil

        for beacon in beacons {
            if (beacon.accuracy < 0) {
                continue
            }
            
            if (beacon.accuracy > blueMinDistanceMeters) {
                continue
            }
            
            if (closestBeacon == nil || beacon.accuracy < closestBeacon!.accuracy) {
                closestBeacon = beacon
            }
        }
        
        if let closestBeacon = closestBeacon {
            let partialID = blueIBeaconMajorMinorToId(major: closestBeacon.major.int16Value, minor: closestBeacon.minor.int16Value)
            
            // Only fire if different to any previous one
            if blueClosestDeviceInfo == nil || !blueClosestDeviceInfo!.deviceID.starts(with: partialID) {
                blueClearClosestNearByDevice()
                
                blueClosestDeviceInfo = BlueDeviceInfo()
                blueClosestDeviceInfo!.deviceID = partialID
                blueClosestDeviceInfo!.distanceMeters = Float(closestBeacon.accuracy)
                blueClosestDeviceInfo!.deviceType = .bluetoothDevice
                blueClosestDeviceInfo!.bluetooth = BlueDeviceDetailsBluetooth()
                blueClosestDeviceInfo!.bluetooth.isIbeacon = true
                blueClosestDeviceInfo!.bluetooth.rssi = Int32(closestBeacon.rssi)
                
                blueFireListeners(fireEvent: .deviceNearByDetected, data: blueClosestDeviceInfo)
            }
        } else {
            blueClearClosestNearByDevice()
        }
    }
}

private func blueClearClosestNearByDevice() {
    if blueClosestDeviceInfo != nil {
        blueFireListeners(fireEvent: .deviceNearByLost, data: blueClosestDeviceInfo)
        blueClosestDeviceInfo = nil
    }
}

private func blueStartLocationRanging() {
    if let blueLocationManager = blueLocationManager {
        blueClearClosestNearByDevice()
        blueLocationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: blueBeaconRegion.uuid))
    }
}

private func blueStopLocationRanging() {
    if let blueLocationManager = blueLocationManager {
        blueLocationManager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: blueBeaconRegion.uuid))
        blueClearClosestNearByDevice()
    }
}

private func blueUpdateLocationMonitoring() {
    if let blueLocationManager = blueLocationManager {
        if (blueLocationManager.monitoredRegions.contains(blueBeaconRegion)) {
            blueStopLocationRanging()
            blueLocationManager.stopMonitoring(for: blueBeaconRegion)
        }
        
        if (blueNearByIsActive) {
            if (blueLocationManager.authorizationStatus == .authorizedAlways) {
                blueLocationManager.startMonitoring(for: blueBeaconRegion)
                blueClearClosestNearByDevice()
                blueLogDebug("Started region monitoring")
            }
        }
    }
}

public func blueLocation_didFinishLaunchingWithOptions(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    // Check if the app was launched due to a location event
    if launchOptions?[UIApplication.LaunchOptionsKey.location] is CLRegion {
        print("Started with region launch option")
        
        do {
            try blueCommands.nearByActivate.run()
            
            if let blueLocationManager = blueLocationManager {
                blueLocationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: blueBeaconRegion.uuid))
                blueLogDebug("Launched with region, started ranging beacons")
            }
        } catch {
            blueLogError(error.localizedDescription)
        }
    }
}

public struct BlueNearByActivate: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        try run()
        return nil
    }
    
    public func run() throws -> Void {
        guard !blueNearByIsActive else {
            throw BlueError(.invalidState)
        }
        
        if blueLocationManager == nil {
            blueLocationManagerListener = BlueLocationManagerListener()
            blueLocationManager = CLLocationManager()
            
            if let blueLocationManager = blueLocationManager {
                blueLocationManager.delegate = blueLocationManagerListener
                blueLocationManager.distanceFilter = kCLDistanceFilterNone
                blueLocationManager.desiredAccuracy = kCLLocationAccuracyBest
                blueLocationManager.allowsBackgroundLocationUpdates = true
                blueLocationManager.pausesLocationUpdatesAutomatically = true
            }
        }
        
        
        if let blueLocationManager = blueLocationManager {
            if (blueLocationManager.authorizationStatus != .authorizedAlways) {
                blueLocationManager.allowsBackgroundLocationUpdates = true
                blueLocationManager.requestAlwaysAuthorization()
                return
            }
            
            blueNearByIsActive = true
            
            blueUpdateLocationMonitoring()
        }
    }
}

public struct BlueNearByDeactivate: BlueCommand {
    internal func run(arg0: Any? = nil, arg1: Any? = nil, arg2: Any? = nil) throws -> Any? {
        try run()
        return nil
    }
    
    public func run() throws -> Void {
        guard blueNearByIsActive else {
            throw BlueError(.invalidState)
        }
        
        blueNearByIsActive = false
        
        blueUpdateLocationMonitoring()
    }
}

#endif

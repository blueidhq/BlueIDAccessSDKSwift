import Foundation
import SwiftUI

@objc
public final class BlueAppDelegate: NSObject {
    private override init() {}
    
    private static func didFinishLaunchingWithOptions(startedByRegion: Bool) {
        do {
            try blueCommands.initialize.run()
        } catch {
            fatalError(error.localizedDescription)
        }
        
#if os(iOS) || os(watchOS)
        if (startedByRegion) {
            blueNearbyAppLaunched()
        }
#endif
        
        BlueTokenSyncScheduler.shared.didFinishLaunching()
    }
    
#if os(iOS) || os(watchOS)
    public static func didFinishLaunchingWithOptions(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        let startedByRegion = launchOptions?[UIApplication.LaunchOptionsKey.location] != nil
        didFinishLaunchingWithOptions(startedByRegion: startedByRegion)
    }
    
    @objc public static func didFinishLaunchingWithOptions(_ launchOptions: NSDictionary) {
        let startedByRegion = launchOptions.object(forKey: UIApplication.LaunchOptionsKey.location) != nil
        didFinishLaunchingWithOptions(startedByRegion: startedByRegion)
    }
#else
    @objc public static func didFinishLaunching() {
        didFinishLaunchingWithOptions(startedByRegion: false)
    }
#endif

    @objc public static func willResignActive() {
        BlueTokenSyncScheduler.shared.willResignActive()
    }

    @objc public static func didBecomeActive() {
#if os(iOS) || os(watchOS)
        blueNearbyAppBecameActive()
#endif
        
        BlueTokenSyncScheduler.shared.didBecomeActive()
    }
    
    @objc public static func didEnterBackground() {
#if os(iOS) || os(watchOS)
        blueNearbyAppEnterBackground()
#endif
    }
    
    @objc public static func willTerminate() {
        do {
            try blueCommands.release.run()
        } catch {
            fatalError(error.localizedDescription)
        }
        
        BlueTokenSyncScheduler.shared.willTerminate()
    }
}

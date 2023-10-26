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
#endif
    
    @objc public static func applicationWillTerminate() {
        do {
            try blueCommands.release.run()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    @objc public static func applicationDidEnterBackground() {
#if os(iOS) || os(watchOS)
        blueNearbyAppEnterBackground()
#endif
    }

    @objc public static func applicationDidBecomeActive() {
#if os(iOS) || os(watchOS)
        blueNearbyAppBecameActive()
#endif
    }
}

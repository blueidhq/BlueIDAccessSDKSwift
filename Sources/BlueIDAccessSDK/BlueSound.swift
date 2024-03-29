import Foundation
import AVFoundation

internal var BlueNegativeSoundSystemID: SystemSoundID = 1001
internal var BluePositiveSoundSystemID: SystemSoundID = 1002

/**
 * @class BlueSound
 *
 * A helper class to play specific sounds in the app.
 */
internal class BlueSound {
    static let shared = BlueSound()
    
    init() {
        AudioServicesCreateSystemSoundID(URL(fileURLWithPath: "/System/Library/Audio/UISounds/nfc_scan_failure.caf") as CFURL, &BlueNegativeSoundSystemID)
        AudioServicesCreateSystemSoundID(URL(fileURLWithPath: "/System/Library/Audio/UISounds/nfc_scan_complete.caf") as CFURL, &BluePositiveSoundSystemID)
    }
    
    func play(_ systemSoundID: SystemSoundID) {
        AudioServicesPlaySystemSound(systemSoundID)
    }
}

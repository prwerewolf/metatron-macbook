import Foundation
import AppKit
import AudioToolbox

public final class SoundEffects {
    public static let shared = SoundEffects()

    public var isSoundEnabled = true

    private init() {}

    public func playStart() {
        guard isSoundEnabled else { return }
        // macOS subtle click sound (Pop)
        NSSound(named: "Pop")?.play()
    }

    public func playStop() {
        guard isSoundEnabled else { return }
        // macOS subtle stop sound (Tink)
        NSSound(named: "Tink")?.play()
    }

    public func playSuccess() {
        guard isSoundEnabled else { return }
        // macOS success sound (Purr / Morse)
        NSSound(named: "Morse")?.play()
    }

    public func playError() {
        guard isSoundEnabled else { return }
        NSSound(named: "Basso")?.play()
    }
}

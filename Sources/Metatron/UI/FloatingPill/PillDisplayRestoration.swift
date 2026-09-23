import Foundation
import CoreGraphics

struct PillDisplay {
    let identifier: String?
    let frame: CGRect
}

enum PillDisplayRestoration {
    static func screenIndex(
        savedIdentifier: String?,
        savedOrigin: CGPoint?,
        displays: [PillDisplay],
        fallbackIndex: Int
    ) -> Int? {
        guard !displays.isEmpty else { return nil }

        // Identity survives rearranging monitors; coordinates migrate older settings.
        if let savedIdentifier,
           let index = displays.firstIndex(where: { $0.identifier == savedIdentifier }) {
            return index
        }
        if let savedOrigin, savedOrigin.x.isFinite, savedOrigin.y.isFinite,
           let index = displays.firstIndex(where: { $0.frame.contains(savedOrigin) }) {
            return index
        }

        // A disconnected display must not leave the pill off-screen.
        return displays.indices.contains(fallbackIndex) ? fallbackIndex : 0
    }
}

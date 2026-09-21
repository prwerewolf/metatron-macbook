import Foundation
import AppKit
import SwiftUI

public final class FloatingPillPanel: NSPanel {
    private let userDefaultsKeyX = "metatron_pill_x"
    private let userDefaultsKeyY = "metatron_pill_y"

    public init() {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 180, height: 42),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false

        // Host the SwiftUI View
        let hostingView = DraggableHostingView(rootView: FloatingPillView())
        self.contentView = hostingView

        restoreSavedPosition()
    }

    public override var canBecomeKey: Bool {
        return false // NEVER steal focus from active text fields!
    }

    public override var canBecomeMain: Bool {
        return false
    }

    private func restoreSavedPosition() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        if UserDefaults.standard.object(forKey: userDefaultsKeyX) != nil,
           UserDefaults.standard.object(forKey: userDefaultsKeyY) != nil {
            let savedX = UserDefaults.standard.double(forKey: userDefaultsKeyX)
            let savedY = UserDefaults.standard.double(forKey: userDefaultsKeyY)

            // Clamp within visible screen area
            let clampedX = max(screenFrame.minX + 20, min(screenFrame.maxX - 200, CGFloat(savedX)))
            let clampedY = max(screenFrame.minY + 20, min(screenFrame.maxY - 50, CGFloat(savedY)))

            self.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        } else {
            // Default position: bottom center of main screen, just above dock
            let defaultX = screenFrame.midX - 90
            let defaultY = screenFrame.minY + 60
            self.setFrameOrigin(NSPoint(x: defaultX, y: defaultY))
        }
    }

    public func saveCurrentPosition() {
        let origin = self.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: userDefaultsKeyX)
        UserDefaults.standard.set(Double(origin.y), forKey: userDefaultsKeyY)
    }

    public func resetPositionToCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let newX = screenFrame.midX - 90
        let newY = screenFrame.minY + 60
        self.setFrameOrigin(NSPoint(x: newX, y: newY))
        saveCurrentPosition()
    }
}

/// Custom NSHostingView that intercepts mouseDown to enable smooth 120Hz window dragging anywhere on the pill
public final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if let panel = window as? FloatingPillPanel {
            panel.saveCurrentPosition()
        }
    }
}

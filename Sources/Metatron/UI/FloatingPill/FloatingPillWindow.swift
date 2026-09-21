import Foundation
import AppKit
import SwiftUI

public enum PillSnapTarget: String, CaseIterable, Identifiable {
    case bottomCenter = "Bottom Center"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case topCenter = "Top Center"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case leftCenter = "Left Edge"
    case leftTop = "Left Top"
    case leftBottom = "Left Bottom"
    case rightCenter = "Right Edge"
    case rightTop = "Right Top"
    case rightBottom = "Right Bottom"

    public var id: String { rawValue }

    public var isVertical: Bool {
        switch self {
        case .leftCenter, .leftTop, .leftBottom, .rightCenter, .rightTop, .rightBottom:
            return true
        default:
            return false
        }
    }
}

public final class FloatingPillPanel: NSPanel {
    private let userDefaultsKeyX = "metatron_pill_x"
    private let userDefaultsKeyY = "metatron_pill_y"
    private let userDefaultsKeySnap = "metatron_pill_snap"

    public static let horizontalSize = NSSize(width: 196, height: 42)
    public static let verticalSize = NSSize(width: 42, height: 140)

    public init() {
        let isVert = AppState.shared.pillOrientation == .vertical
        let initSize = isVert ? FloatingPillPanel.verticalSize : FloatingPillPanel.horizontalSize

        super.init(
            contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: initSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false // We handle dragging manually with magnetic edge snapping
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

    // MARK: - Snapping & Positioning

    public func snapToNearestEdgeAndSave() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let curFrame = self.frame
        let margin: CGFloat = 14

        let centerX = curFrame.midX
        let centerY = curFrame.midY

        let distLeft = abs(centerX - screenFrame.minX)
        let distRight = abs(screenFrame.maxX - centerX)
        let distBottom = abs(centerY - screenFrame.minY)
        let distTop = abs(screenFrame.maxY - centerY)

        let minDist = min(distLeft, distRight, distBottom, distTop)

        var targetSize: NSSize
        var targetOrigin: NSPoint
        var newOrientation: PillOrientation
        var snapTarget: PillSnapTarget

        if minDist == distLeft {
            // Snap to Left Edge -> Vertical Pill
            newOrientation = .vertical
            targetSize = FloatingPillPanel.verticalSize
            let x = screenFrame.minX + margin
            if centerY > screenFrame.minY + screenFrame.height * 0.66 {
                snapTarget = .leftTop
                targetOrigin = NSPoint(x: x, y: screenFrame.maxY - targetSize.height - margin)
            } else if centerY < screenFrame.minY + screenFrame.height * 0.33 {
                snapTarget = .leftBottom
                targetOrigin = NSPoint(x: x, y: screenFrame.minY + margin)
            } else {
                snapTarget = .leftCenter
                targetOrigin = NSPoint(x: x, y: screenFrame.midY - targetSize.height / 2)
            }
        } else if minDist == distRight {
            // Snap to Right Edge -> Vertical Pill
            newOrientation = .vertical
            targetSize = FloatingPillPanel.verticalSize
            let x = screenFrame.maxX - targetSize.width - margin
            if centerY > screenFrame.minY + screenFrame.height * 0.66 {
                snapTarget = .rightTop
                targetOrigin = NSPoint(x: x, y: screenFrame.maxY - targetSize.height - margin)
            } else if centerY < screenFrame.minY + screenFrame.height * 0.33 {
                snapTarget = .rightBottom
                targetOrigin = NSPoint(x: x, y: screenFrame.minY + margin)
            } else {
                snapTarget = .rightCenter
                targetOrigin = NSPoint(x: x, y: screenFrame.midY - targetSize.height / 2)
            }
        } else if minDist == distTop {
            // Snap to Top Edge -> Horizontal Pill
            newOrientation = .horizontal
            targetSize = FloatingPillPanel.horizontalSize
            let y = screenFrame.maxY - targetSize.height - margin
            if centerX < screenFrame.minX + screenFrame.width * 0.33 {
                snapTarget = .topLeft
                targetOrigin = NSPoint(x: screenFrame.minX + margin, y: y)
            } else if centerX > screenFrame.maxX - screenFrame.width * 0.33 {
                snapTarget = .topRight
                targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: y)
            } else {
                snapTarget = .topCenter
                targetOrigin = NSPoint(x: screenFrame.midX - targetSize.width / 2, y: y)
            }
        } else {
            // Snap to Bottom Edge -> Horizontal Pill
            newOrientation = .horizontal
            targetSize = FloatingPillPanel.horizontalSize
            let y = screenFrame.minY + margin
            if centerX < screenFrame.minX + screenFrame.width * 0.33 {
                snapTarget = .bottomLeft
                targetOrigin = NSPoint(x: screenFrame.minX + margin, y: y)
            } else if centerX > screenFrame.maxX - screenFrame.width * 0.33 {
                snapTarget = .bottomRight
                targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: y)
            } else {
                snapTarget = .bottomCenter
                targetOrigin = NSPoint(x: screenFrame.midX - targetSize.width / 2, y: y)
            }
        }

        applySnap(target: snapTarget, origin: targetOrigin, size: targetSize, orientation: newOrientation)
    }

    public func snap(to target: PillSnapTarget) {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 14

        let targetSize = target.isVertical ? FloatingPillPanel.verticalSize : FloatingPillPanel.horizontalSize
        var targetOrigin: NSPoint

        switch target {
        case .bottomCenter:
            targetOrigin = NSPoint(x: screenFrame.midX - targetSize.width / 2, y: screenFrame.minY + margin)
        case .bottomLeft:
            targetOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        case .bottomRight:
            targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: screenFrame.minY + margin)
        case .topCenter:
            targetOrigin = NSPoint(x: screenFrame.midX - targetSize.width / 2, y: screenFrame.maxY - targetSize.height - margin)
        case .topLeft:
            targetOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.maxY - targetSize.height - margin)
        case .topRight:
            targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: screenFrame.maxY - targetSize.height - margin)
        case .leftCenter:
            targetOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.midY - targetSize.height / 2)
        case .leftTop:
            targetOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.maxY - targetSize.height - margin)
        case .leftBottom:
            targetOrigin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        case .rightCenter:
            targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: screenFrame.midY - targetSize.height / 2)
        case .rightTop:
            targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: screenFrame.maxY - targetSize.height - margin)
        case .rightBottom:
            targetOrigin = NSPoint(x: screenFrame.maxX - targetSize.width - margin, y: screenFrame.minY + margin)
        }

        let orientation: PillOrientation = target.isVertical ? .vertical : .horizontal
        applySnap(target: target, origin: targetOrigin, size: targetSize, orientation: orientation)
    }

    private func applySnap(target: PillSnapTarget, origin: NSPoint, size: NSSize, orientation: PillOrientation) {
        AppState.shared.pillOrientation = orientation
        UserDefaults.standard.set(target.rawValue, forKey: userDefaultsKeySnap)

        let targetFrame = NSRect(origin: origin, size: size)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
        }

        saveCurrentPosition()
    }

    private func restoreSavedPosition() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        if let savedSnapRaw = UserDefaults.standard.string(forKey: userDefaultsKeySnap),
           let snapTarget = PillSnapTarget(rawValue: savedSnapRaw) {
            snap(to: snapTarget)
            return
        }

        if UserDefaults.standard.object(forKey: userDefaultsKeyX) != nil,
           UserDefaults.standard.object(forKey: userDefaultsKeyY) != nil {
            let savedX = UserDefaults.standard.double(forKey: userDefaultsKeyX)
            let savedY = UserDefaults.standard.double(forKey: userDefaultsKeyY)
            let isVert = AppState.shared.pillOrientation == .vertical
            let size = isVert ? FloatingPillPanel.verticalSize : FloatingPillPanel.horizontalSize

            let clampedX = max(screenFrame.minX + 10, min(screenFrame.maxX - size.width - 10, CGFloat(savedX)))
            let clampedY = max(screenFrame.minY + 10, min(screenFrame.maxY - size.height - 10, CGFloat(savedY)))

            self.setFrame(NSRect(origin: NSPoint(x: clampedX, y: clampedY), size: size), display: true)
            snapToNearestEdgeAndSave()
        } else {
            // Default position: bottom center of main screen
            snap(to: .bottomCenter)
        }
    }

    public func saveCurrentPosition() {
        let origin = self.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: userDefaultsKeyX)
        UserDefaults.standard.set(Double(origin.y), forKey: userDefaultsKeyY)
    }

    public func resetPositionToCenter() {
        snap(to: .bottomCenter)
    }
}

/// Custom NSHostingView with drag-and-snap and click-to-record detection
public final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    private var initialMouseLocation: NSPoint = .zero
    private var isDragging = false

    public override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        isDragging = false
        window?.performDrag(with: event)

        // If mouse moved more than 4 points, user dragged and dropped
        let currentMouse = NSEvent.mouseLocation
        let distance = hypot(currentMouse.x - initialMouseLocation.x, currentMouse.y - initialMouseLocation.y)

        if distance > 4.0 {
            if let panel = window as? FloatingPillPanel {
                panel.snapToNearestEdgeAndSave()
            }
        } else {
            // Short tap: toggle dictation recording
            AppState.shared.toggleRecording()
        }
    }
}

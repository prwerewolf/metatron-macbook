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
    private let userDefaultsKeyDisplay = "metatron_pill_display"

    // Ultra-compact, sleek dimensions — minimal footprint, zero dots
    public static let horizontalSize = NSSize(width: 106, height: 30)
    public static let verticalSize = NSSize(width: 30, height: 44)

    private var initialMouse: NSPoint = .zero
    private var initialOrigin: NSPoint = .zero
    private var isDraggingPill = false
    private var screenParametersObserver: NSObjectProtocol?

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
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: FloatingPillView())
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        restoreSavedPosition()

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenParametersChanged()
        }
    }

    deinit {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public override var canBecomeKey: Bool {
        return false // NEVER steal focus from active text fields!
    }

    public override var canBecomeMain: Bool {
        return false
    }

    // MARK: - Direct Drag & Snap Event Handling

    public override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            initialMouse = NSEvent.mouseLocation
            initialOrigin = self.frame.origin
            isDraggingPill = false
            super.sendEvent(event)

        case .leftMouseDragged:
            let curMouse = NSEvent.mouseLocation
            let dx = curMouse.x - initialMouse.x
            let dy = curMouse.y - initialMouse.y
            if abs(dx) > 3 || abs(dy) > 3 {
                isDraggingPill = true
                self.setFrameOrigin(NSPoint(x: initialOrigin.x + dx, y: initialOrigin.y + dy))
            } else {
                super.sendEvent(event)
            }

        case .leftMouseUp:
            if isDraggingPill {
                isDraggingPill = false
                snapToNearestEdgeAndSave()
            } else {
                super.sendEvent(event)
            }

        default:
            super.sendEvent(event)
        }
    }

    // MARK: - Snapping & Positioning

    public func snapToNearestEdgeAndSave() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let curFrame = self.frame
        let margin: CGFloat = 12

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
            // Snap to Left Edge -> Vertical Pill ("down not sideways")
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
            // Snap to Right Edge -> Vertical Pill ("down not sideways")
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

        applySnap(target: snapTarget, origin: targetOrigin, size: targetSize, orientation: newOrientation, screen: screen)
    }

    public func snap(to target: PillSnapTarget) {
        guard let screen = self.screen ?? NSScreen.main else { return }
        snap(to: target, on: screen)
    }

    private func snap(to target: PillSnapTarget, on screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 12

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
        applySnap(target: target, origin: targetOrigin, size: targetSize, orientation: orientation, screen: screen)
    }

    private func applySnap(target: PillSnapTarget, origin: NSPoint, size: NSSize, orientation: PillOrientation, screen: NSScreen) {
        AppState.shared.pillOrientation = orientation
        UserDefaults.standard.set(target.rawValue, forKey: userDefaultsKeySnap)
        UserDefaults.standard.set(Double(origin.x), forKey: userDefaultsKeyX)
        UserDefaults.standard.set(Double(origin.y), forKey: userDefaultsKeyY)
        UserDefaults.standard.set(displayIdentifier(for: screen), forKey: userDefaultsKeyDisplay)

        let targetFrame = NSRect(origin: origin, size: size)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
        }
        self.invalidateShadow()
    }

    private func restoreSavedPosition() {
        let defaults = UserDefaults.standard
        let savedOrigin: NSPoint?
        if defaults.object(forKey: userDefaultsKeyX) != nil,
           defaults.object(forKey: userDefaultsKeyY) != nil {
            let x = defaults.double(forKey: userDefaultsKeyX)
            let y = defaults.double(forKey: userDefaultsKeyY)
            savedOrigin = x.isFinite && y.isFinite ? NSPoint(x: x, y: y) : nil
        } else {
            savedOrigin = nil
        }

        let screens = NSScreen.screens
        let fallbackIndex = screens.firstIndex(where: { $0 == NSScreen.main }) ?? 0
        let displays = screens.map { PillDisplay(identifier: displayIdentifier(for: $0), frame: $0.frame) }
        guard let screenIndex = PillDisplayRestoration.screenIndex(
            savedIdentifier: defaults.string(forKey: userDefaultsKeyDisplay),
            savedOrigin: savedOrigin,
            displays: displays,
            fallbackIndex: fallbackIndex
        ) else { return }
        let screen = screens[screenIndex]

        if let savedSnapRaw = UserDefaults.standard.string(forKey: userDefaultsKeySnap),
           let snapTarget = PillSnapTarget(rawValue: savedSnapRaw) {
            snap(to: snapTarget, on: screen)
            return
        }

        let screenFrame = screen.visibleFrame

        if let savedOrigin {
            let isVert = AppState.shared.pillOrientation == .vertical
            let size = isVert ? FloatingPillPanel.verticalSize : FloatingPillPanel.horizontalSize

            let clampedX = max(screenFrame.minX + 10, min(screenFrame.maxX - size.width - 10, savedOrigin.x))
            let clampedY = max(screenFrame.minY + 10, min(screenFrame.maxY - size.height - 10, savedOrigin.y))

            self.setFrame(NSRect(origin: NSPoint(x: clampedX, y: clampedY), size: size), display: true)
            snapToNearestEdgeAndSave()
        } else {
            snap(to: .bottomCenter, on: screen)
        }
    }

    private func displayIdentifier(for screen: NSScreen) -> String? {
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayNumber.uint32Value)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    public func saveCurrentPosition() {
        let origin = self.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: userDefaultsKeyX)
        UserDefaults.standard.set(Double(origin.y), forKey: userDefaultsKeyY)
        if let screen = self.screen {
            UserDefaults.standard.set(displayIdentifier(for: screen), forKey: userDefaultsKeyDisplay)
        }
    }

    public func resetPositionToCenter() {
        snap(to: .bottomCenter)
    }

    /// Re-evaluates position when monitors are connected/disconnected or resolution changes.
    func handleScreenParametersChanged() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let isVisibleOnAnyScreen = screens.contains { $0.visibleFrame.intersects(self.frame) }
        if !isVisibleOnAnyScreen {
            restoreSavedPosition()
        }
    }
}

import Foundation
import AppKit

public final class TextInserter {
    public static let shared = TextInserter()

    private init() {}

    /// Places text on the clipboard and simulates Cmd+V keystroke to active application
    public func insertText(_ text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }

        // 1. Place transcribed text onto general pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 2. Synthesize Cmd+V keystroke to the focused application
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.sendPasteKeystroke()
            completion?()
        }
    }

    /// Synthesizes Command + V keypress events
    public func sendPasteKeystroke() {
        let vKeyCode: CGKeyCode = 9 // 'v' virtual key code on macOS

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

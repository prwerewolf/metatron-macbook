import Foundation
import AppKit
import ApplicationServices

public final class TextInserter {
    public static let shared = TextInserter()

    private init() {}

    /// Directly types or injects text into the active focused application without touching the clipboard.
    public func insertTextDirectly(_ text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }

        // 1. Attempt instantaneous insertion via Accessibility API if focused element supports it
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if axResult == .success, let element = focusedElement {
            // CFGetTypeID check or force cast to AXUIElement
            let axUIElement = element as! AXUIElement
            let error = AXUIElementSetAttributeValue(axUIElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if error == .success {
                completion?()
                return
            }
        }

        // 2. Direct Unicode keystroke typing via CGEvent event tap (100% bypasses NSPasteboard)
        typeUnicodeString(text)
        completion?()
    }

    /// Types a string directly using CGEvent Unicode injection without touching NSPasteboard.
    public func typeUnicodeString(_ string: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Array = Array(string.utf16)
        let chunkSize = 20
        var index = 0

        while index < utf16Array.count {
            let currentChunk = min(chunkSize, utf16Array.count - index)
            var chunk = Array(utf16Array[index..<(index + currentChunk)])

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp?.post(tap: .cghidEventTap)

            index += currentChunk
            if utf16Array.count > 100 {
                usleep(1000) // 1ms delay for long strings
            }
        }
    }

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


import AppKit
import ApplicationServices

/// The application and focused control that owned the cursor when dictation began.
/// Checking a target never activates an application or changes keyboard focus.
public struct InsertionTarget {
    private let processID: pid_t
    private let applicationElement: AXUIElement
    private let focusedElement: AXUIElement?

    public static func capture() -> InsertionTarget? {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication else { return nil }

        let processID = application.processIdentifier
        if processID == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(processID)
        let focusedElement = focus(in: applicationElement)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return nil }

        return InsertionTarget(
            processID: processID,
            applicationElement: applicationElement,
            focusedElement: focusedElement
        )
    }

    public var targetPID: pid_t { processID }

    /// Attempts to read the character immediately before the current selection/cursor in the focused element.
    /// Returns nil if accessibility attributes are unsupported.
    public func precedingCharacter() -> Character? {
        guard let element = focusedElement ?? Self.focus(in: applicationElement) else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }

        let axValue = rangeValue as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.location > 0 else { return nil }

        var charRange = CFRange(location: cfRange.location - 1, length: 1)
        guard let charRangeVal = AXValueCreate(.cfRange, &charRange) else { return nil }
        var stringVal: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            charRangeVal,
            &stringVal
        ) == .success,
              let string = stringVal as? String,
              let char = string.first else { return nil }
        return char
    }

    public var isCurrent: Bool {
        guard let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              currentPID == processID else { return false }

        // If both original and current focused elements could be captured,
        // check whether they match.
        if let focused = focusedElement,
           let currentFocus = Self.focus(in: applicationElement),
           CFEqual(focused, currentFocus) {
            return true
        }

        // For applications that don't expose control-level accessibility (e.g. web
        // browsers, Electron apps like VS Code/Slack, terminals), or where accessibility
        // proxy objects return false for CFEqual despite being in the same control,
        // verify that the user is still in the same application.
        return Self.matches(
            originalProcessID: processID,
            currentProcessID: currentPID,
            focusedElementMatches: true
        )
    }

    // Kept separate from the system queries so focus policy can be tested without
    // accessibility permission, posting keyboard events, or touching the clipboard.
    static func matches(
        originalProcessID: pid_t,
        currentProcessID: pid_t?,
        focusedElementMatches: Bool
    ) -> Bool {
        currentProcessID == originalProcessID && focusedElementMatches
    }

    // AX attribute reads synchronously message the destination app. Apply the
    // timeout to this exact object before every query; equal AX objects do not
    // inherit per-object timeouts. An unresponsive destination fails closed.
    // Injectable functions let tests simulate stalled AX messaging without UI reads.
    static func focus(
        in application: AXUIElement,
        setMessagingTimeout: (AXUIElement, Float) -> AXError = AXUIElementSetMessagingTimeout,
        copyAttributeValue: (AXUIElement, CFString, UnsafeMutablePointer<CFTypeRef?>) -> AXError = AXUIElementCopyAttributeValue
    ) -> AXUIElement? {
        guard setMessagingTimeout(application, 0.2) == .success else { return nil }
        var value: CFTypeRef?
        let result = copyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

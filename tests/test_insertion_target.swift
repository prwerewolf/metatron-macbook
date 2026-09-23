import Foundation
import ApplicationServices

@main
struct InsertionTargetTests {
    static func main() {
        let scenarios: [(String, pid_t?, Bool, Bool)] = [
            ("Original application and control still focused", 100, true, true),
            ("Switched to another application", 200, true, false),
            ("Switched to another field in the original application", 100, false, false),
            ("Original application lost focus and no foreground app is available", nil, true, false),
            ("Focused control is missing or cannot be read", 100, false, false),
            ("Application and focused control both changed", 200, false, false)
        ]

        for (description, currentProcessID, focusedElementMatches, expected) in scenarios {
            let actual = InsertionTarget.matches(
                originalProcessID: 100,
                currentProcessID: currentProcessID,
                focusedElementMatches: focusedElementMatches
            )
            precondition(actual == expected, description)
        }

        // Creating an AX object is local; all messaging below is replaced by fakes.
        // Model an unresponsive server that consumes its configured timeout.
        let application = AXUIElementCreateApplication(getpid())
        var configuredTimeout: Float = 6
        var elapsedMessagingTime: Float = 0
        var requestedAttributes: [String] = []
        let unavailableFocus = InsertionTarget.focus(
            in: application,
            setMessagingTimeout: { element, timeout in
                precondition(CFEqual(element, application))
                configuredTimeout = timeout
                return .success
            },
            copyAttributeValue: { element, attribute, _ in
                precondition(CFEqual(element, application))
                requestedAttributes.append(attribute as String)
                elapsedMessagingTime += configuredTimeout
                return .cannotComplete
            }
        )
        precondition(unavailableFocus == nil, "An unresponsive app must never become an insertion target")
        precondition(elapsedMessagingTime > 0 && elapsedMessagingTime <= 0.25,
                     "A stalled focus query must be bounded, rather than consuming the default multi-second timeout")
        precondition(requestedAttributes == [kAXFocusedUIElementAttribute as String],
                     "Focus protection must read only the focused element identity")

        var didQueryAfterConfigurationFailure = false
        let unboundedFocus = InsertionTarget.focus(
            in: application,
            setMessagingTimeout: { _, _ in .invalidUIElement },
            copyAttributeValue: { _, _, _ in
                didQueryAfterConfigurationFailure = true
                return .success
            }
        )
        precondition(unboundedFocus == nil && !didQueryAfterConfigurationFailure,
                     "Do not attempt an unbounded query if applying the timeout fails")

        let responsiveFocus = InsertionTarget.focus(
            in: application,
            setMessagingTimeout: { _, _ in .success },
            copyAttributeValue: { _, _, result in
                result.pointee = application
                return .success
            }
        )
        precondition(responsiveFocus.map { CFEqual($0, application) } == true,
                     "A successful bounded query must preserve its focused element")

        // An Accessibility timeout or missing original target must never paste.
        var nilTargetOutcome: Bool?
        let queuedWithoutTarget = TextInserter.shared.insertText(
            "Sensitive dictation", target: nil,
            completion: { inserted in nilTargetOutcome = inserted }
        )
        precondition(!queuedWithoutTarget && nilTargetOutcome == false,
                     "A nil destination must fail before touching the clipboard")

        print("All Metatron insertion destination tests passed (\(scenarios.count + 4) scenarios).")
    }
}

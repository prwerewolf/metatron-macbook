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

        // Test bounded timeout and cursor context on focused element
        let targetWithElement = InsertionTarget(processID: 100, applicationElement: application, focusedElement: application)
        var cursorTimeout: Float = 0
        let timedOutContext = targetWithElement.cursorContext(
            setMessagingTimeout: { _, timeout in
                cursorTimeout = timeout
                return .cannotComplete
            }
        )
        precondition(timedOutContext == .unavailable, "Stalled cursor query must fail closed")
        precondition(cursorTimeout == 0.2, "Cursor context must enforce 0.2s messaging timeout")

        // Location 0 should return startOfText
        var zeroRange = CFRange(location: 0, length: 0)
        let zeroAxVal = AXValueCreate(.cfRange, &zeroRange)!
        let startContext = targetWithElement.cursorContext(
            setMessagingTimeout: { _, _ in .success },
            copyAttributeValue: { _, attr, result in
                if attr as String == kAXSelectedTextRangeAttribute as String {
                    result.pointee = zeroAxVal
                    return .success
                }
                return .attributeUnsupported
            }
        )
        precondition(startContext == .startOfText, "Location 0 must report startOfText")

        // Location > 0 should return character
        var midRange = CFRange(location: 5, length: 0)
        let midAxVal = AXValueCreate(.cfRange, &midRange)!
        let charContext = targetWithElement.cursorContext(
            setMessagingTimeout: { _, _ in .success },
            copyAttributeValue: { _, attr, result in
                if attr as String == kAXSelectedTextRangeAttribute as String {
                    result.pointee = midAxVal
                    return .success
                }
                return .attributeUnsupported
            },
            copyParameterizedAttributeValue: { _, attr, _, result in
                if attr as String == kAXStringForRangeParameterizedAttribute as String {
                    result.pointee = "W" as CFString
                    return .success
                }
                return .attributeUnsupported
            }
        )
        precondition(charContext == .character("W"), "Location > 0 must report preceding character")

        // Test precedingText: location 0 returns nil
        let zeroText = targetWithElement.precedingText(
            setMessagingTimeout: { _, _ in .success },
            copyAttributeValue: { _, attr, result in
                if attr as String == kAXSelectedTextRangeAttribute as String {
                    result.pointee = zeroAxVal
                    return .success
                }
                return .attributeUnsupported
            }
        )
        precondition(zeroText == nil, "Location 0 must report nil preceding text")

        // Test precedingText: location > 0 returns preceding substring
        var queriedRange = CFRange()
        let midText = targetWithElement.precedingText(
            maxCharacters: 50,
            setMessagingTimeout: { _, _ in .success },
            copyAttributeValue: { _, attr, result in
                if attr as String == kAXSelectedTextRangeAttribute as String {
                    result.pointee = midAxVal
                    return .success
                }
                return .attributeUnsupported
            },
            copyParameterizedAttributeValue: { _, attr, param, result in
                if attr as String == kAXStringForRangeParameterizedAttribute as String {
                    let axRange = param as! AXValue
                    AXValueGetValue(axRange, .cfRange, &queriedRange)
                    result.pointee = "Hello" as CFString
                    return .success
                }
                return .attributeUnsupported
            }
        )
        precondition(midText == "Hello", "Location > 0 must report preceding text")
        precondition(queriedRange.location == 0 && queriedRange.length == 5, "Queried range must cover prefix up to location 5")

        print("All Metatron insertion destination tests passed (\(scenarios.count + 9) scenarios).")
    }
}


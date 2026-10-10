import Foundation

@main
struct KeyboardShortcutTests {
    static func main() {
        let alternateCommandLayout: [UInt16: String] = [9: "x", 6: "y", 42: "v", 43: "z"]
        precondition(KeyboardShortcutResolver.keyCode(for: "v", translate: { alternateCommandLayout[$0] }) == 42)
        precondition(KeyboardShortcutResolver.keyCode(for: "z", translate: { alternateCommandLayout[$0] }) == 43)
        precondition(KeyboardShortcutResolver.keyCode(for: "v", translate: { $0 == 55 ? "V" : nil }) == 55)
        precondition(KeyboardShortcutResolver.keyCode(for: "v", translate: { _ in "ж" }) == nil,
                     "An unsupported shortcut must not fall back to the US physical key")
        precondition(KeyboardShortcutResolver.keyCode(for: "v", translate: { _ in nil }) == nil)
        precondition(KeyboardShortcutResolver.keyCode(for: "paste", translate: { _ in "paste" }) == nil)
        print("Keyboard shortcuts passed: layout-specific Command mappings and unsupported-layout protection.")
    }
}

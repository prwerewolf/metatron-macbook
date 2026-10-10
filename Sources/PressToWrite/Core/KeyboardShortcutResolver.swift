import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Resolve Command shortcuts using the current layout's Command mapping.
/// An input method with no layout data may use the last ASCII-capable layout.
/// A known layout with no matching shortcut must never fall back to US keys.
public enum KeyboardShortcutResolver {
    public static func keyCode(for character: String) -> CGKeyCode? {
        guard let data = layoutData(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue())
            ?? layoutData(TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
        else { return nil }

        return data.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return nil }
            let layout = address.assumingMemoryBound(to: UCKeyboardLayout.self)
            return keyCode(for: character) { code in
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let result = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), UInt32(cmdKey) >> 8,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeys, characters.count, &length, &characters
                )
                guard result == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
    }

    static func keyCode(for character: String, translate: (UInt16) -> String?) -> CGKeyCode? {
        guard character.count == 1 else { return nil }
        for code in UInt16(0)..<128 where translate(code)?.lowercased() == character.lowercased() {
            return CGKeyCode(code)
        }
        return nil
    }

    private static func layoutData(_ source: TISInputSource?) -> Data? {
        guard let source,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
}

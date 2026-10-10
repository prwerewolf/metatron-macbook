import Foundation

public struct VocabularySuggestion: Equatable, Identifiable {
    public let original: String
    public let word: String
    public var id: String { original + "→" + word }
}

/// A bounded snapshot of one verified, non-secure text control. Never persisted.
public struct CorrectionFieldSnapshot: Equatable {
    public let text: String
    public let selection: NSRange

    public init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }
}

/// Attribute subsequent edits to exactly the region replaced by our paste.
/// Changes anywhere outside that region invalidate the learning session.
public struct CorrectionCapture {
    public let insertedText: String
    public let expectedText: String
    public let beforeText: String
    private let prefix: String
    private let suffix: String

    public init?(before: CorrectionFieldSnapshot, insertedText: String) {
        let text = before.text as NSString
        guard text.length <= 8192, !insertedText.isEmpty, insertedText.utf16.count <= 2048,
              before.selection.location >= 0, before.selection.length >= 0,
              before.selection.location <= text.length,
              before.selection.length <= text.length - before.selection.location else { return nil }
        self.insertedText = insertedText
        beforeText = before.text
        prefix = text.substring(to: before.selection.location)
        suffix = text.substring(from: NSMaxRange(before.selection))
        expectedText = prefix + insertedText + suffix
        guard expectedText.utf16.count <= 8192 else { return nil }
    }

    public func editedText(in snapshot: CorrectionFieldSnapshot) -> String? {
        let text = snapshot.text as NSString
        let prefixLength = prefix.utf16.count
        let suffixLength = suffix.utf16.count
        let length = text.length - prefixLength - suffixLength
        guard text.length <= 8192, length >= 0, length <= 2048,
              text.substring(to: prefixLength).utf16.elementsEqual(prefix.utf16),
              text.substring(from: text.length - suffixLength).utf16.elementsEqual(suffix.utf16)
        else { return nil }
        return text.substring(with: NSRange(location: prefixLength, length: length))
    }
}

public enum CorrectionLearner {
    private static let ordinaryWords = Set((
        "the and that this with from have there their then than what when where why " +
        "your you our for are was were will would should could can not yes okay " +
        "one two three four five six seven eight nine ten hundred thousand " +
        "monday tuesday wednesday thursday friday saturday sunday " +
        "january february march april may june july august september october november december"
    ).split(separator: " ").map(String.init))

    public static func suggestions(original: String, edited: String, knownWords: [String]) -> [VocabularySuggestion] {
        guard original.utf16.count <= 2048, edited.utf16.count <= 2048 else { return [] }
        let before = words(original)
        let after = words(edited)
        // An insertion/deletion or broad rewrite is not a spelling correction.
        guard !before.isEmpty, before.count == after.count, before.count <= 128 else { return [] }
        let changed = before.indices.filter { before[$0] != after[$0] }
        guard !changed.isEmpty, changed.count <= min(3, max(1, before.count / 4)) else { return [] }
        let known = Set(knownWords.map { $0.lowercased() })
        var seen = Set<String>()
        var result: [VocabularySuggestion] = []
        for index in changed {
            let old = before[index]
            let word = after[index]
            let lower = word.lowercased()
            guard old.count >= 3, word.count >= 3, old.count <= 64, word.count <= 64,
                  !ordinaryWords.contains(old.lowercased()), !ordinaryWords.contains(lower),
                  word.unicodeScalars.contains(where: CharacterSet.letters.contains),
                  distance(old.lowercased(), lower) <= max(1, max(old.count, word.count) * 2 / 5)
            else { return [] }
            // Ignore sentence capitalization; retain deliberate acronym/internal casing.
            if old.lowercased() == lower,
               word.dropFirst().allSatisfy({ !$0.isUppercase }) { continue }
            if !known.contains(lower), seen.insert(lower).inserted {
                result.append(VocabularySuggestion(original: old, word: word))
            }
        }
        return result
    }

    private static func words(_ text: String) -> [String] {
        let pattern = "[\\p{L}\\p{N}]+(?:['’\\-][\\p{L}\\p{N}]+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func distance(_ left: String, _ right: String) -> Int {
        let a = Array(left), b = Array(right)
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var row = [i + 1]
            for (j, other) in b.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1,
                               previous[j] + (character == other ? 0 : 1)))
            }
            previous = row
        }
        return previous[b.count]
    }
}

/// Observe for at most thirty seconds, wait for stable edits, and keep all
/// compared text in memory. The reader must revalidate exact control identity.
@MainActor
public final class CorrectionMonitor {
    private var task: Task<Void, Never>?

    public init() {}

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func start(
        capture: CorrectionCapture, knownWords: [String],
        read: @escaping () -> CorrectionFieldSnapshot?,
        onSuggestions: @escaping ([VocabularySuggestion]) -> Void,
        onInvalidated: @escaping () -> Void,
        interval: UInt64 = 500_000_000, duration: TimeInterval = 30,
        settleDuration: TimeInterval = 1
    ) {
        stop()
        task = Task {
            let started = ProcessInfo.processInfo.systemUptime
            var verifiedPaste = false
            var lastEdit: String?
            var changedAt = started
            var lastPublished: [VocabularySuggestion] = []
            while !Task.isCancelled, ProcessInfo.processInfo.systemUptime - started < duration {
                do { try await Task.sleep(nanoseconds: interval) } catch { return }
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard now - started < duration else { return }
                guard let snapshot = read() else { onInvalidated(); return }
                if !verifiedPaste {
                    if snapshot.text == capture.expectedText { verifiedPaste = true }
                    else if snapshot.text == capture.beforeText, now - started < 1.5 { continue }
                    else { onInvalidated(); return }
                }
                guard let edited = capture.editedText(in: snapshot) else { onInvalidated(); return }
                if edited != lastEdit {
                    lastEdit = edited
                    changedAt = now
                    if !lastPublished.isEmpty { onSuggestions([]); lastPublished = [] }
                }
                guard now - changedAt >= settleDuration else { continue }
                let suggestions = CorrectionLearner.suggestions(
                    original: capture.insertedText, edited: edited, knownWords: knownWords
                )
                if suggestions != lastPublished {
                    lastPublished = suggestions
                    onSuggestions(suggestions)
                }
            }
        }
    }
}

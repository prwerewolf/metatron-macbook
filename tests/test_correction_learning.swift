import Foundation

@main
struct CorrectionLearningTests {
    static func snapshot(_ text: String, location: Int = 0, length: Int = 0) -> CorrectionFieldSnapshot {
        CorrectionFieldSnapshot(text: text, selection: NSRange(location: location, length: length))
    }

    @MainActor
    static func waitUntil(_ description: String, condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !condition() {
            precondition(ProcessInfo.processInfo.systemUptime < deadline,
                         "Timed out waiting for \(description)")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor
    static func main() async throws {
        let suggestion = VocabularySuggestion(original: "Lumara", word: "Lumora")
        precondition(CorrectionLearner.suggestions(original: "Send the proposal to Lumara.", edited: "Send the proposal to Lumora.", knownWords: []) == [suggestion])
        precondition(CorrectionLearner.suggestions(original: "Send the proposal to Lumara.", edited: "Send the proposal to Lumora.", knownWords: ["LUMORA"]).isEmpty)
        let exclusions = [
            ("ship friday", "ship monday"), ("take four", "take five"),
            ("why did this happen", "what did this happen"),
            ("send the proposal", "send the revised proposal"),
            ("write the proposal", "cancel the contract"), ("hello world", "Hello world"),
            ("Lumara", "Lumara"), ("version 123", "version 124")
        ]
        for (original, edited) in exclusions {
            precondition(CorrectionLearner.suggestions(original: original, edited: edited, knownWords: []).isEmpty,
                         "Content edits must not become vocabulary: \(original)")
        }
        precondition(CorrectionLearner.suggestions(original: "Luméara", edited: "Luméra", knownWords: []).count == 1)
        precondition(CorrectionLearner.suggestions(original: "Use macos", edited: "Use macOS", knownWords: []).first?.word == "macOS")

        // Attribute edits to a selected region, preserving all surrounding content.
        let before = snapshot("📌 Existing: old ending", location: "📌 Existing: ".utf16.count, length: 3)
        let capture = CorrectionCapture(before: before, insertedText: "Lumara")!
        precondition(capture.expectedText == "📌 Existing: Lumara ending")
        precondition(capture.editedText(in: snapshot("📌 Existing: Lumora ending")) == "Lumora")
        precondition(capture.editedText(in: snapshot("📌 Changed: Lumora ending")) == nil)
        precondition(capture.editedText(in: snapshot("📌 Existing: Lumora finish")) == nil)
        let extended = capture.editedText(in: snapshot("📌 Existing: Lumora different ending"))!
        precondition(CorrectionLearner.suggestions(original: "Lumara", edited: extended, knownWords: []).isEmpty,
                     "New prose at the region boundary must not become a spelling correction")
        precondition(CorrectionCapture(before: snapshot("short", location: 100), insertedText: "Lumara") == nil)
        precondition(CorrectionCapture(before: snapshot(String(repeating: "x", count: 8193)), insertedText: "Lumara") == nil)
        precondition(CorrectionCapture(before: snapshot(""), insertedText: String(repeating: "x", count: 2049)) == nil)

        let monitor = CorrectionMonitor()
        let insertion = CorrectionCapture(before: snapshot(""), insertedText: "Send this to Lumara.")!
        var current: CorrectionFieldSnapshot? = snapshot(insertion.expectedText)
        var published: [VocabularySuggestion] = []
        var invalidations = 0
        var verifiedReads = 0
        var editedReads = 0
        var editedAt: TimeInterval?
        let settleDuration = 0.02
        monitor.start(capture: insertion, knownWords: [], read: {
            if current?.text == insertion.expectedText { verifiedReads += 1 }
            if current?.text == "Send this to Lumora." { editedReads += 1 }
            return current
        }, onSuggestions: {
            if !$0.isEmpty {
                precondition(editedReads > 1, "The first observed edit must not publish immediately")
                precondition(editedAt.map { ProcessInfo.processInfo.systemUptime - $0 >= settleDuration } == true,
                             "Partial edits must settle before suggesting")
            }
            published = $0
        }, onInvalidated: { invalidations += 1 },
        interval: 5_000_000, duration: 5, settleDuration: settleDuration)
        // Await observation before editing: a delayed initial poll must not see
        // the corrected text as an unverified paste.
        try await waitUntil("the initial paste to be verified") { verifiedReads > 0 }
        editedAt = ProcessInfo.processInfo.systemUptime
        current = snapshot("Send this to Lumora.")
        try await waitUntil("the settled spelling suggestion") { published == [suggestion] }
        current = nil
        try await waitUntil("focus loss to invalidate observation") { invalidations == 1 }
        precondition(invalidations == 1, "Leaving the control must invalidate observation")
        monitor.stop()

        var wrongPasteSuggestions = 0
        monitor.start(capture: insertion, knownWords: [], read: { snapshot("Some unrelated field") },
                      onSuggestions: { _ in wrongPasteSuggestions += 1 }, onInvalidated: { invalidations += 1 },
                      interval: 5_000_000, duration: 5, settleDuration: 0)
        try await waitUntil("an unverified paste to invalidate observation") { invalidations == 2 }
        precondition(invalidations == 2 && wrongPasteSuggestions == 0,
                     "An unverified paste must never teach vocabulary")
        monitor.stop()

        monitor.start(capture: insertion, knownWords: [], read: { preconditionFailure("Canceled monitor read private text") },
                      onSuggestions: { _ in preconditionFailure("Canceled monitor published") },
                      onInvalidated: { preconditionFailure("Canceled monitor invalidated") }, interval: 5_000_000)
        monitor.stop()
        try await Task.sleep(nanoseconds: 20_000_000)

        monitor.start(capture: insertion, knownWords: [], read: { preconditionFailure("Expired monitor read private text") },
                      onSuggestions: { _ in preconditionFailure("Expired monitor published") },
                      onInvalidated: { preconditionFailure("Expired monitor invalidated") },
                      interval: 30_000_000, duration: 0.005)
        try await Task.sleep(nanoseconds: 50_000_000)
        monitor.stop()
        print("Correction learning passed: spelling filters, exact insertion region, Unicode, stable edits, focus loss, verified paste, cancellation.")
    }
}

import Foundation

public enum TranscriptionStyle: String, CaseIterable, Identifiable, Codable {
    case natural = "Natural (Direct, No Fillers)"
    case professional = "Professional (Polished & Formatted)"
    case raw = "Raw (Verbatim)"

    public var id: String { rawValue }
}

public final class TextCleaner {
    public static let shared = TextCleaner()

    public var customVocabulary: [String] = []

    private init() {}

    /// Main cleaning pipeline that transforms raw Whisper speech into clean, polished text
    public func clean(text: String, style: TranscriptionStyle = .natural) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return "" }

        if style == .raw {
            return applyCustomVocabulary(result)
        }

        // 1. Convert spoken punctuation
        result = convertSpokenPunctuation(result)

        // 2. Remove filler words (ums, ahs, etc.)
        result = removeFillerWords(result)

        // 3. Deduplicate stutters (e.g., "I I think" -> "I think")
        result = deduplicateStutters(result)

        // 4. Format spoken lists and bullet points
        result = formatSpokenLists(result)

        // 5. Clean up whitespace and typographical punctuation
        result = normalizePunctuationAndSpacing(result)

        // 6. Apply custom vocabulary replacements
        result = applyCustomVocabulary(result)

        // 7. Ensure initial capitalization
        if let first = result.first, first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        return result
    }

    /// Strips common vocal filler words: um, uh, ah, er, erm, you know, etc.
    private func removeFillerWords(_ text: String) -> String {
        let fillers = [
            ",?\\s*\\b(um+h*)\\b\\s*,?",
            ",?\\s*\\b(uh+h*)\\b\\s*,?",
            ",?\\s*\\b(ah+h*)\\b\\s*,?",
            ",?\\s*\\b(er+m*)\\b\\s*,?",
            ",?\\s*\\b(erm)\\b\\s*,?",
            ",?\\s*\\b(you know)\\b\\s*,?",
            ",?\\s*\\b(i mean)\\b\\s*,?",
            ",?\\s*\\b(sort of)\\b\\s*,?",
            ",?\\s*\\b(kind of)\\b\\s*,?"
        ]

        var cleaned = text
        for pattern in fillers {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: " ")
            }
        }

        // Clean up conversational "like" when used as filler (e.g., ", like, ")
        let conversationalLike = try? NSRegularExpression(pattern: "(,\\s*like,\\s*)|(^like,\\s*)", options: [.caseInsensitive])
        if let regex = conversationalLike {
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count), withTemplate: " ")
        }

        return cleaned
    }

    /// Cleans stutters and immediate word repetitions (e.g., "we we" -> "we", "I, I" -> "I")
    private func deduplicateStutters(_ text: String) -> String {
        let stutterPattern = "\\b([a-zA-Z]+)(?:,\\s*|\\s+)\\1\\b"
        guard let regex = try? NSRegularExpression(pattern: stutterPattern, options: [.caseInsensitive]) else {
            return text
        }

        var result = text
        var matched = true
        // Loop in case of triple stutters like "the the the"
        while matched {
            let range = NSRange(location: 0, length: result.utf16.count)
            if regex.firstMatch(in: result, options: [], range: range) != nil {
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            } else {
                matched = false
            }
        }
        return result
    }

    /// Converts spoken punctuation words into actual symbols
    private func convertSpokenPunctuation(_ text: String) -> String {
        var str = text

        let mappings: [(String, String)] = [
            ("\\bperiod\\b", "."),
            ("\\bfull stop\\b", "."),
            ("\\bcomma\\b", ","),
            ("\\bquestion mark\\b", "?"),
            ("\\bexclamation mark\\b", "!"),
            ("\\bexclamation point\\b", "!"),
            ("\\bcolon\\b", ":"),
            ("\\bsemicolon\\b", ";"),
            ("\\bnew line\\b", "\n"),
            ("\\bnew paragraph\\b", "\n\n")
        ]

        for (spoken, symbol) in mappings {
            if let regex = try? NSRegularExpression(pattern: spoken, options: [.caseInsensitive]) {
                str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: symbol)
            }
        }

        return str
    }

    /// Detects spoken lists (e.g., "bullet one ... bullet two ...") and formats into clean Markdown
    private func formatSpokenLists(_ text: String) -> String {
        var str = text

        // Bullets: "bullet point [something]" or "bullet [something]"
        let bulletPattern = "(?:\\b(?:bullet point|bullet)\\s*(?:one|two|three|four|five|[0-9]+)?\\b[:]?\\s*)"
        if let regex = try? NSRegularExpression(pattern: bulletPattern, options: [.caseInsensitive]) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: "\n• ")
        }

        return str
    }

    /// Cleans up doubled spaces, spaced punctuation like "word , word", and fixes capitalization
    private func normalizePunctuationAndSpacing(_ text: String) -> String {
        var str = text

        // Replace multiple spaces with a single space
        if let regex = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: " ")
        }

        // Remove duplicate commas: ",," -> ","
        if let regex = try? NSRegularExpression(pattern: ",\\s*,+", options: []) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: ",")
        }

        // Remove leading commas/spaces at beginning of sentence or line
        if let regex = try? NSRegularExpression(pattern: "^[\\s,;]+", options: []) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: "")
        }

        // Remove commas immediately before end-of-sentence punctuation: ",." -> "."
        if let regex = try? NSRegularExpression(pattern: ",\\s*([.!?])", options: []) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: "$1")
        }

        // Remove space before punctuation: "hello ." -> "hello."
        if let regex = try? NSRegularExpression(pattern: "\\s+([.,!?:;])", options: []) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: "$1")
        }

        // Capitalize after sentence-ending punctuation: ". word" -> ". Word"
        if let regex = try? NSRegularExpression(pattern: "([.!?]\\s+)([a-z])", options: []) {
            let nsStr = str as NSString
            let matches = regex.matches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count))
            for match in matches.reversed() {
                if match.numberOfRanges == 3 {
                    let punctRange = match.range(at: 1)
                    let charRange = match.range(at: 2)
                    let char = nsStr.substring(with: charRange).uppercased()
                    let fullRange = match.range
                    let replacement = nsStr.substring(with: punctRange) + char
                    str = (str as NSString).replacingCharacters(in: fullRange, with: replacement)
                }
            }
        }

        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces custom dictionary terms
    private func applyCustomVocabulary(_ text: String) -> String {
        var str = text
        for term in customVocabulary {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: trimmed) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: trimmed)
            }
        }
        return str
    }
}

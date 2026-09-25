import Foundation

public enum TranscriptionStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case natural = "Natural (Direct, No Fillers)"
    case professional = "Professional (Polished & Formatted)"
    case raw = "Raw (Verbatim)"

    public var id: String { rawValue }
}

public struct TextReplacement: Equatable, Sendable {
    public let phrase: String
    public let replacement: String

    public init(phrase: String, replacement: String) {
        self.phrase = phrase
        self.replacement = replacement
    }
}

public final class TextCleaner {
    public static let shared = TextCleaner()

    public var customVocabulary: [String] = []
    public var customReplacements: [TextReplacement] = []

    private init() {}

    /// Raw preserves the exact recognizer output, including whitespace. Natural
    /// removes clear disfluencies; Professional additionally interprets formatting commands.
    public func clean(
        text: String,
        style: TranscriptionStyle = .natural,
        vocabulary: [String]? = nil,
        replacements: [TextReplacement]? = nil
    ) -> String {
        if style == .raw { return text }

        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return "" }

        result = cleanScratchThatPhrases(result)
        result = removeFillerWords(result)
        result = deduplicateStutters(result)
        result = deduplicateRepetitivePhrases(result)
        result = normalizeWhitespace(result)

        if style == .professional {
            result = convertSpokenPunctuation(result)
            result = formatSpokenLists(result)
            result = normalizePunctuationAndSpacing(result)

            if let first = result.first, first.isLowercase {
                result = result.prefix(1).uppercased() + result.dropFirst()
            }
        }

        // Apply last so preferred casing such as "macOS" wins over sentence casing.
        result = applyCustomVocabulary(result, terms: vocabulary ?? customVocabulary)
        return applyTextReplacements(result, replacements: replacements ?? customReplacements)
    }

    /// Remove only unambiguous interjections. Preserve meaningful phrases, acronyms
    /// such as ER, and explicitly quoted words such as "um".
    private func removeFillerWords(_ text: String) -> String {
        let pattern = ",?[ \\t]*(?<![\\w'’\"“”-])(?:[Uu]m+|[Uu]h+|[Ee]rm+)(?![\\w'’\"“”-])[ \\t]*,?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard regex.firstMatch(in: text, range: range) != nil else { return text }
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        if cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?;:"))).isEmpty {
            return ""
        }
        return cleaned
    }

    /// Comma-marked pronoun/article restarts are safe to remove; repeated words
    /// such as "had had", "that that", and emphatic "No, no" can carry meaning.
    private func deduplicateStutters(_ text: String) -> String {
        let stutterPattern = "(?<![\\w'’-])(I|we|you|he|she|it|they|a|an|the),[ \\t]*\\1(?![\\w'’-])"
        guard let regex = try? NSRegularExpression(pattern: stutterPattern, options: [.caseInsensitive]) else {
            return text
        }

        var result = text
        var matched = true
        // Loop in case of several comma-marked restarts such as "I, I, I".
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

    /// Deduplicates repetitive sentence loops and multi-word phrase repetitions (Whisper hallucination loops)
    private func deduplicateRepetitivePhrases(_ text: String) -> String {
        var result = text

        // Require three complete occurrences so ordinary two-part emphasis survives.
        let sentencePattern = "(?<![\\w'’-])((?:[^.?!\\n]+?[.?!]))(?:\\s+\\1){2,}"
        if let regex = try? NSRegularExpression(pattern: sentencePattern, options: [.caseInsensitive]) {
            var matched = true
            while matched {
                let range = NSRange(location: 0, length: result.utf16.count)
                if regex.firstMatch(in: result, options: [], range: range) != nil {
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
                } else {
                    matched = false
                }
            }
        }

        // 2. Deduplicate repeated multi-word phrases (2 to 8 words) (e.g. "phrase phrase phrase" -> "phrase")
        // Match complete words in every occurrence, including the final repetition.
        // Otherwise "to go to Google" is mistaken for a repeated "to go".
        let phrasePattern = "(?<![\\w'’-])((?:[a-zA-Z0-9']+[-,\\s]+){1,8}[a-zA-Z0-9']+)(?![\\w'’-])(?:[,\\s]+\\1(?![\\w'’-])){2,}"
        if let regex = try? NSRegularExpression(pattern: phrasePattern, options: [.caseInsensitive]) {
            var matched = true
            while matched {
                let range = NSRange(location: 0, length: result.utf16.count)
                if regex.firstMatch(in: result, options: [], range: range) != nil {
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
                } else {
                    matched = false
                }
            }
        }

        return result
    }

    /// Converts only unambiguous dictation commands. Command words are common
    /// prose, so a formatting mode must not treat every occurrence as syntax.
    private func convertSpokenPunctuation(_ text: String) -> String {
        var str = text

        let mappings: [(String, String)] = [
            ("\\bfull stop\\b", "."),
            ("\\bquestion mark\\b", "?"),
            ("\\bexclamation point\\b", "!"),
            ("\\bexclamation mark\\b", "!"),
            ("\\bnew paragraph\\b", "\n\n"),
            ("\\bnew line\\b", "\n"),
            ("\\bsemicolon\\b", ";"),
            ("\\bperiod\\b", "."),
            ("\\bcomma\\b", ","),
            ("\\bcolon\\b", ":")
        ]

        for (spoken, symbol) in mappings {
            if let regex = try? NSRegularExpression(pattern: spoken, options: [.caseInsensitive]) {
                let matches = regex.matches(in: str, range: NSRange(location: 0, length: str.utf16.count))
                for match in matches.reversed() where isSpokenPunctuationCommand(in: str, range: match.range) {
                    str = (str as NSString).replacingCharacters(in: match.range, with: symbol)
                }
            }
        }

        return str
    }

    /// Dictation commands have a small set of deliberately explicit contexts:
    /// a trailing sentence command, a command chain, or "say <command>". Inline
    /// separators remain useful, but exclude article/definition contexts such as
    /// "a comma is punctuation" where the word is clearly being discussed.
    private func isSpokenPunctuationCommand(in text: String, range: NSRange) -> Bool {
        guard !isQuoted(text, at: range.location) else { return false }

        let words = adjacentWords(in: text, around: range)
        let before = words.before.lowercased()
        let after = words.after.lowercased()
        if before == "say" { return true }
        let articles = ["a", "an", "the", "this", "that"]
        // "the semicolon." and "a period." name a literal token even though
        // they happen to end a sentence.
        if articles.contains(before) { return false }

        let nsText = text as NSString
        let trailing = nsText.substring(from: range.location + range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trailing.isEmpty || trailing.allSatisfy({ ".!?;:".contains($0) }) { return true }

        // A chain makes the speaker's formatting intent explicit: "period new paragraph".
        if trailing.range(of: "^(?:period|full stop|comma|question mark|exclamation (?:mark|point)|colon|semicolon|new (?:line|paragraph)|bullet(?: point)?)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        let command = nsText.substring(with: range).lowercased()
        if command == "comma" || command == "colon" || command == "semicolon" {
            let definitionVerbs = ["is", "means", "mean", "denotes", "denote", "represents", "represent", "refers", "refer"]
            return !before.isEmpty && !articles.contains(before) && !definitionVerbs.contains(after)
        }

        if command == "new line" || command == "new paragraph" {
            return !before.isEmpty && !["a", "an", "the", "this", "that"].contains(before)
        }

        return false
    }

    private func adjacentWords(in text: String, around range: NSRange) -> (before: String, after: String) {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z]+") else { return ("", "") }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        let nsText = text as NSString
        let before = matches.last(where: { NSMaxRange($0.range) <= range.location })
            .map { nsText.substring(with: $0.range) } ?? ""
        let after = matches.first(where: { $0.range.location >= NSMaxRange(range) })
            .map { nsText.substring(with: $0.range) } ?? ""
        return (before, after)
    }

    private func isQuoted(_ text: String, at location: Int) -> Bool {
        let prefix = (text as NSString).substring(to: location)
        let straightQuoteCount = prefix.filter { $0 == "\"" }.count
        let openingCurlyQuoteCount = prefix.filter { $0 == "“" }.count
        let closingCurlyQuoteCount = prefix.filter { $0 == "”" }.count
        return straightQuoteCount % 2 == 1 || openingCurlyQuoteCount > closingCurlyQuoteCount
    }

    /// Detects spoken lists (e.g., "bullet one ... bullet two ...") and formats into clean Markdown
    private func formatSpokenLists(_ text: String) -> String {
        var str = text

        // Bare "bullet" is too easily an ordinary noun. Require an ordinal for
        // it, while allowing "bullet point" at a clause boundary as a heading.
        let bulletPattern = "\\b(?:bullet\\s+(?:one|two|three|four|five|[0-9]+)|bullet point(?:\\s+(?:one|two|three|four|five|[0-9]+))?)\\b[:]?\\s*"
        if let regex = try? NSRegularExpression(pattern: bulletPattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: str, range: NSRange(location: 0, length: str.utf16.count))
            for match in matches.reversed() where isSpokenListCommand(in: str, range: match.range) {
                str = (str as NSString).replacingCharacters(in: match.range, with: "\n• ")
            }
        }

        return str
    }

    private func isSpokenListCommand(in text: String, range: NSRange) -> Bool {
        guard !isQuoted(text, at: range.location) else { return false }
        let command = (text as NSString).substring(with: range).lowercased()
        if command.contains("bullet point") {
            let prefix = (text as NSString).substring(to: range.location)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty || prefix.last.map { ".!?:\\n".contains($0) } == true
        }
        return true // An ordinal makes a spoken bullet command explicit.
    }

    private func normalizeWhitespace(_ text: String) -> String {
        let regex = try? NSRegularExpression(pattern: "[ \\t]+")
        var normalized = regex?.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: " ") ?? text
        if let punctuationSpacing = try? NSRegularExpression(pattern: "[ \\t]+([.,!?:;])") {
            normalized = punctuationSpacing.stringByReplacingMatches(in: normalized, range: NSRange(location: 0, length: normalized.utf16.count), withTemplate: "$1")
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Professional formatting: normalize punctuation spacing and sentence casing.
    private func normalizePunctuationAndSpacing(_ text: String) -> String {
        var str = text

        // Replace multiple spaces with a single space
        if let regex = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: " ")
        }

        // Spoken line/paragraph and list commands can leave spaces around newlines.
        if let regex = try? NSRegularExpression(pattern: "[ \\t]*\\n[ \\t]*") {
            str = regex.stringByReplacingMatches(in: str, range: NSRange(location: 0, length: str.utf16.count), withTemplate: "\n")
        }
        if let regex = try? NSRegularExpression(pattern: "\\n{3,}") {
            str = regex.stringByReplacingMatches(in: str, range: NSRange(location: 0, length: str.utf16.count), withTemplate: "\n\n")
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

        // Capitalize sentences, new lines, and bullet items.
        if let regex = try? NSRegularExpression(pattern: "(^|[.!?]\\s+|\\n[ \\t]*|•[ \\t]+)([a-z])", options: []) {
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
    private func applyCustomVocabulary(_ text: String, terms: [String]) -> String {
        var str = text
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let pattern = "(?<!\\w)" + NSRegularExpression.escapedPattern(for: trimmed) + "(?!\\w)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                str = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count), withTemplate: NSRegularExpression.escapedTemplate(for: trimmed))
            }
        }
        return str
    }

    /// Checks if the text is a standalone undo/cancel command intended to trigger an undo keystroke
    public static func isStandaloneUndoCommand(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?:;,")))
        let lower = cleaned.lowercased()
        if lower == "scratch that" ||
           lower == "cancel that" ||
           lower == "undo that" ||
           lower == "undo" ||
           lower == "actually scratch that" ||
           lower == "scratch that please" ||
           lower == "cancel that please" {
            return true
        }
        let standalonePattern = "^(?:(?:actually|no|wait|please)\\s+)*\\b(?:scratch|cancel|undo)\\s+that\\b[.,;]?(?:[\\s,]+(?:(?:actually|no|wait|please)\\s+)*\\b(?:scratch|cancel|undo)\\s+that\\b[.,;]?)*$"
        if let regex = try? NSRegularExpression(pattern: standalonePattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            return regex.firstMatch(in: cleaned, options: [], range: range) != nil
        }
        return false
    }

    /// Mid-utterance voice correction:
    /// e.g. "meeting at four, scratch that, five" -> "meeting at five"
    /// e.g. "send to Alice, scratch that, send to Bob" -> "send to Bob"
    /// e.g. "we need five, scratch that, six servers" -> "we need six servers"
    private func cleanScratchThatPhrases(_ text: String) -> String {
        // If the entire utterance is a standalone voice undo command, preserve it so AppState can execute Cmd+Z
        if Self.isStandaloneUndoCommand(text) {
            return text
        }

        var str = text
        let pattern = "(?:,\\s*)?(?:\\b(?:actually|no|wait)\\s+)*\\b(?:scratch|cancel|undo)\\s+that\\b[.,;]?(?:[\\s,]+(?:(?:actually|no|wait)\\s+)*\\b(?:scratch|cancel|undo)\\s+that\\b[.,;]?)*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        var iterations = 0
        while iterations < 20 {
            iterations += 1
            let nsStr = str as NSString
            let matches = regex.matches(in: str, range: NSRange(location: 0, length: nsStr.length))
            guard let match = matches.reversed().first(where: { m in
                guard !isQuoted(str, at: m.range.location) else { return false }
                let matchedStr = nsStr.substring(with: m.range).lowercased()
                if matchedStr.contains("scratch") {
                    let words = adjacentWords(in: str, around: m.range)
                    let before = words.before.lowercased()
                    let nounArticles = ["a", "an", "the", "this", "that", "my", "your", "his", "her", "its", "our", "their"]
                    if nounArticles.contains(before) {
                        return false
                    }
                }
                return true
            }) else {
                break
            }

            let commandRange = match.range
            let rawPrefix = nsStr.substring(to: commandRange.location)
            let suffix = nsStr.substring(from: NSMaxRange(commandRange)).trimmingCharacters(in: .whitespacesAndNewlines)

            if rawPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                str = suffix
                continue
            }

            let prefixWords = rawPrefix.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).filter { !$0.isEmpty }
            let suffixWords = suffix.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).filter { !$0.isEmpty }

            var commonMatchIndex: Int? = nil
            if let firstSuffixWord = suffixWords.first {
                for (idx, word) in prefixWords.enumerated().reversed() {
                    if word.caseInsensitiveCompare(firstSuffixWord) == .orderedSame {
                        commonMatchIndex = idx
                        break
                    }
                }
            }

            var cutStartLocation = 0
            if let commonIdx = commonMatchIndex {
                let wordPattern = "\\b" + NSRegularExpression.escapedPattern(for: prefixWords[commonIdx]) + "\\b"
                if let wordRegex = try? NSRegularExpression(pattern: wordPattern, options: [.caseInsensitive]),
                   let wordMatch = wordRegex.matches(in: rawPrefix, range: NSRange(location: 0, length: rawPrefix.utf16.count)).last {
                    cutStartLocation = wordMatch.range.location
                }
            } else if let commaRange = rawPrefix.range(of: "[,;—\\-\\n][^,;—\\-\\n]*$", options: .regularExpression) {
                cutStartLocation = commaRange.lowerBound.utf16Offset(in: rawPrefix)
            } else {
                let wordMatches = (try? NSRegularExpression(pattern: "\\b[\\w'’-]+\\b"))?.matches(in: rawPrefix, range: NSRange(location: 0, length: rawPrefix.utf16.count)) ?? []
                if let lastWord = wordMatches.last {
                    cutStartLocation = lastWord.range.location
                } else {
                    cutStartLocation = 0
                }
            }

            let deleteRange = NSRange(location: cutStartLocation, length: NSMaxRange(commandRange) - cutStartLocation)
            str = (str as NSString).replacingCharacters(in: deleteRange, with: "")
        }
        return normalizeWhitespace(str)
    }

    /// Parses text replacement pairs from lines like "phrase -> replacement" or "phrase = replacement"
    public static func parseReplacements(from text: String) -> [TextReplacement] {
        var results: [TextReplacement] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            var phrase: String?
            var replacement: String?

            if let arrowRange = trimmed.range(of: "->") {
                phrase = String(trimmed[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                replacement = String(trimmed[arrowRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let arrowRange = trimmed.range(of: "=>") {
                phrase = String(trimmed[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                replacement = String(trimmed[arrowRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let eqRange = trimmed.range(of: "=") {
                phrase = String(trimmed[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                replacement = String(trimmed[eqRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let p = phrase, let r = replacement, !p.isEmpty {
                results.append(TextReplacement(phrase: p, replacement: r))
            }
        }
        return results
    }

    /// Applies custom text replacements / snippet expansions
    public func applyTextReplacements(_ text: String, replacements: [TextReplacement]) -> String {
        var str = text
        for item in replacements {
            let phrase = item.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            let pattern = "(?<![\\w'’-])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\w'’-])"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                str = regex.stringByReplacingMatches(
                    in: str,
                    options: [],
                    range: NSRange(location: 0, length: str.utf16.count),
                    withTemplate: NSRegularExpression.escapedTemplate(for: item.replacement)
                )
            }
        }
        return str
    }
}

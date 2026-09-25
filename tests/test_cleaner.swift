import Foundation

@main
struct TestRunner {
    static func main() {
        let cleaner = TextCleaner.shared
        cleaner.customVocabulary = ["Metatron", "M4 Max", "Wispr Flow", "macOS"]

        print("==================================================")
        print("  Running Metatron TextCleaner Verification Tests")
        print("==================================================\n")

        // Test 1: Remove clear interjections without stripping meaningful phrases.
        let input1 = "Um, uh, I think, like, we should, you know, deploy now period"
        let output1 = cleaner.clean(text: input1, style: .natural)
        print("Test 1 (Filler Words):")
        print("  Raw:      '\(input1)'")
        print("  Output:   '\(output1)'")
        assert(output1 == "I think, like, we should, you know, deploy now period", "Test 1 Failed: conservative filler cleanup changed wording: \(output1)")
        print("  ✓ PASSED\n")

        // Test 2: Stutters deduplication
        let input2 = "I, I think that the, the system is ready exclamation mark"
        let output2 = cleaner.clean(text: input2, style: .natural)
        print("Test 2 (Stutters):")
        print("  Raw:      '\(input2)'")
        print("  Output:   '\(output2)'")
        assert(output2 == "I think that the system is ready exclamation mark", "Test 2 Failed: comma-marked restarts not cleaned: \(output2)")
        print("  ✓ PASSED\n")

        // Test 3: Spoken lists / bullets
        let input3 = "bullet one first feature bullet two second feature period"
        let output3 = cleaner.clean(text: input3, style: .professional)
        print("Test 3 (Bullets & Lists):")
        print("  Raw:      '\(input3)'")
        print("  Output:   '\(output3)'")
        assert(output3 == "• First feature\n• Second feature.", "Test 3 Failed: bullet points not formatted: \(output3)")
        print("  ✓ PASSED\n")

        // Test 4: Custom Vocabulary
        let input4 = "i am running metatron on my m4 max on macos period"
        let output4 = cleaner.clean(text: input4, style: .natural)
        print("Test 4 (Custom Vocabulary):")
        print("  Raw:      '\(input4)'")
        print("  Output:   '\(output4)'")
        assert(output4 == "i am running Metatron on my M4 Max on macOS period", "Test 4 Failed: custom vocabulary capitalization failed: \(output4)")
        print("  ✓ PASSED\n")

        // Test 5: Whisper Hallucination / Repetition Loop Deduplication
        let input5 = "See, there's one thing that's anything that's true for me. But it's something that's true for me. But it's something that's true for me. But it's something that's true for me. But it's something that's true for me. What's true for me?"
        let output5 = cleaner.clean(text: input5, style: .natural)
        print("Test 5 (Repetition Loops):")
        print("  Raw:      '\(input5)'")
        print("  Output:   '\(output5)'")
        let occurrences = output5.components(separatedBy: "But it's something that's true for me.").count - 1
        assert(occurrences == 1, "Test 5 Failed: repetition loop was not collapsed to 1 occurrence (found \(occurrences))")
        print("  ✓ PASSED\n")

        // Test 6: Repetition detection must not match prefixes or suffixes of words.
        let unchangedPhrases = [
            "We need to go to Google.",
            "Thank you thank yourself.",
            "To replace it, place it here.",
            "Tell them we can we can't attend.",
            "Tell them we can we can’t attend.",
            "We are in New York New Yorker territory.",
            "We went to the theater to the theatergoers.",
            "Do you do your homework?",
            "Can you can your own tomatoes?",
            "First undo it, do it again.",
            "Forecast. Cast.",
            "Play-play. Play.",
            "We’ll go ll go home.",
            "Go now go now's turn.",
            "Go now go now’s turn.",
            "Go now go now-go later.",
            // Three occurrences still must not match a word prefix/suffix.
            "We need to go to go to Google.",
            "First undo it, do it, do it again.",
            "Forecast. Cast. Cast.",
            "Play-play. Play. Play.",
            "Go now go now go now's turn.",
            "Go now go now go now’s turn.",
            "Go now go now go now-go later.",
            // Grammatical repetition, emphasis, and lexical filler phrases carry meaning.
            "Do you know where it is?",
            "What kind of music do you like?",
            "This is the sort of result I mean.",
            "This is ER protocol.",
            "She had had enough, and I know that that matters.",
            "No, no, this is very very important.",
            "Thank you, thank you.",
            "Repeat this. Repeat this.",
            "Ah, yes. He said \"um\", not \"uh\"."
        ]
        for style in [TranscriptionStyle.natural, .professional] {
            for input in unchangedPhrases {
                let output = cleaner.clean(text: input, style: style)
                assert(output == input, "Test 6 Failed: changed legitimate text '\(input)' to '\(output)'")
            }
        }
        print("Test 6 (Preserve Whole Words): ✓ PASSED\n")

        // Test 7: Boundary protection must preserve the existing phrase-loop cleanup.
        let repeatedPhrases = [
            ("We should ship we should ship we should ship today.", "We should ship today."),
            ("Thank you, thank you, thank you.", "Thank you."),
            ("We need to go to go to go to Google.", "We need to go to Google."),
            ("Hello world, hello world, hello world.", "Hello world."),
            ("Don't stop don't stop don't stop.", "Don't stop."),
            ("Repeat this. Repeat this. Repeat this.", "Repeat this.")
        ]
        for (input, expected) in repeatedPhrases {
            let output = cleaner.clean(text: input, style: .natural)
            assert(output == expected, "Test 7 Failed: expected '\(expected)', got '\(output)'")
        }
        print("Test 7 (Whole Phrase Repetitions): ✓ PASSED\n")

        // Test 8: Raw is an exact pass-through, including whitespace and vocabulary casing.
        let rawInputs = [
            " \tmetatron  um I I period\n\n",
            "I, I said comma new line bullet one.",
            "Repeat this. Repeat this. Repeat this.",
            "macos metatron m4 max",
            "\n \t\n",
            ""
        ]
        for input in rawInputs {
            assert(cleaner.clean(text: input, style: .raw) == input, "Test 8 Failed: Raw changed recognizer output")
        }
        print("Test 8 (Exact Raw Output): ✓ PASSED\n")

        // Test 9: Natural preserves literal command words and casing; Professional opts into formatting.
        let literal = "the evaluation period ends tomorrow. A bullet train uses a new line."
        assert(cleaner.clean(text: literal, style: .natural) == literal, "Test 9 Failed: Natural interpreted literal command words")
        let commands = "hello comma world period new paragraph bullet one next step bullet two last step period"
        assert(cleaner.clean(text: commands, style: .natural) == commands, "Test 9 Failed: Natural changed spoken wording")
        let formatted = cleaner.clean(text: commands, style: .professional)
        assert(formatted == "Hello, world.\n\n• Next step\n• Last step.", "Test 9 Failed: Professional formatting incorrect: \(formatted)")
        assert(cleaner.clean(text: "hello. another sentence.", style: .natural) == "hello. another sentence.", "Test 9 Failed: Natural changed sentence casing")
        assert(cleaner.clean(text: "hello. another sentence.", style: .professional) == "Hello. Another sentence.", "Test 9 Failed: Professional did not capitalize sentences")
        assert(cleaner.clean(text: "um, uh.", style: .natural).isEmpty, "Test 9 Failed: filler-only speech left punctuation")
        print("Test 9 (Distinct Natural and Professional Styles): ✓ PASSED\n")

        // Test 10: Vocabulary is literal replacement text, including symbols, and wins over casing.
        cleaner.customVocabulary = ["macOS", "C++", "A$AP", "foo$1", #"a\b"#]
        let technicalTerms = #"c++ a$ap foo$1 a\b"#
        let expectedTerms = #"C++ A$AP foo$1 a\b"#
        for style in [TranscriptionStyle.natural, .professional] {
            let output = cleaner.clean(text: technicalTerms, style: style)
            assert(output == expectedTerms, "Test 10 Failed: custom terms were interpreted as replacement templates: \(output)")
        }
        assert(cleaner.clean(text: "macos is ready period", style: .professional) == "macOS is ready.", "Test 10 Failed: sentence casing overrode custom vocabulary")
        assert(cleaner.clean(text: technicalTerms, style: .raw) == technicalTerms, "Test 10 Failed: Raw applied custom vocabulary")
        let savedVocabulary = cleaner.customVocabulary
        assert(cleaner.clean(text: "macos metatron", style: .natural, vocabulary: ["Metatron"]) == "macos Metatron", "Test 10 Failed: current global vocabulary overrode the per-request snapshot")
        assert(cleaner.customVocabulary == savedVocabulary, "Test 10 Failed: per-request vocabulary mutated shared settings")
        assert(cleaner.clean(text: "macos metatron", style: .raw, vocabulary: ["Metatron"]) == "macos metatron", "Test 10 Failed: Raw applied per-request vocabulary")
        print("Test 10 (Literal Custom Vocabulary): ✓ PASSED\n")

        // Test 11: Professional only recognizes spoken commands in explicit contexts.
        let ordinaryProse = [
            "The evaluation period ends tomorrow.",
            "The bullet train arrives at noon.",
            "A comma is punctuation.",
            "She wrote about the colon and the semicolon.",
            "He quoted \"period\" and \"bullet one\" in the guide."
        ]
        for input in ordinaryProse {
            assert(cleaner.clean(text: input, style: .professional) == input, "Test 11 Failed: Professional interpreted literal prose '\(input)'")
        }
        assert(cleaner.clean(text: "this sentence ends period", style: .professional) == "This sentence ends.", "Test 11 Failed: trailing period command was lost")
        assert(cleaner.clean(text: "say period", style: .professional) == "Say.", "Test 11 Failed: say-period command was lost")
        assert(cleaner.clean(text: "hello comma world period new paragraph bullet one first task bullet two second task period", style: .professional) == "Hello, world.\n\n• First task\n• Second task.", "Test 11 Failed: explicit command chain was not formatted")
        print("Test 11 (Professional Command Context): ✓ PASSED\n")

        // Test 12: Custom Text Replacements / Snippet Macros
        let sampleReplacements = """
        my email -> test@example.com
        cal link => https://example.com/calendar
        shrug = ¯\\_(ツ)_/¯
        """
        let parsed = TextCleaner.parseReplacements(from: sampleReplacements)
        assert(parsed.count == 3, "Test 12 Failed: did not parse 3 replacements")
        cleaner.customReplacements = parsed

        let repInput = "please send an email to my email period"
        assert(cleaner.clean(text: repInput, style: .professional) == "Please send an email to test@example.com.", "Test 12 Failed: snippet replacement not applied: \(cleaner.clean(text: repInput, style: .professional))")
        assert(cleaner.clean(text: "here is my cal link", style: .natural) == "here is my https://example.com/calendar", "Test 12 Failed: snippet replacement not applied in natural")
        assert(cleaner.clean(text: repInput, style: .raw) == repInput, "Test 12 Failed: raw applied snippet replacements")
        cleaner.customReplacements = []
        print("Test 12 (Custom Text Replacements / Snippets): ✓ PASSED\n")

        // Test 13: "Scratch That" / Mid-utterance voice correction
        let scratch1 = "meeting at four, scratch that, five"
        assert(cleaner.clean(text: scratch1, style: .natural) == "meeting at five", "Test 13 Failed: scratch that word correction: '\(cleaner.clean(text: scratch1, style: .natural))'")

        let scratch2 = "send to Alice, scratch that, send to Bob"
        assert(cleaner.clean(text: scratch2, style: .natural) == "send to Bob", "Test 13 Failed: scratch that phrase repetition: '\(cleaner.clean(text: scratch2, style: .natural))'")

        let scratch3 = "we need red, cancel that, green"
        assert(cleaner.clean(text: scratch3, style: .natural) == "we need green", "Test 13 Failed: cancel that correction: '\(cleaner.clean(text: scratch3, style: .natural))'")

        let scratchMulti1 = "apple, scratch that, banana, scratch that, orange"
        assert(cleaner.clean(text: scratchMulti1, style: .natural) == "orange", "Test 13 Failed: multi scratch that: '\(cleaner.clean(text: scratchMulti1, style: .natural))'")

        let scratchMulti2 = "hello, scratch that, world, scratch that, foo, scratch that, bar"
        assert(cleaner.clean(text: scratchMulti2, style: .natural) == "bar", "Test 13 Failed: sequential scratch that: '\(cleaner.clean(text: scratchMulti2, style: .natural))'")

        let scratchChained = "meeting at four, scratch that, cancel that, five"
        assert(cleaner.clean(text: scratchChained, style: .natural) == "meeting at five", "Test 13 Failed: chained scratch that: '\(cleaner.clean(text: scratchChained, style: .natural))'")

        let nounPreserve = "The cat has a scratch that hurts."
        assert(cleaner.clean(text: nounPreserve, style: .natural) == nounPreserve, "Test 13 Failed: noun 'a scratch that' was stripped")

        let standaloneUndo = "scratch that"
        assert(cleaner.clean(text: standaloneUndo, style: .natural) == "scratch that", "Test 13 Failed: standalone scratch that should be preserved for undo")
        assert(TextCleaner.isStandaloneUndoCommand("scratch that"))
        assert(TextCleaner.isStandaloneUndoCommand("cancel that."))
        assert(TextCleaner.isStandaloneUndoCommand("undo that"))
        assert(!TextCleaner.isStandaloneUndoCommand(nounPreserve))
        print("Test 13 (Scratch That Voice Correction): ✓ PASSED\n")

        print("==================================================")
        print("  All Metatron TextCleaner Tests PASSED! (13/13)")
        print("==================================================")
    }
}

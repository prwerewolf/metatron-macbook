import Foundation

@main
struct TestRunner {
    static func main() {
        let cleaner = TextCleaner.shared
        cleaner.customVocabulary = ["Metatron", "M4 Max", "Wispr Flow", "macOS"]

        print("==================================================")
        print("  Running Metatron TextCleaner Verification Tests")
        print("==================================================\n")

        // Test 1: Filler words removal (ums, ahs, like, you know)
        let input1 = "Um, uh, I think, like, we should, you know, deploy now period"
        let output1 = cleaner.clean(text: input1, style: .natural)
        print("Test 1 (Filler Words):")
        print("  Raw:      '\(input1)'")
        print("  Output:   '\(output1)'")
        assert(!output1.contains("Um") && !output1.contains("uh") && !output1.contains("you know"), "Test 1 Failed: filler words not removed")
        print("  ✓ PASSED\n")

        // Test 2: Stutters deduplication
        let input2 = "I, I think that the the system is ready exclamation mark"
        let output2 = cleaner.clean(text: input2, style: .natural)
        print("Test 2 (Stutters):")
        print("  Raw:      '\(input2)'")
        print("  Output:   '\(output2)'")
        assert(!output2.contains("I, I") && !output2.contains("the the"), "Test 2 Failed: stutters not deduplicated")
        print("  ✓ PASSED\n")

        // Test 3: Spoken lists / bullets
        let input3 = "bullet one first feature bullet two second feature period"
        let output3 = cleaner.clean(text: input3, style: .professional)
        print("Test 3 (Bullets & Lists):")
        print("  Raw:      '\(input3)'")
        print("  Output:   '\(output3)'")
        assert(output3.contains("•"), "Test 3 Failed: bullet points not formatted")
        print("  ✓ PASSED\n")

        // Test 4: Custom Vocabulary
        let input4 = "i am running metatron on my m4 max on macos period"
        let output4 = cleaner.clean(text: input4, style: .natural)
        print("Test 4 (Custom Vocabulary):")
        print("  Raw:      '\(input4)'")
        print("  Output:   '\(output4)'")
        assert(output4.contains("Metatron") && output4.contains("M4 Max") && output4.contains("macOS"), "Test 4 Failed: custom vocabulary capitalization failed")
        print("  ✓ PASSED\n")

        print("==================================================")
        print("  All Metatron TextCleaner Tests PASSED! (4/4)")
        print("==================================================")
    }
}

# Metatron Project Status & Handoff

## Where We Stand

Metatron is a 100% offline, local-first push-to-talk speech dictation app for Apple Silicon running macOS 13+. All speech recognition, text cleanup, and system integrations run strictly on-device with zero internet connectivity.

### Recently Completed & Verified

1. **Launch at Login (`SMAppService`)**:
   - Native macOS 13+ ServiceManagement integration via `LaunchAtLogin.swift`.
   - General Settings toggle seamlessly registers/unregisters `Metatron.app` in macOS Login Items.

2. **Custom Text Replacements / Voice Snippet Macros**:
   - Expansion engine in `TextCleaner.swift` supporting `phrase -> replacement` or `phrase = replacement`.
   - Applied in Natural and Professional styles with word-boundary matching and case-insensitive recognition.
   - User-configurable via dedicated editor in Style Settings tab with live `UserDefaults` persistence.

3. **Smart Prefix Spacing**:
   - Caret inspection via `InsertionTarget.precedingCharacter()` using macOS Accessibility API.
   - Fallback consecutive dictation heuristic: automatically prepends space if dictating into the same app/PID within 45 seconds without trailing whitespace.
   - Punctuation guard ensures spaces are never prepended before punctuation, quotes, brackets, or newlines.

4. **"Scratch That" Voice Corrections & Standalone Undo**:
   - Mid-utterance phrase correction in `TextCleaner.swift` automatically cuts abandoned words/clauses before `"scratch that"` / `"cancel that"`.
   - Standalone voice undo: Speaking *"scratch that"*, *"cancel that"*, or *"undo that"* alone synthesizes a native `Cmd+Z` keystroke via `TextInserter.sendUndoKeystroke()`, displays `"Undone!"` on the pill, and avoids inserting text.

5. **Accidental Click Guard**:
   - Silently drops recordings under 0.25 seconds in `AppState.stopRecordingAndTranscribe()`.
   - Cleans up temporary audio files and resets state to `"Ready"` without error chimes.

6. **Portable Daemon Path Resolution**:
   - Removed all hardcoded personal paths in `LocalDaemonClient.swift` and tests.
   - Dynamically discovers daemon and script locations relative to the app bundle or repository root for multi-Mac compatibility.

### Verification Status
- All test suites passing (`make test`): 13/13 TextCleaner tests, 29 hotkey tests, 10 insertion destination tests, synthetic audio tests, AppState regression suite, and 35 Python daemon unit tests.
- App bundle builds and codesigns cleanly (`make build`).

---

## What's Left & Future Roadmap

- Additional specialized punctuation / code snippet modes if requested.
- Extended multi-monitor edge-docking customization for unconventional display layouts.
- Performance profiling on M-series chips for larger vocabulary lists (>1,000 terms).

---

## Architectural Context & Gotchas

- **Strict Offline Enforcement**: The Python daemon sets `sys.addaudithook(deny_network_access)` to block socket connections and DNS lookups at the interpreter level. Any feature or dependency that introduces network calls will be blocked and will fail tests.
- **Standalone Undo vs. Mid-Utterance**: `TextCleaner.isStandaloneUndoCommand` preserves bare undo commands so `AppState` can inspect them before text insertion and trigger `Cmd+Z`. Mid-utterance commands are handled separately in `cleanScratchThatPhrases`.
- **Accessibility Permissions**: Virtual keystroke insertion (`Cmd+V`, `Cmd+Z`) and focused element inspection require macOS Accessibility permissions. If ungranted, clipboard fallback is used.

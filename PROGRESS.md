# Press To Write Project Status & Handoff

## Where We Stand

Press To Write is a local-first push-to-talk speech dictation app for Apple Silicon running macOS 14+. One-time setup installs dependencies and a model; speech recognition, text cleanup, and system integrations then run on-device. The pinned MLX runtime determines the supported macOS version.

### Recently Completed & Verified

**Community sharing preparation (October 7, 2026):**

- Replaced personal fixtures and machine-specific examples with synthetic values.
- Added the Unmodified Use License: free use of official unmodified versions,
  including internal business use; modification, resale, and redistribution
  require written permission. Third-party dependencies retain their own licenses.
- Added exclusions for private data, models, signing material, local editor and
  agent settings, and distribution artifacts. Added staged-file and full-history
  privacy checks, local commit/push hooks, a neutral commit wrapper, and CI.
- Added pinned direct runtime dependencies and first-run instructions. Setup
  creates the Python environment directly in Application Support, supports cache
  environment variables, and has an explicit offline mode. MLX requires macOS 14+.
- Building packages the daemon without replacing a user's running runtime.
- Isolated audio recovery tests from real Application Support data.
- Verified all Swift regression suites, 54 Python tests, the source privacy
  check, and a signed release build. Fresh online dependency/model installation
  has not been exercised on a second Mac; model setup is covered with mocked
  downloads and temporary caches.
- Before changing a previously private repository to public, separately verify
  retained pull-request refs and cached old commits. A branch rewrite alone does
  not remove those GitHub copies. See PRIVACY.md and MAINTAINING.md.

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

7. **Speech Transcription Without `ffmpeg`**:
   - Fixed Fn dictation failing after release when the GUI-launched daemon could not find Homebrew's `ffmpeg`.
   - The daemon validates and decodes Metatron's 16 kHz mono PCM16 WAV using Python `wave` and NumPy, then passes float32 samples to MLX Whisper.
   - Added a regression test for sample scaling, array input to MLX, and temporary recording cleanup.

8. **Comprehensive Codebase Hardening & Bug Fixes**:
   - **Bounded Accessibility IPC**: Added a 200ms timeout (`AXUIElementSetMessagingTimeout(element, 0.2)`) on cursor context queries in `InsertionTarget.swift` to prevent main-thread beachballs on sluggish target applications.
   - **Empty Field Leading Space Suppression**: Introduced typed `CursorContext` (`.character`, `.startOfText`, `.unavailable`) in `InsertionTarget.swift` and `AppState.swift` to prevent erroneous leading spaces when dictating at cursor position 0 in empty fields.
   - **Sticky Modifier Key Recovery**: Added `resetModifierStates()` in `HotkeyManager.swift` and invoked it on cancellation, click-guard drops, audio recording errors, and `stopListening()` to eliminate latched modifier states.
   - **Socket `EINTR` Interruption Safety**: Guarded `write()` and `read()` loops in `LocalDaemonClient.swift` against POSIX signal interruptions (`EINTR`).
   - **Dynamic Excision & Chained Undo Correction**: Replaced static match iteration with dynamic live-string re-matching in `TextCleaner.swift` and added support for chained undo phrases (`"meeting at four, scratch that, cancel that, five"` -> `"meeting at five"`), while preserving noun phrases (`"a scratch that hurts"`).
   - **Multi-Display Topology Auto-Recovery**: Added an observer for `NSApplication.didChangeScreenParametersNotification` in `FloatingPillWindow.swift` to automatically re-anchor the floating pill to the main screen if an external display is disconnected.

9. **Multi-Device Fallback Cascade (`AudioInputSelection.candidates`)**:
   - Dynamic prioritized candidate resolution (`preferred -> built-in -> system default -> AUHAL default`).
   - Prevents capture failures and freezes when an input device (e.g., iPhone Continuity Camera mic) enters an invalid or non-responsive AUHAL state (`Input:No | Output:No`, error `1852797029`).

10. **Unconditional Hotkey Modifier Unlatching (`HotkeyManager.swift`)**:
   - Modifier releases and unexpected `flagsChanged` events unconditionally reset `isFnDown`, `isRightOptionDown`, and `isRightCommandDown`.
   - `startRecording()` and `onRecordingError` explicitly call `resetModifierStates()` to guarantee modifier flags can never stay latched after an error.

11. **Persistent Audio Rescue System & Menu Bar Recovery (`RescueAudioController.swift`)**:
   - Raw recorded audio is persisted to `~/Library/Application Support/Metatron/last_recording.wav` with a JSON metadata manifest.
   - Speech audio is never discarded on device errors or transcription timeouts.
   - Added **"Transcribe Last Recording"** menu bar status item with duration readout (`AppDelegate.swift`), enabling instant one-click recovery to the clipboard at any time.

12. **Zero-Orphan Process Watchdog (`whisper_daemon.py` & `LocalDaemonClient.swift`)**:
   - `METATRON_PARENT_PID` environment propagation to spawned daemons.
   - Background POSIX watchdog thread in Python terminates the daemon within 1 second if the parent app exits or is force-quit.
   - Explicit `terminateLaunchedDaemon()` hook in `AppDelegate.applicationWillTerminate`.

13. **macOS TCC Sandbox Immunity via Application Support Runtime**:
   - Resolved the issue where launching `Metatron.app` outside a terminal session (e.g., from Finder, Dock, Spotlight, or Login Items) failed to start the speech daemon with `PermissionError: [Errno 1] Operation not permitted: '.../.venv/pyvenv.cfg'` due to macOS TCC privacy protection on `~/Documents`.
   - Mirrored the Python runtime virtual environment to `~/Library/Application Support/Metatron/venv`, which macOS always permits apps to access without prompt or restriction.
   - Updated `LocalDaemonClient.swift` to automatically sync `whisper_daemon.py` to Application Support and prioritize the Application Support Python environment in `candidatePythonPaths`.
   - Updated `scripts/build_app.sh` and `scripts/setup_mac.sh` to stage and maintain the Application Support environment automatically.
   - Added `NSDocumentsFolderUsageDescription` in `Resources/Info.plist` for defense-in-depth.

14. **Full Rebrand to Press To Write (`Press To Write.app`)**:
   - Rebranded the entire application from Metatron to **Press To Write** across native Swift sources, app bundle (`Press To Write.app`), bundle identifier (`com.presstowrite.mac`), Swift package target (`PressToWrite`), and local codesigning identity (`Press To Write Development`).
   - Cleaned up legacy prototype processes (`PushTalk`), reset TCC permissions for `com.presstowrite.mac`, and unhooked legacy Fn key interceptors.
   - Updated all user-facing UI: Menu Bar ("Press To Write"), Floating Pill ("Press To Write", adjusted horizontal pill width to 126pt), Settings, History, and Permissions windows.
   - Modernized offline model downloader in `scripts/setup_mac.sh` to use `huggingface_hub.snapshot_download` instead of deprecated `huggingface_hub.cli.core`.
   - Updated local IPC socket path to `/tmp/presstowrite.sock` with dual environment variable support (`PRESSTOWRITE_MODEL_DIR` / `METATRON_MODEL_DIR`, `PRESSTOWRITE_PYTHON` / `METATRON_PYTHON`).
   - Re-verified full test suite and clean release build.

### Verification Status
- All test suites passing (`make test`), including 13 cleaner test groups, 13 insertion destination tests, 35 hotkey tests, 14 microphone selection tests, 14 audio conversion/configuration tests, 9 pill display tests, app state rescue tests, and 36 Python daemon unit tests (100% pass rate).
- App bundle cleanly compiles, packages, and codesigns with persistent identity 'Press To Write Development' (`make build`).
- Live app verified running (`Press To Write.app` / `PressToWrite`, PID `10617`) with offline daemon listening on `/tmp/presstowrite.sock`.

---

## What's Left & Future Roadmap

- Additional specialized punctuation / code snippet modes if requested.
- Extended multi-monitor edge-docking customization for unconventional display layouts.
- Performance profiling on M-series chips for larger vocabulary lists (>1,000 terms).

---

## Architectural Context & Gotchas

- **Strict Offline Enforcement**: The Python daemon sets `sys.addaudithook(deny_network_access)` to block socket connections and DNS lookups at the interpreter level. Any feature or dependency that introduces network calls will be blocked and will fail tests.
- **Audio Rescue Invariant**: Speech audio is saved to `RescueAudioController` whenever recording finishes or encounters an error after >= 1.0s of speech. The temporary file in `/tmp` is removed to prevent disk leaks while preserving user voice data in Application Support.
- **Standalone Undo vs. Mid-Utterance**: `TextCleaner.isStandaloneUndoCommand` preserves bare undo commands so `AppState` can inspect them before text insertion and trigger `Cmd+Z`. Mid-utterance commands are handled separately in `cleanScratchThatPhrases`.
- **Accessibility Permissions**: Virtual keystroke insertion (`Cmd+V`, `Cmd+Z`) and focused element inspection require macOS Accessibility permissions. If ungranted, clipboard fallback is used.
- **GUI Process `PATH`**: Apps launched by Finder may not inherit Homebrew paths. Pass decoded NumPy audio to MLX Whisper, rather than a WAV filename that would make the dependency call `ffmpeg`. Metatron's PCM16 WAV format is validated before inference.

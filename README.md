# Press To Write — Local Dictation for macOS

Native push-to-talk dictation for Apple Silicon. Speech recognition, vocabulary hints, and text cleanup run on your Mac. Cloud transcription, model downloads, and online model checks are disabled.

## Daily use

1. Wait for the local speech engine to show **Ready** in Settings → Speech Engine.
2. Hold **Fn / Globe**, speak, and release to transcribe. Alternative hotkeys and toggle mode are available in Settings.
3. Press **Escape** to discard a recording or cancel a pending dictation.
4. Text is inserted only if the original app and focused control still own the cursor. If focus changes, your result remains available through **Copy Last Dictation** in the menu bar or the pill's Copy button.

The compact pill can be dragged to screen edges and remembers its monitor across restarts. Its waveform shows recording activity; loading and error states have explanatory tooltips.

## Settings

- **Launch at Login:** Option in Settings → General to start Press To Write automatically on macOS login via `SMAppService`.
- **Microphone:** Choose the system default or a specific input. The level-meter test runs only while enabled, saves no recording, and stops when Settings closes or dictation begins. An unavailable saved microphone produces a clear error instead of silently switching inputs.
- **Custom vocabulary & Text Replacements:** Comma-separated vocabulary terms guide local recognition. The Text Replacements editor in Settings → Style allows defining voice snippet macros (`phrase -> replacement` or `phrase = replacement`, e.g., `my email -> test@example.com`).
- **Voice Correction & Undo ("Scratch That"):** Mid-sentence corrections like *"meeting at four, scratch that, five"* replace the abandoned phrase. Speaking *"scratch that"*, *"cancel that"*, or *"undo that"* as a standalone utterance triggers a native `Cmd+Z` undo keystroke with visual feedback on the pill.
- **Smart Prefix Spacing:** Consecutive dictations into the same app/control automatically prepend a space, using accessibility cursor inspection with a 45-second fallback for smooth multi-sentence dictation.
- **Audio Rescue & Recovery:** If an audio device disconnects mid-speech or an unexpected engine error occurs, Press To Write preserves the raw audio recording in `~/Library/Application Support/Press To Write/last_recording.wav`. The **Transcribe Last Recording** menu item in the macOS status bar allows immediate one-click recovery of the dictated speech directly to your clipboard.
- **Accidental Click Guard:** Hotkey presses shorter than 0.25 seconds are silently discarded without transcription or error chimes.
- **Natural:** Conservative removal of clear hesitations and obvious repetition loops, preserving wording, casing, and literal punctuation words.
- **Professional:** Natural cleanup plus spoken punctuation (`comma`, `period`, `new line`, `new paragraph`), bullet commands, and sentence capitalization. Choose Natural for literal uses of those command words.
- **Raw:** The recognizer's output without text cleanup, vocabulary replacements, or formatting. Vocabulary still guides recognition itself.
- **Clipboard:** Existing transient clipboard markers and automatic restoration are used for insertion. “Keep Speech on System Clipboard” retains copied speech when enabled. If Accessibility is unavailable, the existing copy-to-clipboard fallback remains available.
- **History:** Session Only is the default. Incognito disables history; rolling limits keep the last 10 or 50 entries in memory. History is not persisted across app restarts.

Temporary recording files in `/tmp` are removed after processing, while the most recent recording is securely archived in Application Support for recovery. Audio tests only compute levels in memory. Text deliberately copied or inserted into another application follows that application's own storage/sync behavior.

## Offline model setup

Press To Write uses the Python environment at `.venv` (mirrored to `~/Library/Application Support/Press To Write/venv`) and already-downloaded MLX Whisper files. The engine loads and warms the actual model before reporting Ready.

Press To Write records 16 kHz mono PCM16 WAV. The local daemon decodes that format directly with Python and NumPy before recognition, so `ffmpeg` is not needed at runtime. This also works when a Finder-launched app does not inherit Homebrew's `PATH`.

The daemon looks in the local Hugging Face cache for `mlx-community/whisper-large-v3-turbo`; an already-cached `mlx-community/whisper-base.en` can serve as a startup fallback. It reads cache directories directly and never calls an online model resolver. Standard `HF_HOME`, `HF_HUB_CACHE`, and `XDG_CACHE_HOME` cache locations are supported.

You can instead set `PRESSTOWRITE_MODEL_DIR` (or `METATRON_MODEL_DIR`) to an existing local model directory containing `config.json` and `weights.safetensors` or `weights.npz` when launching the app/daemon. Missing model files produce an unavailable message; they are never downloaded automatically. Python network sockets and DNS lookups are blocked in the daemon in addition to offline dependency flags.

## Build, test, and launch

```bash
make test   # Synthetic/mocked regression tests; no microphone or network access
make build  # Build and sign Press To Write.app
make run    # Restart the app and local daemon
```

`make run` uses the existing app bundle; run `make build` first after changing source. Restart both the app and daemon after an update so they use the same offline protocol.

## macOS permissions

- **Microphone:** Needed for dictation and the explicitly started input test.
- **Accessibility:** Needed for global hotkeys, checking the insertion destination, and pasting into the focused application.
- In **System Settings → Keyboard**, set **“Press 🌐 key to:” → “Do Nothing”** to prevent the system emoji window from opening when using Fn.

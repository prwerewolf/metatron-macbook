# Metatron — Local Dictation for macOS

Native push-to-talk dictation for Apple Silicon. Speech recognition, vocabulary hints, and text cleanup run on your Mac. Cloud transcription, model downloads, and online model checks are disabled.

## Daily use

1. Wait for the local speech engine to show **Ready** in Settings → Speech Engine.
2. Hold **Fn / Globe**, speak, and release to transcribe. Alternative hotkeys and toggle mode are available in Settings.
3. Press **Escape** to discard a recording or cancel a pending dictation.
4. Text is inserted only if the original app and focused control still own the cursor. If focus changes, your result remains available through **Copy Last Dictation** in the menu bar or the pill's Copy button.

The compact pill can be dragged to screen edges and remembers its monitor across restarts. Its waveform shows recording activity; loading and error states have explanatory tooltips.

## Settings

- **Microphone:** Choose the system default or a specific input. The level-meter test runs only while enabled, saves no recording, and stops when Settings closes or dictation begins. An unavailable saved microphone produces a clear error instead of silently switching inputs.
- **Custom vocabulary:** Comma-separated names and terms guide local recognition. Natural and Professional also apply preferred spelling/capitalization after recognition.
- **Natural:** Conservative removal of clear hesitations and obvious repetition loops, preserving wording, casing, and literal punctuation words.
- **Professional:** Natural cleanup plus spoken punctuation (`comma`, `period`, `new line`, `new paragraph`), bullet commands, and sentence capitalization. Choose Natural for literal uses of those command words.
- **Raw:** The recognizer's output without text cleanup, vocabulary replacements, or formatting. Vocabulary still guides recognition itself.
- **Clipboard:** Existing transient clipboard markers and automatic restoration are used for insertion. “Keep Speech on System Clipboard” retains copied speech when enabled. If Accessibility is unavailable, the existing copy-to-clipboard fallback remains available.
- **History:** Session Only is the default. Incognito disables history; rolling limits keep the last 10 or 50 entries in memory. History is not persisted across app restarts.

Temporary recording files are deleted after processing, cancellation, or capture failure. Audio tests only compute levels in memory. Text deliberately copied or inserted into another application follows that application's own storage/sync behavior.

## Offline model setup

Metatron uses the existing Python environment at `.venv` and already-downloaded MLX Whisper files. The engine loads and warms the actual model before reporting Ready.

The daemon looks in the local Hugging Face cache for `mlx-community/whisper-large-v3-turbo`; an already-cached `mlx-community/whisper-base.en` can serve as a startup fallback. It reads cache directories directly and never calls an online model resolver. Standard `HF_HOME`, `HF_HUB_CACHE`, and `XDG_CACHE_HOME` cache locations are supported.

You can instead set `METATRON_MODEL_DIR` to an existing local model directory containing `config.json` and `weights.safetensors` or `weights.npz` when launching the app/daemon. Missing model files produce an unavailable message; they are never downloaded automatically. Python network sockets and DNS lookups are blocked in the daemon in addition to offline dependency flags.

## Build, test, and launch

```bash
make test   # Synthetic/mocked regression tests; no microphone or network access
make build  # Build and sign Metatron.app
make run    # Restart the app and local daemon
```

`make run` uses the existing app bundle; run `make build` first after changing source. Restart both the app and daemon after an update so they use the same offline protocol.

## macOS permissions

- **Microphone:** Needed for dictation and the explicitly started input test.
- **Accessibility:** Needed for global hotkeys, checking the insertion destination, and pasting into the focused application.
- In **System Settings → Keyboard**, set **“Press 🌐 key to:” → “Do Nothing”** to prevent the system emoji window from opening when using Fn.

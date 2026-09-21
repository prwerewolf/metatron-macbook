# 🎙️ Metatron — The Celestial On-Device Scribe for macOS

> A 1:1 Wispr Flow native clone built specifically for **Apple M4 Max** with **48 GB Unified Memory**.
> 100% On-Device · Zero Cloud Latency · Zero Subscriptions · Ephemeral Privacy.

---

## ✨ Features

- **Push-to-Talk (`Fn` / Globe Key)**: Hold down the `Fn` (Function) key to speak. Release to instantly clean and paste into whatever app you are using (Slack, Cursor, VS Code, Chrome, Notes, Terminal, etc.).
- **Floating Pill UI**: A sleek, liquid-glass draggable capsule that lives on your screen. Drag it to the left, right, top, or bottom. It remembers its exact coordinates across restarts and **never** steals focus from active windows.
- **Real-Time Soundwave**: Dynamic, spring-animated audio bars that dance with your voice in real time as you speak.
- **"Um" & "Ah" Removal**: Intelligent multi-stage cleaning pipeline that eliminates filler speech (*um, uh, ah, er, like, you know*), stutters (*I-I, the-the*), and false starts.
- **Private Direct Text Insertion**: Injects text directly at the cursor via macOS Accessibility/keystrokes without touching your clipboard, preventing clipboard monitors, history utilities (Raycast, Maccy), and iCloud Universal Clipboard from capturing your speech.
- **On-Demand Clipboard Copy**: Explicitly copy your last transcription to your clipboard at any time via the menu bar toolbar up top or the floating pill.
- **100% Local & Private (Apple Silicon Metal GPU)**: Powered by `mlx-whisper` running locally on your Apple M4 Max GPU and Neural Engine. Audio is processed strictly in RAM and immediately deleted upon transcription.
- **Incognito Ephemeral Storage by Default**: Audio and transcripts are never stored on disk forever.
- **Dictation History & Search**: Optional rolling session history with word counts, search, and one-click copy.
- **Custom Vocabulary**: Easily add specialized names, acronyms, and technical terms in Settings.
- **Menu Bar Control**: Status item for quick access to styles, engine selection, settings, and permissions.

---

## 🚀 Quickstart

### Launch Metatron

To build and launch Metatron:

```bash
cd /path/to/user/Documents/_codeRepos/metatron-macbook
make run
```

Or run the launch script directly:

```bash
./scripts/run.sh
```

You can also drag `Metatron.app` directly into your `/Applications` folder.

---

## ⌨️ How to Use

1. **Hold to Speak**: Press and hold the **Function (`Fn` / Globe)** key on your keyboard.
2. **Watch the Pill**: The floating pill expands and the audio waveform bars animate to your voice.
3. **Speak Naturally**: Include fillers like *"um"*, *"uh"*, and spoken punctuation like *"comma"*, *"period"*, *"new line"*.
4. **Release to Paste**: Release the `Fn` key. The pill briefly shows *"Transcribing..."*, cleans the text, and pastes it into your focused text area with a subtle confirmation sound.

---

## ⚙️ Settings & Configuration

Click the **waveform icon in the macOS menu bar** or right-click the floating pill:

- **Hotkey & Mode**: Switch between `Fn (Hold)`, `Right Option`, `Right Command`, or `Toggle Mode` (tap to start, tap to stop).
- **Style**:
  - `Natural`: Direct transcription minus filler words and stutters.
  - `Professional`: Formatted structure with automatic casing, punctuation, and bullet points.
  - `Raw`: Verbatim transcription.
- **Engine**:
  - `Apple M4 Max Local`: 100% offline, GPU-accelerated local transcription.
  - `Groq / OpenAI Cloud`: Optional cloud API fallback if desired.
- **Custom Vocabulary**: Comma-separated custom words and brand names.
- **Privacy & Retention**:
  - `Incognito`: Zero persistent storage (default).
  - `Session Only`: Wiped on app quit.
  - `Keep Last 10 / 50`: Rolling buffer with one-click purge.

---

## 🔒 Permissions & Setup Note

For the optimal experience, macOS requires two permissions:
1. **Microphone**: Prompted on first launch to allow audio capture.
2. **Accessibility**: Needed to detect global `Fn` keypresses and synthesize `Cmd+V`.
   - Open **System Settings → Privacy & Security → Accessibility** and enable `Metatron`.
3. **Fn / Globe Key System Setting**:
   - In macOS **System Settings → Keyboard**, set **"Press 🌐 key to:"** to **"Do Nothing"**. This prevents macOS from popping up the system emoji window when holding the `Fn` key.

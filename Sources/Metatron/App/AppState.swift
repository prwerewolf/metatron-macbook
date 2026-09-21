import Foundation
import SwiftUI
import Combine

public struct DictationItem: Identifiable, Codable {
    public var id = UUID()
    public var timestamp = Date()
    public var rawText: String
    public var cleanedText: String
    public var durationSeconds: Double

    public var wordCount: Int {
        let words = cleanedText.split { $0.isWhitespace || $0.isPunctuation }
        return words.count
    }
}

public enum HistoryRetention: String, CaseIterable, Identifiable, Codable {
    case off = "Incognito (Never save history)"
    case clearOnQuit = "Session Only (Wipe on quit)"
    case keepLast10 = "Keep Last 10 Items"
    case keepLast50 = "Keep Last 50 Items"

    public var id: String { rawValue }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Live States
    @Published public var isRecording: Bool = false
    @Published public var isProcessing: Bool = false
    @Published public var showSuccess: Bool = false
    @Published public var currentAudioLevel: Float = 0.0
    @Published public var statusMessage: String = "Ready"
    @Published public var lastTranscribedText: String = ""

    // MARK: - History & Privacy
    @Published public var history: [DictationItem] = []
    @Published public var historyRetention: HistoryRetention = .clearOnQuit {
        didSet {
            UserDefaults.standard.set(historyRetention.rawValue, forKey: "metatron_retention")
            applyRetentionPolicy()
        }
    }

    // MARK: - Privacy & Clipboard Controls
    @Published public var autoCopyToClipboard: Bool = false {
        didSet {
            UserDefaults.standard.set(autoCopyToClipboard, forKey: "metatron_auto_copy")
        }
    }

    @Published public var autoInsertText: Bool = true {
        didSet {
            UserDefaults.standard.set(autoInsertText, forKey: "metatron_auto_insert")
        }
    }

    // MARK: - Settings
    @Published public var hotkeyChoice: HotkeyChoice = .fnHold {
        didSet {
            UserDefaults.standard.set(hotkeyChoice.rawValue, forKey: "metatron_hotkey")
            HotkeyManager.shared.activeHotkey = hotkeyChoice
        }
    }

    @Published public var dictationMode: DictationMode = .pushToTalk {
        didSet {
            UserDefaults.standard.set(dictationMode.rawValue, forKey: "metatron_mode")
            HotkeyManager.shared.activeMode = dictationMode
        }
    }

    @Published public var transcriptionStyle: TranscriptionStyle = .natural {
        didSet {
            UserDefaults.standard.set(transcriptionStyle.rawValue, forKey: "metatron_style")
        }
    }

    @Published public var speechEngineType: SpeechEngineType = .localMLX {
        didSet {
            UserDefaults.standard.set(speechEngineType.rawValue, forKey: "metatron_engine")
        }
    }

    @Published public var isSoundEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: "metatron_sound")
            SoundEffects.shared.isSoundEnabled = isSoundEnabled
        }
    }

    @Published public var customVocabularyText: String = "" {
        didSet {
            UserDefaults.standard.set(customVocabularyText, forKey: "metatron_vocab")
            updateCustomVocabulary()
        }
    }

    @Published public var groqApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(groqApiKey, forKey: "metatron_groq_key")
            CloudEngine.shared.groqApiKey = groqApiKey
        }
    }

    @Published public var openAIApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(openAIApiKey, forKey: "metatron_openai_key")
            CloudEngine.shared.openAIApiKey = openAIApiKey
        }
    }

    private var recordingStartTime: Date?
    private var activeAudioURL: URL?

    private init() {
        loadSettings()
        setupAudioLevelCallback()
        setupHotkeys()
    }

    private func loadSettings() {
        if let rawRetention = UserDefaults.standard.string(forKey: "metatron_retention"),
           let retention = HistoryRetention(rawValue: rawRetention) {
            self.historyRetention = retention
        }

        if UserDefaults.standard.object(forKey: "metatron_auto_copy") != nil {
            self.autoCopyToClipboard = UserDefaults.standard.bool(forKey: "metatron_auto_copy")
        } else {
            self.autoCopyToClipboard = false // Default to false for privacy
        }

        if UserDefaults.standard.object(forKey: "metatron_auto_insert") != nil {
            self.autoInsertText = UserDefaults.standard.bool(forKey: "metatron_auto_insert")
        } else {
            self.autoInsertText = true
        }

        if let rawHotkey = UserDefaults.standard.string(forKey: "metatron_hotkey"),
           let hotkey = HotkeyChoice(rawValue: rawHotkey) {
            self.hotkeyChoice = hotkey
        }

        if let rawMode = UserDefaults.standard.string(forKey: "metatron_mode"),
           let mode = DictationMode(rawValue: rawMode) {
            self.dictationMode = mode
        }

        if let rawStyle = UserDefaults.standard.string(forKey: "metatron_style"),
           let style = TranscriptionStyle(rawValue: rawStyle) {
            self.transcriptionStyle = style
        }

        if let rawEngine = UserDefaults.standard.string(forKey: "metatron_engine"),
           let engine = SpeechEngineType(rawValue: rawEngine) {
            self.speechEngineType = engine
        }

        if UserDefaults.standard.object(forKey: "metatron_sound") != nil {
            self.isSoundEnabled = UserDefaults.standard.bool(forKey: "metatron_sound")
        }

        self.customVocabularyText = UserDefaults.standard.string(forKey: "metatron_vocab") ?? ""
        self.groqApiKey = UserDefaults.standard.string(forKey: "metatron_groq_key") ?? ""
        self.openAIApiKey = UserDefaults.standard.string(forKey: "metatron_openai_key") ?? ""

        updateCustomVocabulary()
    }

    private func setupAudioLevelCallback() {
        AudioRecorder.shared.onAudioLevel = { [weak self] level in
            guard let self = self, self.isRecording else { return }
            self.currentAudioLevel = level
        }
    }

    private func setupHotkeys() {
        HotkeyManager.shared.activeHotkey = hotkeyChoice
        HotkeyManager.shared.activeMode = dictationMode

        HotkeyManager.shared.onHotkeyDown = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }

        HotkeyManager.shared.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndTranscribe()
            }
        }

        HotkeyManager.shared.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
    }

    private func updateCustomVocabulary() {
        let terms = customVocabularyText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        TextCleaner.shared.customVocabulary = terms
    }

    // MARK: - Actions

    public func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        guard !isRecording, !isProcessing else { return }

        do {
            let url = try AudioRecorder.shared.startRecording()
            self.activeAudioURL = url
            self.isRecording = true
            self.recordingStartTime = Date()
            self.statusMessage = "Listening..."
            SoundEffects.shared.playStart()
        } catch {
            NSLog("[Metatron] Failed to start audio recording: \(error)")
            self.statusMessage = "Mic Error"
            SoundEffects.shared.playError()
        }
    }

    public func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        self.isRecording = false
        self.isProcessing = true
        self.statusMessage = "Transcribing..."
        self.currentAudioLevel = 0.0
        SoundEffects.shared.playStop()

        let audioURL = AudioRecorder.shared.stopRecording() ?? activeAudioURL
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

        Task {
            guard let url = audioURL, FileManager.default.fileExists(atPath: url.path) else {
                self.isProcessing = false
                self.statusMessage = "No Audio"
                return
            }

            do {
                let engine: SpeechEngineProtocol
                switch speechEngineType {
                case .localMLX:
                    engine = LocalDaemonClient.shared
                case .groq, .openAI:
                    engine = CloudEngine.shared
                }

                let rawText = try await engine.transcribe(audioFileURL: url)
                let cleanedText = TextCleaner.shared.clean(text: rawText, style: transcriptionStyle)

                if !cleanedText.isEmpty {
                    self.lastTranscribedText = cleanedText

                    if self.autoInsertText {
                        let hasAccessibility = HotkeyManager.isAccessibilityGranted()
                        if hasAccessibility {
                            TextInserter.shared.insertText(cleanedText, keepOnClipboard: self.autoCopyToClipboard)
                            self.statusMessage = self.autoCopyToClipboard ? "Inserted & Copied!" : "Inserted!"
                        } else {
                            HotkeyManager.requestAccessibilityPermission()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cleanedText, forType: .string)
                            self.statusMessage = "Copied! (Grant Accessibility to auto-insert)"
                        }
                    } else {
                        if self.autoCopyToClipboard {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cleanedText, forType: .string)
                            self.statusMessage = "Copied to Clipboard!"
                        } else {
                            self.statusMessage = "Transcribed! (Click Copy in toolbar)"
                        }
                    }

                    // Visual and audio feedback
                    self.showSuccess = true
                    SoundEffects.shared.playSuccess()

                    // Record history according to privacy retention settings
                    self.recordHistory(raw: rawText, cleaned: cleanedText, duration: duration)

                    // Keep success message visible briefly
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    self.showSuccess = false
                    self.statusMessage = "Ready"
                } else {
                    self.statusMessage = "No Speech Detected"
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    self.statusMessage = "Ready"
                }
            } catch {
                NSLog("[Metatron] Transcription error: \(error)")
                let msg = error.localizedDescription
                self.statusMessage = msg.count > 40 ? String(msg.prefix(37)) + "..." : msg
                SoundEffects.shared.playError()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.statusMessage = "Ready"
            }

            self.isProcessing = false

            // Ephemeral Audio Cleanup: Ensure local temporary audio file is deleted immediately!
            if let path = audioURL?.path, FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    private func recordHistory(raw: String, cleaned: String, duration: Double) {
        guard historyRetention != .off else { return }

        let item = DictationItem(
            rawText: raw,
            cleanedText: cleaned,
            durationSeconds: duration
        )

        history.insert(item, at: 0)
        applyRetentionPolicy()
    }

    private func applyRetentionPolicy() {
        switch historyRetention {
        case .off:
            history.removeAll()
        case .clearOnQuit:
            // kept in memory, not persisted to disk
            break
        case .keepLast10:
            if history.count > 10 {
                history = Array(history.prefix(10))
            }
        case .keepLast50:
            if history.count > 50 {
                history = Array(history.prefix(50))
            }
        }
    }

    public func clearHistory() {
        history.removeAll()
    }

    public func copyLastDictation() {
        guard !lastTranscribedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscribedText, forType: .string)
        self.statusMessage = "Copied to Clipboard!"
        self.showSuccess = true
        SoundEffects.shared.playSuccess()

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self.statusMessage == "Copied to Clipboard!" {
                self.showSuccess = false
                self.statusMessage = "Ready"
            }
        }
    }
}

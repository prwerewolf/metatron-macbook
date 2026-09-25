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

public enum PillOrientation: String, CaseIterable, Identifiable, Codable {
    case horizontal
    case vertical

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
    @Published public var hasPendingInsertion: Bool = false
    @Published public var engineStatus = LocalEngineStatus(phase: .loading, message: "Loading local speech model…")

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

    // MARK: - Floating Pill State
    @Published public var pillOrientation: PillOrientation = .horizontal {
        didSet {
            UserDefaults.standard.set(pillOrientation.rawValue, forKey: "metatron_pill_orientation")
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

    @Published public var textReplacementsText: String = "" {
        didSet {
            UserDefaults.standard.set(textReplacementsText, forKey: "metatron_replacements")
            updateTextReplacements()
        }
    }

    @Published public var launchAtLogin: Bool = false {
        didSet {
            LaunchAtLogin.isEnabled = launchAtLogin
        }
    }

    /// Recordings shorter than this threshold are discarded quietly as accidental clicks.
    public var minRecordingDuration: Double = 0.25

    private var recordingStartTime: Date?
    private var activeAudioURL: URL?
    private var feedbackResetTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionID: UUID?
    private var processingAudioURL: URL?
    private var insertionTarget: InsertionTarget?
    private var isRefreshingEngine = false
    private var lastInsertionTime: Date?
    private var lastInsertionPID: pid_t?
    private var lastInsertedEndsWithWhitespace: Bool = false

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

        if let rawOrientation = UserDefaults.standard.string(forKey: "metatron_pill_orientation"),
           let orientation = PillOrientation(rawValue: rawOrientation) {
            self.pillOrientation = orientation
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

        // Retire settings from older builds that offered cloud transcription.
        for key in ["metatron_engine", "metatron_groq_key", "metatron_openai_key"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        if UserDefaults.standard.object(forKey: "metatron_sound") != nil {
            self.isSoundEnabled = UserDefaults.standard.bool(forKey: "metatron_sound")
        }

        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.customVocabularyText = UserDefaults.standard.string(forKey: "metatron_vocab") ?? ""
        self.textReplacementsText = UserDefaults.standard.string(forKey: "metatron_replacements") ?? ""

        updateCustomVocabulary()
        updateTextReplacements()
    }

    private func setupAudioLevelCallback() {
        AudioRecorder.shared.onAudioLevel = { [weak self] level in
            guard let self = self, self.isRecording else { return }
            self.currentAudioLevel = level
        }
        AudioRecorder.shared.onRecordingError = { [weak self] error, url in
            guard let self = self else { return }
            self.cancelDictation(showFeedback: false)
            HotkeyManager.shared.resetModifierStates()
            if let url { try? FileManager.default.removeItem(at: url) }
            self.statusMessage = error.localizedDescription
            SoundEffects.shared.playError()
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
        HotkeyManager.shared.onCancel = { [weak self] in
            Task { @MainActor in
                self?.cancelDictation()
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

    private func updateTextReplacements() {
        TextCleaner.shared.customReplacements = TextCleaner.parseReplacements(from: textReplacementsText)
    }

    public static func isUndoCommand(_ text: String) -> Bool {
        return TextCleaner.isStandaloneUndoCommand(text)
    }

    public static func shouldPrependSpace(
        to newText: String,
        target: InsertionTarget?,
        lastInsertionTime: Date?,
        lastInsertionPID: pid_t?,
        lastInsertedEndsWithWhitespace: Bool,
        now: Date = Date()
    ) -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespaces)
        guard let firstChar = trimmed.first else { return false }

        // Never prepend a space before punctuation, quotes, brackets, or newlines
        let noLeadingSpaceCharacters = CharacterSet(charactersIn: ".,!?;:)]}'\"”\n•-")
        if let scalar = firstChar.unicodeScalars.first, noLeadingSpaceCharacters.contains(scalar) {
            return false
        }

        // 1. If AX can inspect the cursor context in the focused control:
        if let target {
            switch target.cursorContext() {
            case .startOfText:
                // Cursor is at the beginning of the text field (location == 0). Never prepend space.
                return false
            case .character(let preceding):
                let whitespaceOrOpening = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "([{“\"'\n\t"))
                if let scalar = preceding.unicodeScalars.first, whitespaceOrOpening.contains(scalar) {
                    return false
                }
                return true
            case .unavailable:
                break
            }
        }

        // 2. Fallback: Consecutive dictation in the same app within 45 seconds
        if let lastTime = lastInsertionTime,
           let lastPID = lastInsertionPID,
           let currentPID = target?.targetPID,
           lastPID == currentPID,
           now.timeIntervalSince(lastTime) < 45.0,
           !lastInsertedEndsWithWhitespace {
            return true
        }

        return false
    }

    // MARK: - Actions

    public func refreshEngineStatus() async {
        guard !isRefreshingEngine else { return }
        isRefreshingEngine = true
        defer { isRefreshingEngine = false }
        let previous = engineStatus
        engineStatus = await LocalDaemonClient.shared.engineStatus()
        if !isRecording, !isProcessing, !showSuccess,
           statusMessage == previous.message {
            statusMessage = "Ready"
        }
    }

    public func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        guard !isRecording, !isProcessing else { return }
        clearFeedback()
        guard engineStatus.phase == .ready else {
            statusMessage = engineStatus.message
            return
        }

        do {
            let captureStartedAt = ProcessInfo.processInfo.systemUptime
            let target = InsertionTarget.capture()
            NSLog("[Metatron Timing] capture_focus=%.3fs", ProcessInfo.processInfo.systemUptime - captureStartedAt)
            let audioStartedAt = ProcessInfo.processInfo.systemUptime
            let url = try AudioRecorder.shared.startRecording()
            NSLog("[Metatron Timing] start_audio=%.3fs", ProcessInfo.processInfo.systemUptime - audioStartedAt)
            self.insertionTarget = target
            self.activeAudioURL = url
            self.isRecording = true
            self.recordingStartTime = Date()
            self.statusMessage = "Listening..."
            SoundEffects.shared.playStart()
        } catch {
            NSLog("[Metatron] Failed to start audio recording: \(error)")
            self.statusMessage = error.localizedDescription
            SoundEffects.shared.playError()
            self.scheduleFeedbackReset(after: 3_000_000_000)
        }
    }

    public func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        let pipelineStartedAt = ProcessInfo.processInfo.systemUptime
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

        // Accidental Click Guard: Silently discard clicks shorter than minRecordingDuration (default 0.25s)
        if minRecordingDuration > 0 && duration < minRecordingDuration {
            let audioURL = AudioRecorder.shared.stopRecording() ?? activeAudioURL
            if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
                try? FileManager.default.removeItem(at: audioURL)
            }
            activeAudioURL = nil
            recordingStartTime = nil
            insertionTarget = nil
            self.isRecording = false
            self.isProcessing = false
            self.currentAudioLevel = 0.0
            HotkeyManager.shared.resetModifierStates()
            clearFeedback()
            self.statusMessage = "Ready"
            return
        }

        clearFeedback()
        self.isRecording = false
        self.isProcessing = true
        self.statusMessage = "Transcribing..."
        self.currentAudioLevel = 0.0
        SoundEffects.shared.playStop()

        let audioURL = AudioRecorder.shared.stopRecording() ?? activeAudioURL
        NSLog("[Metatron Timing] stop_audio=%.3fs", ProcessInfo.processInfo.systemUptime - pipelineStartedAt)
        let target = insertionTarget
        let vocabulary = TextCleaner.shared.customVocabulary
        let replacements = TextCleaner.shared.customReplacements
        let style = transcriptionStyle
        let requestID = UUID()
        transcriptionID = requestID
        processingAudioURL = audioURL
        activeAudioURL = nil
        recordingStartTime = nil
        insertionTarget = nil

        transcriptionTask = Task {
            defer {
                NSLog("[Metatron Timing] release_to_completion=%.3fs cancelled=%d", ProcessInfo.processInfo.systemUptime - pipelineStartedAt, Task.isCancelled ? 1 : 0)
                // Release the recording as soon as processing finishes, independently of feedback.
                if let url = audioURL, FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                if self.transcriptionID == requestID {
                    self.isProcessing = false
                    self.processingAudioURL = nil
                    self.transcriptionID = nil
                    self.transcriptionTask = nil
                }
            }

            guard self.transcriptionID == requestID, !Task.isCancelled else { return }
            guard let url = audioURL, FileManager.default.fileExists(atPath: url.path) else {
                self.statusMessage = "No Audio"
                self.scheduleFeedbackReset(after: 1_200_000_000)
                return
            }

            do {
                let recognitionStartedAt = ProcessInfo.processInfo.systemUptime
                let rawText = try await LocalDaemonClient.shared.transcribe(audioFileURL: url, vocabulary: vocabulary, style: style)
                NSLog("[Metatron Timing] recognition=%.3fs", ProcessInfo.processInfo.systemUptime - recognitionStartedAt)
                try Task.checkCancellation()
                guard self.transcriptionID == requestID else { return }
                let cleanupStartedAt = ProcessInfo.processInfo.systemUptime
                let cleanedText = TextCleaner.shared.clean(text: rawText, style: style, vocabulary: vocabulary, replacements: replacements)
                NSLog("[Metatron Timing] text_cleanup=%.3fs", ProcessInfo.processInfo.systemUptime - cleanupStartedAt)

                // Standalone Voice Undo: "scratch that", "cancel that", "undo that"
                if Self.isUndoCommand(cleanedText) {
                    if HotkeyManager.isAccessibilityGranted() {
                        TextInserter.shared.sendUndoKeystroke()
                    }
                    self.statusMessage = "Undone!"
                    self.showSuccess = true
                    SoundEffects.shared.playSuccess()
                    self.scheduleFeedbackReset(after: 1_800_000_000)
                    return
                }

                if !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var needsManualInsertion = false

                    // Smart Prefix Spacing: prepend space if following a prior insertion in same target
                    var textToInsert = cleanedText
                    let effectiveTarget = target ?? InsertionTarget.capture()
                    if self.autoInsertText && Self.shouldPrependSpace(
                        to: textToInsert,
                        target: effectiveTarget,
                        lastInsertionTime: self.lastInsertionTime,
                        lastInsertionPID: self.lastInsertionPID,
                        lastInsertedEndsWithWhitespace: self.lastInsertedEndsWithWhitespace
                    ) {
                        textToInsert = " " + textToInsert
                    }

                    if self.autoInsertText {
                        let hasAccessibility = HotkeyManager.isAccessibilityGranted()
                        if hasAccessibility {
                            let inserted: Bool = await withCheckedContinuation { continuation in
                                TextInserter.shared.insertText(textToInsert, keepOnClipboard: self.autoCopyToClipboard, target: effectiveTarget, shouldInsert: { [weak self] in
                                    self?.transcriptionID == requestID
                                }) { inserted in
                                    continuation.resume(returning: inserted)
                                }
                            }
                            try Task.checkCancellation()
                            guard self.transcriptionID == requestID else { return }
                            if inserted {
                                self.statusMessage = self.autoCopyToClipboard ? "Inserted & Copied!" : "Inserted!"
                                self.lastInsertionTime = Date()
                                self.lastInsertionPID = effectiveTarget?.targetPID
                                self.lastInsertedEndsWithWhitespace = textToInsert.hasSuffix(" ") || textToInsert.hasSuffix("\n")
                            } else {
                                // Always place speech on clipboard if auto-insertion could not complete
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cleanedText, forType: .string)
                                needsManualInsertion = true
                                self.statusMessage = "Focus changed — text copied to clipboard"
                            }
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

                    self.lastTranscribedText = cleanedText
                    self.hasPendingInsertion = needsManualInsertion
                    // Visual and audio feedback
                    self.showSuccess = !self.hasPendingInsertion
                    if !self.hasPendingInsertion {
                        SoundEffects.shared.playSuccess()
                    } else {
                        SoundEffects.shared.playError()
                    }

                    // Record history according to privacy retention settings
                    self.recordHistory(raw: rawText, cleaned: cleanedText, duration: duration)

                    if !self.hasPendingInsertion {
                        self.scheduleFeedbackReset(after: 2_200_000_000)
                    } else {
                        self.scheduleFeedbackReset(after: 3_500_000_000)
                    }
                } else {
                    self.statusMessage = "No Speech Detected"
                    self.scheduleFeedbackReset(after: 1_200_000_000)
                }
            } catch is CancellationError {
                // A canceled request must never insert text or overwrite a newer recording.
            } catch {
                guard self.transcriptionID == requestID, !Task.isCancelled else { return }
                NSLog("[Metatron] Transcription error: \(error)")
                let msg = error.localizedDescription
                self.statusMessage = msg.count > 40 ? String(msg.prefix(37)) + "..." : msg
                SoundEffects.shared.playError()
                self.scheduleFeedbackReset(after: 3_000_000_000)
            }
        }
    }

    public func cancelDictation(showFeedback: Bool = true) {
        guard isRecording || isProcessing else { return }
        clearFeedback()
        let recordedURL = isRecording ? AudioRecorder.shared.stopRecording() : nil
        transcriptionID = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        for url in [recordedURL, activeAudioURL, processingAudioURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        activeAudioURL = nil
        processingAudioURL = nil
        insertionTarget = nil
        recordingStartTime = nil
        isRecording = false
        isProcessing = false
        currentAudioLevel = 0
        HotkeyManager.shared.resetModifierStates()
        if showFeedback {
            statusMessage = "Canceled"
            scheduleFeedbackReset(after: 1_200_000_000)
        }
    }

    private func clearFeedback() {
        feedbackResetTask?.cancel()
        feedbackResetTask = nil
        showSuccess = false
    }

    private func scheduleFeedbackReset(after nanoseconds: UInt64) {
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self = self, !self.isRecording, !self.isProcessing else { return }
            self.showSuccess = false
            self.statusMessage = "Ready"
            self.feedbackResetTask = nil
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
            clearHistory()
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
        lastTranscribedText = ""
        hasPendingInsertion = false
        lastInsertionTime = nil
        lastInsertionPID = nil
        lastInsertedEndsWithWhitespace = false
        clearFeedback()
        if !isRecording && !isProcessing {
            statusMessage = "Ready"
        }
    }

    public func copyLastDictation() {
        guard !lastTranscribedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscribedText, forType: .string)
        hasPendingInsertion = false
        self.statusMessage = "Copied to Clipboard!"
        self.showSuccess = true
        SoundEffects.shared.playSuccess()

        scheduleFeedbackReset(after: 1_800_000_000)
    }
}

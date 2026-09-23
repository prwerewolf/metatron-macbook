import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Settings section", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Microphone").tag(4)
                Text("Writing").tag(1)
                Text("Engine").tag(2)
                Text("Privacy").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedTab {
                case 4: MicrophoneSettingsView()
                case 1: StyleSettingsTab()
                case 2: EngineSettingsTab()
                case 3: PrivacySettingsTab()
                default: GeneralSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: $appState.hotkeyChoice) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.menu)

                Picker("Mode", selection: $appState.dictationMode) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Press Escape to discard a recording or cancel a pending dictation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Activation & Controls")
                    .fontWeight(.semibold)
            }

            Divider()

            Section {
                Toggle("Enable Audio Cues (Clicks & Chimes)", isOn: $appState.isSoundEnabled)
            } header: {
                Text("Feedback")
                    .fontWeight(.semibold)
            }

            Divider()

            Section {
                HStack {
                    Text("Floating Pill Position")
                    Spacer()
                    Button("Center Pill on Screen") {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.pillPanel?.resetPositionToCenter()
                        }
                    }
                }
            } header: {
                Text("Appearance")
                    .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Style & Eloquence Tab
struct StyleSettingsTab: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Picker("Transcription Style", selection: $appState.transcriptionStyle) {
                    ForEach(TranscriptionStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(styleDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            } header: {
                Text("Clean-Up & Formatting")
                    .fontWeight(.semibold)
            }

            Divider()

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Vocabulary & Acronyms")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Enter comma-separated names and technical terms to guide local speech recognition. Natural and Professional also preserve their preferred capitalization.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $appState.customVocabularyText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private var styleDescription: String {
        switch appState.transcriptionStyle {
        case .natural:
            return "Light cleanup: removes clear hesitations while preserving your wording, punctuation, and sentence casing. Spoken punctuation words stay as words."
        case .professional:
            return "Formats spoken punctuation and bullet commands, tidies spacing, and capitalizes sentences. Preserves meaning without rewriting your speech."
        case .raw:
            return "The speech recognizer's original output, with no cleanup, formatting, or vocabulary replacements."
        }
    }
}

// MARK: - Speech Engine Tab
struct EngineSettingsTab: View {
    @ObservedObject var appState = AppState.shared

    private var statusColor: Color {
        switch appState.engineStatus.phase {
        case .loading: return .orange
        case .ready: return .green
        case .unavailable: return .red
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Local Whisper on Apple Silicon")
                            .fontWeight(.semibold)
                        Text("Speech recognition runs on this Mac using mlx-whisper and Metal GPU acceleration. Your recordings stay on this Mac.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: appState.engineStatus.phase == .ready ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundColor(statusColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.engineStatus.message)
                            .font(.callout)
                        if let model = appState.engineStatus.model {
                            Text(model)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)

                Text("Uses installed model files only. Model downloads and online checks are disabled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("On-Device Speech Recognition")
                    .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Privacy & Retention Tab
struct PrivacySettingsTab: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle("Auto-Insert Text at Cursor", isOn: $appState.autoInsertText)
                Text("Automatically pastes text directly where your cursor is. Uses transient markers and automatic clipboard restoration (Whisperflow-style) so your clipboard history stays clean.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Keep Speech on System Clipboard", isOn: $appState.autoCopyToClipboard)
                Text("When disabled (recommended), your previously copied items are preserved and speech is not saved in clipboard history. When enabled, speech remains in your clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Cursor Typing & Clipboard Privacy")
                    .fontWeight(.semibold)
            }

            Divider()

            Section {
                Picker("History Retention", selection: $appState.historyRetention) {
                    ForEach(HistoryRetention.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zero Permanent Storage Policy")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Temporary recordings are deleted after processing or cancellation. Session history stays in memory on this Mac.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
                .padding(.top, 4)
            } header: {
                Text("Data & Privacy Controls")
                    .fontWeight(.semibold)
            }

            Divider()

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Purge Session History")
                            .fontWeight(.medium)
                        Text("Instantly delete all stored dictations from memory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Purge Now", role: .destructive) {
                        appState.clearHistory()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

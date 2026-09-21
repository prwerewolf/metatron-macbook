import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            StyleSettingsTab()
                .tabItem {
                    Label("Style & Eloquence", systemImage: "text.badge.star")
                }
                .tag(1)

            EngineSettingsTab()
                .tabItem {
                    Label("Speech Engine", systemImage: "cpu")
                }
                .tag(2)

            PrivacySettingsTab()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised.shield")
                }
                .tag(3)
        }
        .padding(20)
        .frame(width: 520, height: 440)
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
                    Text("Enter comma-separated words, technical terms, or company names to prioritize accurate spelling.")
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
            return "Wispr Flow style: eliminates 'um', 'uh', 'ah', 'like', and stutter repetitions. Punctuation is naturally preserved."
        case .professional:
            return "Polished structure: eliminates filler words and automatically formats lists, bullet points, and sentence casing."
        case .raw:
            return "Exact verbatim speech: preserves every word spoken without filtering."
        }
    }
}

// MARK: - Speech Engine Tab
struct EngineSettingsTab: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Picker("Speech Engine", selection: $appState.speechEngineType) {
                    ForEach(SpeechEngineType.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)

                if appState.speechEngineType == .localMLX {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.badge.checkmark.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple M4 Max Acceleration Active")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Using native Metal GPU pipeline via mlx-whisper. 100% offline, private, and sub-200ms latency.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.top, 4)
                }
            } header: {
                Text("Speech-to-Text Engine")
                    .fontWeight(.semibold)
            }

            if appState.speechEngineType == .groq {
                Divider()
                Section {
                    SecureField("Groq API Key (gsk_...)", text: $appState.groqApiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Groq runs Whisper large-v3-turbo in ~150ms in the cloud.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Groq Cloud Credentials")
                        .fontWeight(.semibold)
                }
            } else if appState.speechEngineType == .openAI {
                Divider()
                Section {
                    SecureField("OpenAI API Key (sk-...)", text: $appState.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("OpenAI Credentials")
                        .fontWeight(.semibold)
                }
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
                Toggle("Auto-Copy Dictation to Clipboard", isOn: $appState.autoCopyToClipboard)
                Text("When disabled, transcribed speech is never placed on your macOS clipboard. You can still copy anytime via the top toolbar or floating pill.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Auto-Insert Text at Cursor", isOn: $appState.autoInsertText)
                Text("Directly types text into your active application via Accessibility/keystrokes without touching the clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Clipboard & Typing Privacy")
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
                        Text("Audio files are kept exclusively in temporary RAM during dictation and deleted the exact moment transcription finishes.")
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

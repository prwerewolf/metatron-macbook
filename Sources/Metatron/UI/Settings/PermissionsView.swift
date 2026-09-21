import SwiftUI
import AppKit

public struct PermissionsView: View {
    @State private var hasMic: Bool = AudioRecorder.shared.hasPermission
    @State private var hasAccessibility: Bool = HotkeyManager.isAccessibilityGranted()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions & Setup")
                        .font(.headline)
                    Text("Metatron requires two macOS permissions to listen and insert text.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 1. Microphone Permission
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.blue)
                        Text("Microphone Access")
                            .fontWeight(.medium)
                    }
                    Text("Needed to record your voice when holding the hotkey. Audio is processed 100% locally in RAM and immediately purged.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasMic {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button("Grant Access") {
                        AudioRecorder.shared.requestPermission { granted in
                            hasMic = granted
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // 2. Accessibility Permission
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "keyboard.fill")
                            .foregroundColor(.purple)
                        Text("Accessibility Access")
                            .fontWeight(.medium)
                    }
                    Text("Needed to detect the Function (Fn) key globally and simulate Cmd+V to paste into active applications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasAccessibility {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    HStack(spacing: 8) {
                        Button("Reveal in Finder") {
                            let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
                            NSWorkspace.shared.activateFileViewerSelecting([appURL])
                        }
                        .buttonStyle(.bordered)

                        Button("Open Settings") {
                            HotkeyManager.requestAccessibilityPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // 3. Pro-Tip on macOS Fn / Globe Key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Pro-Tip for the Fn / Globe Key")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text("In macOS **System Settings → Keyboard**, set **\"Press 🌐 key to:\"** to **\"Do Nothing\"**. This prevents macOS from popping up the emoji window when you hold Fn to speak.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Open Keyboard Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 12) {
                Text("Note: macOS requires restarting the app after enabling Accessibility.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Refresh") {
                    hasMic = AudioRecorder.shared.hasPermission
                    hasAccessibility = HotkeyManager.isAccessibilityGranted()
                }
                .buttonStyle(.bordered)

                Button("Restart App") {
                    let appPath = Bundle.main.bundlePath
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = ["-n", appPath]
                    try? task.run()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            hasMic = AudioRecorder.shared.hasPermission
            hasAccessibility = HotkeyManager.isAccessibilityGranted()
        }
    }
}

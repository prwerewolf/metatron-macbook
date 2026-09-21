import SwiftUI

public struct FloatingPillView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @State private var isHovering: Bool = false
    @State private var isShimmering: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            // Leading Status Icon / Orb
            ZStack {
                if appState.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .scaleEffect(appState.currentAudioLevel > 0.1 ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: appState.currentAudioLevel)
                } else if appState.isProcessing {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(
                            LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2.2
                        )
                        .frame(width: 12, height: 12)
                        .rotationEffect(Angle(degrees: isShimmering ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isShimmering)
                        .onAppear { isShimmering = true }
                } else if appState.showSuccess {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    // Idle Orb
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.cyan.opacity(0.5), radius: 4, x: 0, y: 0)
                }
            }

            // Center Content: Waveform or Text
            if appState.isRecording {
                WaveformView(audioLevel: appState.currentAudioLevel)
                Text("Listening...")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            } else if appState.isProcessing {
                Text("Transcribing...")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            } else if appState.showSuccess {
                Text(appState.lastTranscribedText.isEmpty ? appState.statusMessage : appState.lastTranscribedText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
                    .truncationMode(.tail)
            } else if appState.statusMessage != "Ready" {
                Text(appState.statusMessage)
                    .font(.system(size: 11.0, weight: .medium, design: .rounded))
                    .foregroundColor(appState.statusMessage.contains("Error") || appState.statusMessage.contains("failed") ? .orange : .cyan)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
                    .truncationMode(.tail)
            } else {
                Text(appState.hotkeyChoice == .fnHold ? "Hold Fn" : "Metatron")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Copy Quick Button when hovering and transcribed text exists
            if isHovering && !appState.lastTranscribedText.isEmpty && !appState.isRecording && !appState.isProcessing {
                Button {
                    appState.copyLastDictation()
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .help("Copy last transcription")
            }

            // Trailing Drag Gripper (subtle dots)
            HStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 2) {
                        Circle().fill(Color.white.opacity(isHovering ? 0.4 : 0.2)).frame(width: 2.5, height: 2.5)
                        Circle().fill(Color.white.opacity(isHovering ? 0.4 : 0.2)).frame(width: 2.5, height: 2.5)
                        Circle().fill(Color.white.opacity(isHovering ? 0.4 : 0.2)).frame(width: 2.5, height: 2.5)
                    }
                }
            }
            .padding(.leading, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                // Frosted Dark Glass Pill
                Capsule()
                    .fill(.ultraThinMaterial)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    )

                // Outer border glow
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(appState.isRecording ? 0.5 : (isHovering ? 0.3 : 0.15)),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            appState.toggleRecording()
        }
    }
}

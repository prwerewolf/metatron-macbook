import SwiftUI
import AppKit

public struct FloatingPillView: View {
    @ObservedObject var appState: AppState = AppState.shared
    @State private var isHovering: Bool = false
    @State private var isShimmering: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if appState.pillOrientation == .vertical {
                verticalPillContent
            } else {
                horizontalPillContent
            }
        }
        .background(pillBackground)
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - App Icon Component (replaces former circle orb)

    private var appIconView: some View {
        ZStack {
            // App Icon
            if let icon = loadAppIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
            }

            // Pulsing active recording indicator ring around icon
            if appState.isRecording {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .scaleEffect(appState.currentAudioLevel > 0.08 ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: appState.currentAudioLevel)
            } else if appState.isProcessing {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.8
                    )
                    .frame(width: 26, height: 26)
                    .rotationEffect(Angle(degrees: isShimmering ? 360 : 0))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isShimmering)
                    .onAppear { isShimmering = true }
            } else if appState.showSuccess {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .offset(x: 9, y: -9)
            }
        }
    }

    // MARK: - Horizontal Pill (Top / Bottom edges)

    private var horizontalPillContent: some View {
        HStack(spacing: 8) {
            // 1. App Icon
            appIconView

            // 2. State content (NO "Hold Fn")
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
                    .frame(maxWidth: 180)
                    .truncationMode(.tail)
            } else if appState.statusMessage != "Ready" {
                Text(appState.statusMessage)
                    .font(.system(size: 11.0, weight: .medium, design: .rounded))
                    .foregroundColor(appState.statusMessage.contains("Error") || appState.statusMessage.contains("failed") ? .orange : .cyan)
                    .lineLimit(1)
                    .frame(maxWidth: 180)
                    .truncationMode(.tail)
            } else {
                // Clean Idle title — NO "Hold Fn"
                Text("Metatron")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }

            // 3. Quick Copy on hover
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

            // 4. Drag Gripper dots
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Vertical Pill (Left / Right edges — "a pill that's down not sideways")

    private var verticalPillContent: some View {
        VStack(spacing: 8) {
            // Top: App Icon
            appIconView
                .padding(.top, 4)

            // Middle: Vertical Visualizer / Status
            if appState.isRecording {
                VStack(spacing: 2.5) {
                    ForEach(0..<4, id: \.self) { i in
                        let multiplier: CGFloat = [0.5, 1.0, 0.75, 0.4][i]
                        let baseW: CGFloat = 6.0
                        let maxW: CGFloat = 22.0
                        let w = baseW + (CGFloat(appState.currentAudioLevel) * (maxW - baseW) * multiplier)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(baseW, min(maxW, w)), height: 2.5)
                            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: appState.currentAudioLevel)
                    }
                }
                .frame(height: 22)
            } else if appState.isProcessing {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .rotationEffect(Angle(degrees: isShimmering ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isShimmering)
            } else if appState.showSuccess {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            } else {
                // Idle: Minimal vertical dots
                VStack(spacing: 3) {
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 2.5, height: 2.5)
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 2.5, height: 2.5)
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 2.5, height: 2.5)
                }
            }

            Spacer(minLength: 4)

            // Bottom: Copy button on hover or drag grip
            if isHovering && !appState.lastTranscribedText.isEmpty && !appState.isRecording && !appState.isProcessing {
                Button {
                    appState.copyLastDictation()
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
                .help("Copy last transcription")
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(isHovering ? 0.4 : 0.2)).frame(width: 2.5, height: 2.5)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Glass Background

    private var pillBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                )

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
    }

    private func loadAppIcon() -> NSImage? {
        if let masterURL = Bundle.main.url(forResource: "AppIcon_master", withExtension: "png"),
           let img = NSImage(contentsOf: masterURL) {
            return img
        }
        if let fileURL = URL(string: "file:///path/to/user/Documents/_codeRepos/metatron-macbook/Resources/AppIcon_master.png"),
           let img = NSImage(contentsOf: fileURL) {
            return img
        }
        return NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
    }
}

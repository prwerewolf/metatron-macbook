import SwiftUI

public struct WaveformView: View {
    public var audioLevel: Float // Normalized 0.0 ... 1.0
    public var barCount: Int = 4

    // Heights multipliers to create an organic curved wave shape
    private let barMultipliers: [CGFloat] = [0.5, 1.0, 0.8, 0.4]

    public init(audioLevel: Float, barCount: Int = 4) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 2.0) {
            ForEach(0..<barCount, id: \.self) { index in
                let multiplier = index < barMultipliers.count ? barMultipliers[index] : 0.6
                let baseHeight: CGFloat = 3.0
                let maxHeight: CGFloat = 14.0
                let dynamicHeight = baseHeight + (CGFloat(audioLevel) * (maxHeight - baseHeight) * multiplier)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: max(baseHeight, min(maxHeight, dynamicHeight)))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: audioLevel)
            }
        }
        .frame(height: 16)
    }
}

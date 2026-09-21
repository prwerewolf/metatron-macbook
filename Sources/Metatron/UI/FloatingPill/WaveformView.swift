import SwiftUI

public struct WaveformView: View {
    public var audioLevel: Float // Normalized 0.0 ... 1.0
    public var barCount: Int = 5

    // Heights multipliers to create an organic curved wave shape
    private let barMultipliers: [CGFloat] = [0.4, 0.75, 1.0, 0.75, 0.4]

    public init(audioLevel: Float, barCount: Int = 5) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<barCount, id: \.self) { index in
                let multiplier = index < barMultipliers.count ? barMultipliers[index] : 0.6
                let baseHeight: CGFloat = 4.0
                let maxHeight: CGFloat = 20.0
                let dynamicHeight = baseHeight + (CGFloat(audioLevel) * (maxHeight - baseHeight) * multiplier)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan, Color.blue, Color.purple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: max(baseHeight, min(maxHeight, dynamicHeight)))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: audioLevel)
            }
        }
        .frame(height: 22)
    }
}

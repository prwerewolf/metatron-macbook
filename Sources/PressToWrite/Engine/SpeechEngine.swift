import Foundation

public enum SpeechMode: String, CaseIterable, Identifiable, Sendable {
    case accuracy
    case fast

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .accuracy: return "Accuracy — Whisper"
        case .fast: return "Fast — Nemotron English"
        }
    }
}

public struct LocalEngineStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        case unavailable
    }

    public let phase: Phase
    public let message: String
    public let model: String?

    public init(phase: Phase = .loading, message: String = "Loading the local speech model…", model: String? = nil) {
        self.phase = phase
        self.message = message
        self.model = model
    }
}

public protocol SpeechEngineProtocol {
    func transcribe(audioFileURL: URL, vocabulary: [String], style: TranscriptionStyle, context: String?) async throws -> String
}

public extension SpeechEngineProtocol {
    func transcribe(audioFileURL: URL, vocabulary: [String], style: TranscriptionStyle) async throws -> String {
        try await transcribe(audioFileURL: audioFileURL, vocabulary: vocabulary, style: style, context: nil)
    }
}

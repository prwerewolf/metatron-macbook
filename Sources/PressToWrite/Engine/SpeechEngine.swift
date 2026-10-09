import Foundation

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

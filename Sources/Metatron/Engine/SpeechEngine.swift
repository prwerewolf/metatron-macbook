import Foundation

public enum SpeechEngineType: String, CaseIterable, Identifiable, Codable {
    case localMLX = "Apple M4 Max Local (100% Offline, GPU Metal)"
    case groq = "Groq Cloud (Lightning Fast API)"
    case openAI = "OpenAI Cloud (Whisper API)"

    public var id: String { rawValue }
}

public protocol SpeechEngineProtocol {
    func transcribe(audioFileURL: URL) async throws -> String
}

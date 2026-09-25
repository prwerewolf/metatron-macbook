import Foundation

public final class RescueAudioController: @unchecked Sendable {
    public static let shared = RescueAudioController()

    private let lock = NSLock()
    private let appSupportURL: URL
    private let rescueWavURL: URL
    private let metadataURL: URL

    public struct RescueMetadata: Codable {
        public let timestamp: Date
        public let duration: Double
        public var status: String // "pending", "transcribed", "failed"
        public var errorMessage: String?
    }

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("Press To Write", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.appSupportURL = base
        self.rescueWavURL = base.appendingPathComponent("last_recording.wav")
        self.metadataURL = base.appendingPathComponent("rescue_metadata.json")
    }

    public var rescueAudioURL: URL { rescueWavURL }

    public var hasRescueAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: rescueWavURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: rescueWavURL.path),
              let size = attrs[.size] as? UInt64, size > 1000 else {
            return false
        }
        return true
    }

    public var pendingMetadata: RescueMetadata? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: metadataURL),
              let meta = try? JSONDecoder().decode(RescueMetadata.self, from: data) else {
            return nil
        }
        return meta
    }

    public func saveRescueAudio(from sourceURL: URL, duration: Double) {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        if fm.fileExists(atPath: rescueWavURL.path) {
            try? fm.removeItem(at: rescueWavURL)
        }
        do {
            try fm.copyItem(at: sourceURL, to: rescueWavURL)
            let meta = RescueMetadata(timestamp: Date(), duration: duration, status: "pending", errorMessage: nil)
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: metadataURL)
            }
            NSLog("[Metatron Rescue] Saved rescue audio (%.2fs) to %@", duration, rescueWavURL.path)
        } catch {
            NSLog("[Metatron Rescue] Failed to save rescue audio: %@", error.localizedDescription)
        }
    }

    public func markTranscriptionCompleted() {
        lock.lock()
        defer { lock.unlock() }
        guard var meta = pendingMetadataNoLock() else { return }
        meta.status = "transcribed"
        meta.errorMessage = nil
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metadataURL)
        }
    }

    public func markTranscriptionFailed(error: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var meta = pendingMetadataNoLock() else { return }
        meta.status = "failed"
        meta.errorMessage = error
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metadataURL)
        }
    }

    public func clearRescueAudio() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(at: rescueWavURL)
    }

    private func pendingMetadataNoLock() -> RescueMetadata? {
        guard let data = try? Data(contentsOf: metadataURL),
              let meta = try? JSONDecoder().decode(RescueMetadata.self, from: data) else {
            return nil
        }
        return meta
    }
}

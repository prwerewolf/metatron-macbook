import Foundation
import AVFoundation
import Accelerate

public final class AudioRecorder: NSObject {
    public static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var isRecordingInternal = false

    public var onAudioLevel: ((Float) -> Void)?

    public var isRecording: Bool {
        return isRecordingInternal
    }

    private override init() {
        super.init()
    }

    /// Request microphone access if not already granted
    public func requestPermission(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    public var hasPermission: Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// Starts recording audio from the default input device
    public func startRecording() throws -> URL {
        guard !isRecordingInternal else {
            return tempFileURL ?? URL(fileURLWithPath: "/tmp/metatron_temp.wav")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "metatron_\(UUID().uuidString).wav"
        let outputURL = tempDir.appendingPathComponent(fileName)
        self.tempFileURL = outputURL

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode

        // Whisper expects 16kHz, 1-channel, 16-bit Linear PCM
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "MetatronAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create 16kHz target audio format"])
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "MetatronAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Microphone input format invalid or device disconnected"])
        }

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: whisperFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )
        self.audioFile = audioFile

        guard let formatConverter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            throw NSError(domain: "MetatronAudio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format converter"])
        }

        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecordingInternal else { return }

            // 1. Calculate RMS audio power for waveform visualization
            let level = self.calculateAudioLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.onAudioLevel?(level)
            }

            // 2. Convert incoming buffer to 16kHz PCM and write to disk
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (16000.0 / inputFormat.sampleRate)) + 64
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var allConsumed = false

            formatConverter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if !allConsumed {
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            if let error = error {
                NSLog("[MetatronAudio] Conversion error: \(error)")
                return
            }

            if convertedBuffer.frameLength > 0 {
                do {
                    try self.audioFile?.write(from: convertedBuffer)
                } catch {
                    NSLog("[MetatronAudio] Write buffer error: \(error)")
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRecordingInternal = true
        return outputURL
    }

    /// Stops recording and finalizes the audio file
    public func stopRecording() -> URL? {
        guard isRecordingInternal else { return nil }
        isRecordingInternal = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        let url = tempFileURL
        return url
    }

    /// Calculates a normalized [0.0 ... 1.0] audio level for the visualizer
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frames = buffer.frameLength
        if frames == 0 { return 0.0 }

        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frames))

        // Convert RMS to decibels and normalize
        let minDb: Float = -50.0
        let maxDb: Float = 0.0
        let db = 20.0 * log10(max(rms, 0.00001))
        let clamped = max(minDb, min(maxDb, db))
        let normalized = (clamped - minDb) / (maxDb - minDb)

        return normalized
    }
}

import Foundation
import AVFoundation

// Synthetic PCM only: this does not open an audio engine, access a microphone,
// request permission, or write a recording to disk.
@main
struct AudioConversionTests {
    static func convert(channels: AVAudioChannelCount, signalChannel: Int?) throws -> Double {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: channels,
            interleaved: false
        )!
        let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800)!
        input.frameLength = input.frameCapacity
        for channel in 0..<Int(channels) {
            let samples = input.floatChannelData![channel]
            for frame in 0..<Int(input.frameLength) {
                samples[frame] = channel == signalChannel
                    ? Float(0.5 * sin(2 * Double.pi * 440 * Double(frame) / inputFormat.sampleRate))
                    : 0
            }
        }

        let converter = try AudioRecorder.makeWhisperConverter(from: inputFormat)
        let outputFormat = converter.outputFormat
        precondition(outputFormat.sampleRate == 16000, "Whisper audio must be resampled to 16 kHz")
        precondition(outputFormat.channelCount == 1, "Whisper audio must be mono")
        precondition(outputFormat.commonFormat == .pcmFormatInt16, "Whisper audio must use 16-bit PCM")

        let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1664)!
        var suppliedInput = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        if let error { throw error }
        precondition(status != .error, "Audio conversion must succeed")
        precondition(output.frameLength > 0, "Audio conversion must produce samples")

        let samples = output.int16ChannelData![0]
        var sumSquares = 0.0
        for frame in 0..<Int(output.frameLength) {
            let sample = Double(samples[frame])
            sumSquares += sample * sample
        }
        return sqrt(sumSquares / Double(output.frameLength))
    }

    static func main() throws {
        let secondChannelRMS = try convert(channels: 2, signalChannel: 1)
        precondition(secondChannelRMS > 100,
                     "Speech on input channel 2 must survive mono conversion (RMS \(secondChannelRMS))")

        let monoRMS = try convert(channels: 1, signalChannel: 0)
        precondition(monoRMS > 100,
                     "A mono microphone must remain audible after conversion (RMS \(monoRMS))")

        let silentRMS = try convert(channels: 2, signalChannel: nil)
        precondition(silentRMS == 0,
                     "Silent input must remain silent after conversion (RMS \(silentRMS))")

        print("Audio conversion: 3 synthetic PCM scenarios passed (channel 2, mono, silence)")

        testConfigurationChanges()
    }

    static func testConfigurationChanges() {
        let expectedDevice = AudioInputDevice(id: 42, uid: "selected-microphone", name: "Selected Microphone")
        let otherDevice = AudioInputDevice(id: 17, uid: "other-microphone", name: "Other Microphone")
        let expectedFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false
        )!
        let equivalentFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false
        )!
        var checked = 0

        func expect(
            _ expectedAction: AudioCaptureConfigurationAction,
            currentDeviceID: UInt32?,
            devices: [AudioInputDevice],
            format: AVAudioFormat,
            isRunning: Bool,
            _ description: String
        ) {
            let action = AudioRecorder.configurationAction(
                expectedDevice: expectedDevice,
                currentDeviceID: currentDeviceID,
                availableDevices: devices,
                expectedFormat: expectedFormat,
                currentFormat: format,
                isRunning: isRunning
            )
            precondition(action == expectedAction,
                         "\(description): expected \(expectedAction), got \(action)")
            checked += 1
        }

        expect(.unchanged, currentDeviceID: expectedDevice.id, devices: [otherDevice, expectedDevice],
               format: equivalentFormat, isRunning: true,
               "A benign configuration notification must preserve a running capture")
        expect(.restart, currentDeviceID: expectedDevice.id, devices: [expectedDevice],
               format: equivalentFormat, isRunning: false,
               "An unchanged input must allow a stopped engine to restart")
        expect(.fail, currentDeviceID: expectedDevice.id, devices: [otherDevice],
               format: expectedFormat, isRunning: true,
               "A disconnected input must fail even if its stale numeric ID is reported")

        let replacementDevice = AudioInputDevice(id: expectedDevice.id, uid: "replacement-microphone", name: expectedDevice.name)
        expect(.fail, currentDeviceID: expectedDevice.id, devices: [replacementDevice],
               format: expectedFormat, isRunning: true,
               "A reused numeric ID must not disguise a different microphone")
        expect(.fail, currentDeviceID: nil, devices: [expectedDevice],
               format: expectedFormat, isRunning: true,
               "An unreadable current device must fail")
        expect(.fail, currentDeviceID: otherDevice.id, devices: [expectedDevice, otherDevice],
               format: expectedFormat, isRunning: true,
               "An unexpected input switch must fail")

        let changedRate = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false
        )!
        let changedChannels = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false
        )!
        let changedPCM = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: false
        )!
        let changedInterleaving = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true
        )!
        for (format, description) in [
            (changedRate, "A changed sample rate must fail"),
            (changedChannels, "A changed channel count must fail"),
            (changedPCM, "A changed PCM representation must fail"),
            (changedInterleaving, "Changed channel interleaving must fail")
        ] {
            expect(.fail, currentDeviceID: expectedDevice.id, devices: [expectedDevice],
                   format: format, isRunning: true, description)
        }
        expect(.fail, currentDeviceID: expectedDevice.id, devices: [expectedDevice],
               format: changedRate, isRunning: false,
               "A stopped engine must not restart with an incompatible format")

        print("Audio configuration: \(checked) synthetic regression checks passed")
    }
}

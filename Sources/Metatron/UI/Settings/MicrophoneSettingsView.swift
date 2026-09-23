import SwiftUI

struct MicrophoneSettingsView: View {
    @ObservedObject private var microphone = MicrophoneController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Input")
                .font(.headline)

            Picker("Microphone", selection: $microphone.selectedInputUID) {
                Text("System Default").tag("")
                ForEach(microphone.availableInputs) { device in
                    Text(device.name).tag(device.uid)
                }
                if !microphone.selectedInputUID.isEmpty,
                   !microphone.availableInputs.contains(where: { $0.uid == microphone.selectedInputUID }) {
                    Text("Saved microphone (unavailable)").tag(microphone.selectedInputUID)
                }
            }
            .pickerStyle(.menu)
            .disabled(microphone.isRecording)

            Text(deviceDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)

            Text("Microphone Test")
                .font(.headline)

            HStack {
                Text(microphone.isTesting ? "Listening to microphone…" : "Input level")
                Spacer()
                Button(microphone.isTesting || microphone.isRequestingPermission ? "Stop Test" : "Test Microphone") {
                    if microphone.isTesting || microphone.isRequestingPermission {
                        microphone.stopTest()
                    } else {
                        microphone.startTest()
                    }
                }
                .disabled(microphone.isRecording || microphone.selectedDevice == nil)
            }

            ProgressView(value: Double(microphone.testLevel), total: 1)
                .tint(.green)
                .accessibilityLabel("Microphone input level")
                .accessibilityValue("\(Int(microphone.testLevel * 100)) percent")

            Text(microphone.isRecording
                 ? "Finish your dictation before changing or testing the microphone."
                 : "Start the test and speak to check the input level. Audio stays on this Mac and is never saved or transcribed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = microphone.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { microphone.beginMonitoring() }
        .onDisappear { microphone.endMonitoring() }
    }

    private var deviceDescription: String {
        if let activeName = microphone.activeInputName {
            return "Using \(activeName)"
        }
        if let device = microphone.selectedDevice {
            return microphone.selectedInputUID.isEmpty
                ? "Follows your Mac’s default input. Currently: \(device.name)."
                : "Dictation will use \(device.name)."
        }
        return microphone.selectedInputUID.isEmpty
            ? "No input microphone is available. Connect a microphone to continue."
            : "Your saved microphone is unavailable. Reconnect it or choose another input."
    }
}

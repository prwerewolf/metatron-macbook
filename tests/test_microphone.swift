import Foundation

// Compile with Sources/Metatron/Core/AudioInputDevice.swift. These fixtures
// exercise selection only; no microphone permission or audio engine is needed.
@main
struct MicrophoneSelectionTests {
    static func main() throws {
        let builtIn = AudioInputDevice(id: 17, uid: "built-in-microphone", name: "Mac Microphone")
        let headset = AudioInputDevice(id: 42, uid: "usb-headset", name: "USB Headset")
        let devices = [builtIn, headset]
        var checked = 0

        func expect(_ actual: AudioInputDevice, _ expected: AudioInputDevice, _ description: String) {
            precondition(actual == expected, "\(description): expected \(expected), got \(actual)")
            checked += 1
        }

        func expectUnavailable(
            selectedUID: String,
            devices: [AudioInputDevice],
            systemDefaultID: UInt32?,
            _ description: String
        ) {
            do {
                let selected = try AudioInputSelection.resolve(
                    selectedUID: selectedUID,
                    devices: devices,
                    systemDefaultID: systemDefaultID
                )
                preconditionFailure("\(description): unexpectedly selected \(selected)")
            } catch {
                checked += 1
            }
        }

        expect(
            try AudioInputSelection.resolve(selectedUID: "", devices: devices, systemDefaultID: builtIn.id),
            builtIn,
            "System selection must resolve the current default input"
        )
        expect(
            try AudioInputSelection.resolve(selectedUID: "", devices: devices, systemDefaultID: headset.id),
            headset,
            "System selection must follow a changed default input"
        )
        expect(
            try AudioInputSelection.resolve(selectedUID: headset.uid, devices: devices, systemDefaultID: builtIn.id),
            headset,
            "An explicit microphone must override the system default"
        )
        expect(
            try AudioInputSelection.resolve(selectedUID: headset.uid, devices: devices, systemDefaultID: nil),
            headset,
            "An explicit microphone must work without a system default"
        )

        // Hardware IDs can change after reconnecting or restarting the Mac.
        // The old numeric ID may even be reused by a different microphone.
        let reconnectedHeadset = AudioInputDevice(id: 91, uid: headset.uid, name: "USB Headset")
        let replacementDefault = AudioInputDevice(id: headset.id, uid: builtIn.uid, name: builtIn.name)
        expect(
            try AudioInputSelection.resolve(
                selectedUID: headset.uid,
                devices: [replacementDefault, reconnectedHeadset],
                systemDefaultID: replacementDefault.id
            ),
            reconnectedHeadset,
            "An explicit selection must persist by UID when hardware IDs change"
        )

        expectUnavailable(
            selectedUID: headset.uid, devices: [builtIn], systemDefaultID: builtIn.id,
            "A disconnected explicit microphone must not fall back to another input"
        )
        expectUnavailable(
            selectedUID: headset.uid, devices: [], systemDefaultID: nil,
            "An explicit microphone must be unavailable when there are no inputs"
        )
        expectUnavailable(
            selectedUID: "", devices: [], systemDefaultID: nil,
            "System selection must fail when there are no inputs or default"
        )
        expectUnavailable(
            selectedUID: "", devices: devices, systemDefaultID: nil,
            "System selection must not guess when no default exists"
        )
        expectUnavailable(
            selectedUID: "", devices: devices, systemDefaultID: 999,
            "System selection must fail when the default is absent from available inputs"
        )
        expectUnavailable(
            selectedUID: "", devices: [], systemDefaultID: builtIn.id,
            "A stale default must not select an input from an empty list"
        )

        print("Microphone selection: \(checked) regression checks passed")
    }
}

import Foundation
import Combine

/// Settings and meter state are separate from dictation's waveform callback.
public final class MicrophoneController: ObservableObject {
    public static let shared = MicrophoneController()
    private static let preferenceKey = "metatron_microphone_uid"

    @Published public var selectedInputUID: String {
        didSet {
            guard selectedInputUID != oldValue else { return }
            stopTest()
            errorMessage = nil
            UserDefaults.standard.set(selectedInputUID, forKey: Self.preferenceKey)
        }
    }
    @Published public private(set) var availableInputs: [AudioInputDevice] = []
    @Published public private(set) var systemDefaultID: UInt32?
    @Published public private(set) var isTesting = false
    @Published public private(set) var isRequestingPermission = false
    @Published public private(set) var testLevel: Float = 0
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var activeInputName: String?
    @Published public private(set) var isRecording = false

    private var refreshTimer: Timer?
    private var permissionRequestID: UUID?

    private init() {
        selectedInputUID = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? ""
        refreshDevices()
    }

    public var selectedDevice: AudioInputDevice? {
        try? AudioInputSelection.resolve(selectedUID: selectedInputUID, devices: availableInputs, systemDefaultID: systemDefaultID)
    }

    public func refreshDevices() {
        availableInputs = AudioInputCatalog.devices()
        systemDefaultID = AudioInputCatalog.defaultDeviceID()
        if isTesting, selectedDevice == nil {
            stopTest()
            errorMessage = MicrophoneError.disconnected.localizedDescription
        }
    }

    public func beginMonitoring() {
        refreshDevices()
        refreshTimer?.invalidate()
        // Refresh while Settings is visible to reflect hot-plugged devices. This
        // only enumerates Core Audio devices; it never opens the microphone.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    public func endMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopTest()
    }

    public func startTest() {
        guard !isTesting, !isRequestingPermission else { return }
        guard !AudioRecorder.shared.isRecording else {
            errorMessage = MicrophoneError.recordingInProgress.localizedDescription
            return
        }
        errorMessage = nil
        refreshDevices()
        if AudioRecorder.shared.hasPermission {
            activateTest()
            return
        }

        let requestID = UUID()
        permissionRequestID = requestID
        isRequestingPermission = true
        AudioRecorder.shared.requestPermission { [weak self] granted in
            guard let self, self.permissionRequestID == requestID else { return }
            self.permissionRequestID = nil
            self.isRequestingPermission = false
            if granted {
                self.activateTest()
            } else {
                self.errorMessage = "Allow microphone access in System Settings → Privacy & Security → Microphone to test your input."
            }
        }
    }

    private func activateTest() {
        guard !AudioRecorder.shared.isRecording else { return }
        do {
            let device = try AudioRecorder.shared.startMicrophoneTest(
                onLevel: { [weak self] level in self?.testLevel = level },
                onFailure: { [weak self] error in
                    self?.isTesting = false
                    self?.testLevel = 0
                    self?.activeInputName = nil
                    self?.errorMessage = error.localizedDescription
                }
            )
            activeInputName = device.name
            isTesting = true
        } catch {
            isTesting = false
            testLevel = 0
            errorMessage = error.localizedDescription
        }
    }

    public func stopTest() {
        permissionRequestID = nil
        isRequestingPermission = false
        AudioRecorder.shared.stopMicrophoneTest()
        isTesting = false
        testLevel = 0
        if !isRecording { activeInputName = nil }
    }

    func recordingStarted(device: AudioInputDevice) {
        isRecording = true
        activeInputName = device.name
        errorMessage = nil
    }

    func recordingStopped() {
        isRecording = false
        activeInputName = nil
    }
}

import Foundation

public final class LocalDaemonClient: SpeechEngineProtocol, @unchecked Sendable {
    public static let shared = LocalDaemonClient()

    private let socketPath = "/tmp/metatron.sock"

    private init() {}

    private func defaultDaemonScriptPath() -> String {
        let inAppScript = Bundle.main.bundlePath + "/Contents/Resources/whisper_daemon.py"
        let sourceScript = "/path/to/user/Documents/_codeRepos/metatron-macbook/daemon/whisper_daemon.py"
        if FileManager.default.fileExists(atPath: inAppScript) {
            return inAppScript
        }
        return sourceScript
    }

    /// Checks if the local MLX daemon is responsive on the Unix socket
    public func isDaemonRunning() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let rawPtr = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBytes { src in
                rawPtr.copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, addrLen)
            }
        }

        return result == 0
    }

    /// Automatically launches the resident daemon if not already active
    public func ensureDaemonRunning(daemonScriptPath: String? = nil) {
        if isDaemonRunning() { return }

        let script = daemonScriptPath ?? defaultDaemonScriptPath()
        NSLog("[Metatron] Launching detached MLX daemon at \(script)...")

        let venvPython = "/path/to/user/Documents/_codeRepos/metatron-macbook/.venv/bin/python3"
        let pythonPath = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "/usr/bin/python3"

        // Launch detached in background with unbuffered output
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "nohup \"\(pythonPath)\" -u \"\(script)\" > /tmp/metatron_daemon.log 2>&1 &"]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("[Metatron] Error spawning daemon process: \(error)")
        }

        // Wait up to 3 seconds for socket to become ready
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.2)
            if isDaemonRunning() {
                NSLog("[Metatron] Daemon socket is live and ready.")
                break
            }
        }
    }

    /// Sends audio file path to local daemon over Unix domain socket and reads transcription
    public func transcribe(audioFileURL: URL) async throws -> String {
        let currentSocketPath = self.socketPath

        // 1. Auto-heal: Ensure daemon is running before attempting socket connection
        if !self.isDaemonRunning() {
            self.ensureDaemonRunning()
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                    guard fd >= 0 else {
                        throw NSError(domain: "MetatronLocal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create Unix socket"])
                    }
                    defer { close(fd) }

                    // Allow up to 45s for model processing
                    var tv = timeval(tv_sec: 45, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                    var addr = sockaddr_un()
                    addr.sun_family = sa_family_t(AF_UNIX)

                    let pathBytes = currentSocketPath.utf8CString
                    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                        let rawPtr = UnsafeMutableRawPointer(ptr)
                        pathBytes.withUnsafeBytes { src in
                            rawPtr.copyMemory(from: src.baseAddress!, byteCount: src.count)
                        }
                    }

                    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                    var connectRes = withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                            connect(fd, sockPtr, addrLen)
                        }
                    }

                    // Retry if connect failed
                    if connectRes != 0 {
                        self.ensureDaemonRunning()
                        for _ in 0..<10 {
                            Thread.sleep(forTimeInterval: 0.3)
                            connectRes = withUnsafePointer(to: &addr) { ptr in
                                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                                    connect(fd, sockPtr, addrLen)
                                }
                            }
                            if connectRes == 0 { break }
                        }
                    }

                    guard connectRes == 0 else {
                        throw NSError(domain: "MetatronLocal", code: 2, userInfo: [NSLocalizedDescriptionKey: "MLX engine is starting up. Please hold Fn again in a moment."])
                    }

                    // Send payload: JSON {"action":"transcribe", "path":"..."}\n
                    let request: [String: Any] = [
                        "action": "transcribe",
                        "path": audioFileURL.path
                    ]
                    let jsonData = try JSONSerialization.data(withJSONObject: request)
                    var payload = jsonData
                    payload.append(contentsOf: [0x0A]) // \n

                    try payload.withUnsafeBytes { rawBuffer in
                        guard let ptr = rawBuffer.baseAddress else { return }
                        var totalSent = 0
                        while totalSent < rawBuffer.count {
                            let sent = write(fd, ptr.advanced(by: totalSent), rawBuffer.count - totalSent)
                            if sent <= 0 {
                                throw NSError(domain: "MetatronLocal", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to write to daemon socket"])
                            }
                            totalSent += sent
                        }
                    }

                    // Read response until newline
                    var responseData = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)

                    while true {
                        let bytesRead = read(fd, &buffer, buffer.count)
                        if bytesRead <= 0 { break }
                        responseData.append(buffer, count: bytesRead)
                        if responseData.contains(0x0A) { break }
                    }

                    guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                        throw NSError(domain: "MetatronLocal", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response from transcription engine"])
                    }

                    if let errorMsg = json["error"] as? String {
                        throw NSError(domain: "MetatronLocal", code: 5, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                    }

                    guard let text = json["text"] as? String else {
                        throw NSError(domain: "MetatronLocal", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing text in daemon response"])
                    }

                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

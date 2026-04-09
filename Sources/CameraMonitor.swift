import Foundation
import CoreMediaIO
import Cocoa
import Darwin

struct CameraProcess: Equatable {
    let pid: pid_t
    let name: String
    let bundleID: String?
}

class CameraMonitor {
    private var pollTimer: Timer?
    private var allowedPIDs: Set<pid_t> = []
    private var onCameraActive: (CameraProcess) -> Void
    private var onCameraUnidentified: () -> Void
    private var onCameraInactive: () -> Void

    // Debounced camera-off state (#7): avoids clearing allowedPIDs on brief drops
    private var confirmedCameraActive = false
    private var cameraOffDebounceTimer: Timer?
    private static let cameraOffDebounceInterval: TimeInterval = 3.0

    init(
        onCameraActive: @escaping (CameraProcess) -> Void,
        onCameraUnidentified: @escaping () -> Void,
        onCameraInactive: @escaping () -> Void
    ) {
        self.onCameraActive = onCameraActive
        self.onCameraUnidentified = onCameraUnidentified
        self.onCameraInactive = onCameraInactive
    }

    func startMonitoring() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let timer = pollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        cameraOffDebounceTimer?.invalidate()
        cameraOffDebounceTimer = nil
    }

    func allowProcess(_ pid: pid_t) {
        assert(Thread.isMainThread)
        allowedPIDs.insert(pid)
    }

    /// Resume a previously frozen process.
    func resumeProcess(_ pid: pid_t) {
        guard pid > 0 else { return }
        kill(pid, SIGCONT)
    }

    /// Kill a previously frozen process.
    /// Fix #4: shortened delay (200ms) to reduce PID-reuse window.
    func killProcess(_ pid: pid_t) {
        guard pid > 0 else { return }
        kill(pid, SIGCONT)
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Polling

    private func poll() {
        assert(Thread.isMainThread)
        let isActive = isCameraRunning()

        if isActive {
            // Camera is on — cancel any pending off-debounce
            cameraOffDebounceTimer?.invalidate()
            cameraOffDebounceTimer = nil

            if !confirmedCameraActive {
                // Camera just turned ON
                confirmedCameraActive = true
                let process = identifyProcess()

                // Fix #2: if pid is 0, don't freeze or show a blocking modal
                guard process.pid > 0 else {
                    onCameraUnidentified()
                    return
                }

                if allowedPIDs.contains(process.pid) {
                    return
                }

                // SIGSTOP: freeze the process immediately
                kill(process.pid, SIGSTOP)
                onCameraActive(process)
            }
        } else if confirmedCameraActive && cameraOffDebounceTimer == nil {
            // Fix #7: debounce camera-off — wait before declaring inactive.
            // Avoids re-prompting on brief camera drops during a video call.
            cameraOffDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: Self.cameraOffDebounceInterval,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                self.confirmedCameraActive = false
                self.allowedPIDs.removeAll()
                self.cameraOffDebounceTimer = nil
                self.onCameraInactive()
            }
            RunLoop.main.add(cameraOffDebounceTimer!, forMode: .common)
        }
    }

    // MARK: - CoreMediaIO Camera Detection

    private func isCameraRunning() -> Bool {
        let devices = getVideoDevices()
        return devices.contains { isDeviceStreaming($0) }
    }

    private func getVideoDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: 0
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)

        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, dataSize, &dataSize, &devices
        ) == noErr else {
            return []
        }

        return devices
    }

    private func isDeviceStreaming(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: 0
        )

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        guard CMIOObjectGetPropertyData(
            device, &address, 0, nil, dataSize, &dataSize, &isRunning
        ) == noErr else {
            return false
        }

        return isRunning != 0
    }

    // MARK: - Process Identification

    /// Fix #1: improved heuristic with scoring. Documented as best-effort.
    /// Scores running GUI apps by: frontmost status, active status,
    /// and whether they are known camera apps. Highest score wins.
    private func identifyProcess() -> CameraProcess {
        let knownCameraApps: Set<String> = [
            "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2",
            "com.google.Chrome", "org.mozilla.firefox", "com.apple.Safari",
            "com.apple.FaceTime", "com.skype.skype", "com.webex.meetingmanager",
            "com.discord.Discord", "com.cisco.webexmeetingsapp",
            "com.apple.PhotoBooth", "com.loom.desktop",
            "com.obsproject.obs-studio", "com.brave.Browser",
            "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
            "com.slack.Slack", "com.tinyspeck.slackmacgap",
            "com.hnc.Discord", "com.microsoft.Outlook",
        ]

        let frontApp = NSWorkspace.shared.frontmostApplication
        let runningApps = NSWorkspace.shared.runningApplications

        // Score each regular (GUI) app
        var best: (app: NSRunningApplication, score: Int)?

        for app in runningApps where app.activationPolicy == .regular {
            guard !app.isTerminated else { continue }
            var score = 0

            if app == frontApp                  { score += 3 }
            if app.isActive                     { score += 2 }
            if let bid = app.bundleIdentifier,
               knownCameraApps.contains(bid)    { score += 4 }

            if score > 0, score > (best?.score ?? 0) {
                best = (app, score)
            }
        }

        if let best = best {
            return CameraProcess(
                pid: best.app.processIdentifier,
                name: best.app.localizedName ?? best.app.bundleIdentifier ?? "Unknown",
                bundleID: best.app.bundleIdentifier
            )
        }

        // Fallback: frontmost app even if score was 0
        if let front = frontApp {
            return CameraProcess(
                pid: front.processIdentifier,
                name: front.localizedName ?? "Unknown",
                bundleID: front.bundleIdentifier
            )
        }

        return CameraProcess(pid: 0, name: "Unknown Process", bundleID: nil)
    }
}

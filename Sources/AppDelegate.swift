import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cameraMonitor: CameraMonitor!
    private let menu = NSMenu()

    // Menu item references
    private var statusMenuItem: NSMenuItem!
    private var activityHeaderItem: NSMenuItem!
    private var activitySeparator: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    // History window
    private var historyWindowController: HistoryWindowController?

    // Flashing icon state
    private var flashTimer: Timer?
    private var flashVisible = true

    // Currently allowed (running) processes — so we can revoke later
    private var activeProcesses: [pid_t: CameraProcess] = [:]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()

        cameraMonitor = CameraMonitor(
            onCameraActive: { [weak self] process in
                self?.handleCameraAccess(process)
            },
            onCameraUnidentified: { [weak self] in
                // Fix #2: pid=0 — can't freeze, show non-blocking warning
                DispatchQueue.main.async {
                    self?.statusMenuItem.title = "Camera: Active (unknown process)"
                    self?.startFlashing()
                }
            },
            onCameraInactive: { [weak self] in
                DispatchQueue.main.async {
                    self?.activeProcesses.removeAll()
                    self?.stopFlashing()
                    self?.updateStatus(active: false)
                }
            }
        )
        cameraMonitor.startMonitoring()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Guard")
            button.image?.isTemplate = true
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        statusMenuItem = NSMenuItem(title: "Camera: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        activityHeaderItem = NSMenuItem(title: "Recent activity:", action: nil, keyEquivalent: "")
        activityHeaderItem.isEnabled = false
        menu.addItem(activityHeaderItem)

        activitySeparator = NSMenuItem.separator()
        menu.addItem(activitySeparator)

        let logItem = NSMenuItem(title: "Open Activity Log…", action: #selector(openActivityLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Guard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshActivityItems()
    }

    @objc private func quit() {
        cameraMonitor.stopMonitoring()
        NSApp.terminate(nil)
    }

    // MARK: - Flashing Red Icon

    private func startFlashing() {
        guard flashTimer == nil else { return }
        flashVisible = true
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            self.flashVisible.toggle()
            if self.flashVisible {
                button.contentTintColor = .systemRed
                if let img = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Active") {
                    img.isTemplate = false
                    button.image = img
                }
            } else {
                button.contentTintColor = nil
                if let img = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Active") {
                    img.isTemplate = true
                    button.image = img
                }
            }
        }
        RunLoop.main.add(flashTimer!, forMode: .common)
    }

    private func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil
        flashVisible = true
        if let button = statusItem.button {
            button.contentTintColor = nil
            if let img = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Guard") {
                img.isTemplate = true
                button.image = img
            }
        }
    }

    // MARK: - Status Text

    private func updateStatus(active: Bool, process: CameraProcess? = nil) {
        if active, let p = process {
            statusMenuItem.title = "Camera: Suspended (\(p.name))"
        } else if !activeProcesses.isEmpty {
            let names = activeProcesses.values.map { $0.name }.joined(separator: ", ")
            statusMenuItem.title = "Camera: Active (\(names))"
        } else {
            statusMenuItem.title = "Camera: Idle"
        }
    }

    // MARK: - Camera Access Handling

    private func handleCameraAccess(_ process: CameraProcess) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let identifier = process.bundleID ?? process.name

            // Auto-block permanently blocked apps (silent — no alert)
            if BlockList.shared.isBlocked(identifier) {
                self.cameraMonitor.killProcess(process.pid)
                ActivityLog.shared.add(
                    processName: process.name, pid: process.pid,
                    bundleID: process.bundleID, action: .autoBlocked
                )
                self.refreshActivityItems()
                return
            }

            // Interactive: flash icon and show approval dialog
            self.startFlashing()
            self.updateStatus(active: true, process: process)
            self.showApprovalAlert(for: process)
        }
    }

    // MARK: - Approval Alert (process is FROZEN at this point)

    /// Fix #3: 30-second timeout auto-blocks if user doesn't respond.
    private static let approvalTimeoutSeconds: TimeInterval = 30

    private func showApprovalAlert(for process: CameraProcess) {
        let alert = NSAlert()
        alert.messageText = "Camera Access Blocked"

        var info = "\"\(process.name)\" (PID: \(process.pid)) wants to use your camera.\n"
        info += "The process is suspended until you decide."
        if let bid = process.bundleID {
            info += "\nBundle: \(bid)"
        }
        info += "\n\n(Auto-blocks in \(Int(Self.approvalTimeoutSeconds))s if no response)"

        alert.informativeText = info
        alert.alertStyle = .critical
        if let icon = NSImage(systemSymbolName: "camera.badge.ellipsis", accessibilityDescription: nil) {
            alert.icon = icon
        }

        alert.addButton(withTitle: "Allow")        // .alertFirstButtonReturn
        alert.addButton(withTitle: "Block")         // .alertSecondButtonReturn
        alert.addButton(withTitle: "Always Block")  // .alertThirdButtonReturn

        // Fix #14: use non-deprecated activate() on macOS 14+
        NSApp.activate()

        // Fix #3: timeout timer — aborts the modal after N seconds
        let timeoutTimer = Timer(timeInterval: Self.approvalTimeoutSeconds, repeats: false) { _ in
            NSApp.abortModal()
        }
        RunLoop.main.add(timeoutTimer, forMode: .common)

        let response = alert.runModal()
        timeoutTimer.invalidate()

        let identifier = process.bundleID ?? process.name

        switch response {
        case .alertFirstButtonReturn:
            // ALLOW — resume the frozen process
            cameraMonitor.allowProcess(process.pid)
            cameraMonitor.resumeProcess(process.pid)
            activeProcesses[process.pid] = process
            ActivityLog.shared.add(
                processName: process.name, pid: process.pid,
                bundleID: process.bundleID, action: .allowed
            )
            // Fix #6: stop flashing is wrong here — camera is now legitimately
            // active. But we DO need to stop the "suspended" flash pattern.
            // Keep flashing to indicate camera is in use, handled by updateStatus.
            stopFlashing()
            startFlashing()
            updateStatus(active: false)  // recalculates from activeProcesses

        case .alertSecondButtonReturn:
            // BLOCK this time
            cameraMonitor.killProcess(process.pid)
            ActivityLog.shared.add(
                processName: process.name, pid: process.pid,
                bundleID: process.bundleID, action: .blocked
            )
            stopFlashing()
            updateStatus(active: false)

        case .alertThirdButtonReturn:
            // ALWAYS BLOCK — add to permanent list + kill
            BlockList.shared.block(identifier)
            cameraMonitor.killProcess(process.pid)
            ActivityLog.shared.add(
                processName: process.name, pid: process.pid,
                bundleID: process.bundleID, action: .autoBlocked
            )
            stopFlashing()
            updateStatus(active: false)

        default:
            // TIMEOUT or abort — auto-block for safety
            cameraMonitor.killProcess(process.pid)
            ActivityLog.shared.add(
                processName: process.name, pid: process.pid,
                bundleID: process.bundleID, action: .blocked
            )
            stopFlashing()
            updateStatus(active: false)
        }

        refreshActivityItems()
    }

    // MARK: - Recent Activity Menu Items

    private func refreshActivityItems() {
        menu.items.filter { $0.tag == 100 }.forEach { menu.removeItem($0) }

        let recent = ActivityLog.shared.entries.suffix(8)

        // Fix #12-low: guard against missing header item
        guard let headerIdx = menu.items.firstIndex(of: activityHeaderItem) else { return }
        let insertIdx = headerIdx + 1

        if recent.isEmpty {
            let empty = NSMenuItem(title: "  No activity yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.tag = 100
            menu.insertItem(empty, at: insertIdx)
            return
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"

        for (i, entry) in recent.reversed().enumerated() {
            let statusLabel: String
            switch entry.action {
            case .allowed:     statusLabel = "Allowed"
            case .blocked:     statusLabel = "Blocked"
            case .autoBlocked: statusLabel = "Auto-blocked"
            }

            let item = NSMenuItem(
                title: "  \(fmt.string(from: entry.date))  \(entry.processName) — \(statusLabel)",
                action: nil, keyEquivalent: ""
            )
            item.tag = 100

            let sub = NSMenu()
            let identifier = entry.bundleID ?? entry.processName

            if entry.action == .allowed, activeProcesses[entry.pid] != nil {
                let revoke = NSMenuItem(title: "Revoke & Kill Process", action: #selector(revokeProcess(_:)), keyEquivalent: "")
                revoke.target = self
                revoke.representedObject = entry.pid
                sub.addItem(revoke)
                sub.addItem(NSMenuItem.separator())
            }

            if BlockList.shared.isBlocked(identifier) {
                let unblock = NSMenuItem(title: "Remove from Block List", action: #selector(unblockApp(_:)), keyEquivalent: "")
                unblock.target = self
                unblock.representedObject = identifier
                sub.addItem(unblock)
            } else {
                let permBlock = NSMenuItem(title: "Permanently Block", action: #selector(permanentlyBlockApp(_:)), keyEquivalent: "")
                permBlock.target = self
                permBlock.representedObject = identifier
                sub.addItem(permBlock)
            }

            item.submenu = sub
            menu.insertItem(item, at: insertIdx + i)
        }
    }

    // MARK: - Menu Actions

    @objc private func revokeProcess(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? pid_t,
              let process = activeProcesses[pid] else { return }

        cameraMonitor.killProcess(pid)
        activeProcesses.removeValue(forKey: pid)

        ActivityLog.shared.add(
            processName: process.name, pid: process.pid,
            bundleID: process.bundleID, action: .blocked
        )

        if activeProcesses.isEmpty { stopFlashing() }
        updateStatus(active: false)
        refreshActivityItems()
    }

    /// Fix #5: collect PIDs first, then mutate — avoids dict-mutation-during-iteration crash.
    @objc private func permanentlyBlockApp(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        BlockList.shared.block(identifier)

        let pidsToKill = activeProcesses
            .filter { (_, process) in (process.bundleID ?? process.name) == identifier }
            .map { $0.key }

        for pid in pidsToKill {
            cameraMonitor.killProcess(pid)
            activeProcesses.removeValue(forKey: pid)
        }

        if activeProcesses.isEmpty { stopFlashing() }
        updateStatus(active: false)
        refreshActivityItems()
    }

    @objc private func unblockApp(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        BlockList.shared.unblock(identifier)
        refreshActivityItems()
    }

    // MARK: - Activity Log Window

    @objc private func openActivityLog() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        historyWindowController?.openWindow()
    }

    // MARK: - Launch at Login (LaunchAgent)

    @objc private func toggleLaunchAtLogin() {
        let enable = !isLaunchAtLoginEnabled()
        let success = setLaunchAtLogin(enable)
        if success {
            launchAtLoginItem.state = enable ? .on : .off
        } else {
            // Fix #10: show error if plist write failed
            let alert = NSAlert()
            alert.messageText = "Failed to update login item"
            alert.informativeText = "Could not write to ~/Library/LaunchAgents/. Check disk permissions."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.guard-app.mac.plist"
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    /// Fix #9: use direct executable path instead of /usr/bin/open.
    /// Fix #10: return success/failure instead of silently ignoring.
    @discardableResult
    private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        if enabled {
            let execPath = Bundle.main.executablePath ?? Bundle.main.bundlePath + "/Contents/MacOS/Guard"
            let plist: NSDictionary = [
                "Label": "com.guard-app.mac",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            let dir = (launchAgentPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            return plist.write(toFile: launchAgentPath, atomically: true)
        } else {
            do {
                try FileManager.default.removeItem(atPath: launchAgentPath)
                return true
            } catch {
                return !FileManager.default.fileExists(atPath: launchAgentPath)
            }
        }
    }
}

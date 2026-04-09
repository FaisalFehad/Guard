import Cocoa

class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var tableView: NSTableView!
    private var entries: [ActivityEntry] = []

    // Fix #11: reuse DateFormatter instead of creating one per cell render
    private let dateFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt
    }()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Guard — Activity Log"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 300)

        self.init(window: window)
        setupUI()
        loadData()

        NotificationCenter.default.addObserver(
            self, selector: #selector(dataDidChange),
            name: .activityLogUpdated, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        tableView = NSTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("date",    "Date & Time",  160),
            ("process", "Process",      170),
            ("pid",     "PID",           60),
            ("bundle",  "Bundle ID",    210),
            ("action",  "Action",       110),
        ]
        for col in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            column.title = col.title
            column.width = col.width
            column.minWidth = 40
            tableView.addTableColumn(column)
        }

        tableView.dataSource = self
        tableView.delegate = self

        // Scroll view wrapping the table
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Bottom bar
        let clearButton = NSButton(title: "Clear History", target: self, action: #selector(clearHistory))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .rounded

        let blockListButton = NSButton(title: "Manage Block List…", target: self, action: #selector(showBlockList))
        blockListButton.translatesAutoresizingMaskIntoConstraints = false
        blockListButton.bezelStyle = .rounded

        let countLabel = NSTextField(labelWithString: "")
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.tag = 999  // we'll find it later to update
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 11)

        contentView.addSubview(scrollView)
        contentView.addSubview(clearButton)
        contentView.addSubview(blockListButton)
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: clearButton.topAnchor, constant: -8),

            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            clearButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

            blockListButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            blockListButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),

            countLabel.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),
            countLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
    }

    // MARK: - Data

    private func loadData() {
        entries = ActivityLog.shared.entries.reversed()  // newest first
        tableView?.reloadData()
        updateCountLabel()
    }

    @objc private func dataDidChange() {
        DispatchQueue.main.async { [weak self] in self?.loadData() }
    }

    private func updateCountLabel() {
        guard let contentView = window?.contentView else { return }
        if let label = contentView.viewWithTag(999) as? NSTextField {
            let total = entries.count
            let blocked = entries.filter { $0.action == .blocked || $0.action == .autoBlocked }.count
            label.stringValue = "\(total) events  ·  \(blocked) blocked"
        }
    }

    // MARK: - Actions

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Activity Log?"
        alert.informativeText = "This removes all history entries. The permanent block list is not affected."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            ActivityLog.shared.clear()
        }
    }

    @objc private func showBlockList() {
        let blocked = BlockList.shared.blockedIdentifiers.sorted()

        let alert = NSAlert()
        alert.messageText = "Permanently Blocked Apps"

        if blocked.isEmpty {
            alert.informativeText = "No apps are permanently blocked."
            alert.addButton(withTitle: "OK")
        } else {
            alert.informativeText = blocked.joined(separator: "\n")
            alert.addButton(withTitle: "Done")
            alert.addButton(withTitle: "Clear All Blocks")
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            for id in blocked { BlockList.shared.unblock(id) }
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colID = tableColumn?.identifier.rawValue, row < entries.count else { return nil }

        let entry = entries[row]
        let cellID = NSUserInterfaceItemIdentifier("Cell_\(colID)")

        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellID
            cell.lineBreakMode = .byTruncatingTail
            cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        cell.textColor = .labelColor  // reset

        switch colID {
        case "date":
            cell.stringValue = dateFmt.string(from: entry.date)
        case "process":
            cell.stringValue = entry.processName
        case "pid":
            cell.stringValue = "\(entry.pid)"
        case "bundle":
            cell.stringValue = entry.bundleID ?? "—"
        case "action":
            switch entry.action {
            case .allowed:
                cell.stringValue = "Allowed"
                cell.textColor = .systemGreen
            case .blocked:
                cell.stringValue = "Blocked"
                cell.textColor = .systemRed
            case .autoBlocked:
                cell.stringValue = "Auto-blocked"
                cell.textColor = .systemOrange
            }
        default:
            cell.stringValue = ""
        }

        return cell
    }

    // MARK: - Public

    func openWindow() {
        loadData()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

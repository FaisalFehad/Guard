import Foundation

// MARK: - Data Types

enum ActivityAction: String, Codable {
    case allowed
    case blocked
    case autoBlocked
}

struct ActivityEntry: Codable {
    let id: UUID
    let date: Date
    let processName: String
    let pid: Int32
    let bundleID: String?
    let action: ActivityAction

    init(processName: String, pid: Int32, bundleID: String?, action: ActivityAction) {
        self.id = UUID()
        self.date = Date()
        self.processName = processName
        self.pid = pid
        self.bundleID = bundleID
        self.action = action
    }
}

// MARK: - Activity Log (persisted to JSON file)

class ActivityLog {
    static let shared = ActivityLog()

    private(set) var entries: [ActivityEntry] = []
    private let fileURL: URL

    // Fix #8: guard the Application Support URL instead of force-unwrapping
    private init() {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("Guard", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("activity_log.json")
        } else {
            // Fallback to tmp if Application Support is unavailable
            fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("Guard_activity_log.json")
        }
        load()
    }

    func add(processName: String, pid: Int32, bundleID: String?, action: ActivityAction) {
        let entry = ActivityEntry(
            processName: processName, pid: pid,
            bundleID: bundleID, action: action
        )
        entries.append(entry)
        save()
        NotificationCenter.default.post(name: .activityLogUpdated, object: nil)
    }

    func clear() {
        entries.removeAll()
        save()
        NotificationCenter.default.post(name: .activityLogUpdated, object: nil)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([ActivityEntry].self, from: data)) ?? []
    }
}

// MARK: - Permanent Block List (persisted to UserDefaults)

class BlockList {
    static let shared = BlockList()

    private let key = "PermanentlyBlockedApps"

    var blockedIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    func isBlocked(_ identifier: String?) -> Bool {
        guard let id = identifier, !id.isEmpty else { return false }
        return blockedIdentifiers.contains(id)
    }

    /// Block by bundle ID (preferred) or process name as fallback identifier.
    func block(_ identifier: String) {
        var list = blockedIdentifiers
        list.insert(identifier)
        blockedIdentifiers = list
    }

    func unblock(_ identifier: String) {
        var list = blockedIdentifiers
        list.remove(identifier)
        blockedIdentifiers = list
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let activityLogUpdated = Notification.Name("Guard.activityLogUpdated")
}

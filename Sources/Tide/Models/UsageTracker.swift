import Foundation
import Observation

struct ProjectStats: Codable, Hashable {
    var firstOpened: Date?
    var lastOpened: Date?
    var sessionCount: Int = 0
    var totalActiveSeconds: TimeInterval = 0
    var dayBuckets: [String: TimeInterval] = [:]
    var lastFocusedAt: Date?
}

@Observable
@MainActor
final class UsageTracker {
    var statsByID: [String: ProjectStats] = [:]

    @ObservationIgnored private var currentFocus: UUID?
    @ObservationIgnored private var focusStart: Date?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTimer: Timer?

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Tide", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("usage.json")
        load()
    }

    func recordSessionStart(projectID: UUID) {
        let now = Date()
        update(projectID) { s in
            s.firstOpened = s.firstOpened ?? now
            s.lastOpened = now
            s.sessionCount += 1
        }
    }

    func setFocus(projectID: UUID?) {
        let now = Date()
        if let prev = currentFocus, let start = focusStart {
            let delta = now.timeIntervalSince(start)
            if delta >= 0.5 {
                recordActiveSeconds(projectID: prev, seconds: delta, at: start)
            }
        }
        currentFocus = projectID
        focusStart = projectID != nil ? now : nil
        if let p = projectID {
            update(p) { $0.lastFocusedAt = now }
        }
    }

    func flush() {
        let now = Date()
        if let prev = currentFocus, let start = focusStart {
            let delta = now.timeIntervalSince(start)
            if delta >= 0.5 {
                recordActiveSeconds(projectID: prev, seconds: delta, at: start)
            }
            focusStart = now
        }
        save()
    }

    func stats(for id: UUID) -> ProjectStats {
        statsByID[id.uuidString] ?? ProjectStats()
    }

    var totalActiveTodaySeconds: TimeInterval {
        let key = Self.dayKey(Date())
        return statsByID.values.reduce(0) { $0 + ($1.dayBuckets[key] ?? 0) }
    }

    var totalAllTimeSeconds: TimeInterval {
        statsByID.values.reduce(0) { $0 + $1.totalActiveSeconds }
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    static func formatRelativeDate(_ date: Date?) -> String {
        guard let date else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func recordActiveSeconds(projectID: UUID, seconds: TimeInterval, at start: Date) {
        update(projectID) { s in
            s.totalActiveSeconds += seconds
            let key = Self.dayKey(start)
            s.dayBuckets[key, default: 0] += seconds
        }
    }

    private func update(_ id: UUID, _ mutate: (inout ProjectStats) -> Void) {
        let key = id.uuidString
        var s = statsByID[key] ?? ProjectStats()
        mutate(&s)
        statsByID[key] = s
        scheduleSave()
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.save() }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let obj = try? dec.decode([String: ProjectStats].self, from: data) {
            statsByID = obj
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(statsByID) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

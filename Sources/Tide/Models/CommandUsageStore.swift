import Foundation
import Observation

@Observable
@MainActor
final class CommandUsageStore {
    private struct Entry: Codable {
        var count: Int
        var lastUsed: Date
    }

    private var entries: [String: Entry] = [:]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveScheduled = false

    init() {
        self.fileURL = TideStorage.file("command_usage.json")
        load()
    }

    func record(_ command: String) {
        let key = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var entry = entries[key] ?? Entry(count: 0, lastUsed: .distantPast)
        entry.count += 1
        entry.lastUsed = Date()
        entries[key] = entry
        scheduleSave()
    }

    func count(for command: String) -> Int {
        entries[command.trimmingCharacters(in: .whitespacesAndNewlines)]?.count ?? 0
    }

    func lastUsed(for command: String) -> Date {
        entries[command.trimmingCharacters(in: .whitespacesAndNewlines)]?.lastUsed ?? .distantPast
    }

    /// Higher = more recently / more often used. Stable across launches.
    func priority(for command: String) -> (count: Int, lastUsed: Date) {
        let key = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = entries[key]
        return (entry?.count ?? 0, entry?.lastUsed ?? .distantPast)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            self.persist()
        }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

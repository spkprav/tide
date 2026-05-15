import Foundation
import Observation

@Observable
@MainActor
final class SnippetStore {
    var snippets: [Snippet] = []

    @ObservationIgnored private let fileURL: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Tide", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else {
            return
        }
        snippets = decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ s: Snippet) {
        snippets.append(s)
        save()
    }

    func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    func update(_ s: Snippet) {
        if let i = snippets.firstIndex(where: { $0.id == s.id }) {
            snippets[i] = s
            save()
        }
    }

    func relevant(for projectID: UUID?) -> [Snippet] {
        snippets.filter { $0.isGlobal || $0.scopeProjectID == projectID }
    }

    @discardableResult
    func bulkImport(_ items: [(name: String, command: String)]) -> (added: Int, skipped: Int) {
        var added = 0
        var skipped = 0
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespaces)
            let command = item.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !command.isEmpty else { skipped += 1; continue }
            if snippets.contains(where: { $0.name == name && $0.command == command && $0.isGlobal }) {
                skipped += 1
                continue
            }
            snippets.append(Snippet(name: name, command: command))
            added += 1
        }
        save()
        return (added, skipped)
    }
}

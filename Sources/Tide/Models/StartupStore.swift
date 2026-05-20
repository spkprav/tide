import Foundation
import Observation

struct ProjectStartups: Codable, Identifiable, Hashable {
    var id: UUID { projectID }
    let projectID: UUID
    var configs: [StartupConfig]
}

@Observable
@MainActor
final class StartupStore {
    var entries: [ProjectStartups] = []

    @ObservationIgnored private let fileURL: URL

    init() {
        self.fileURL = TideStorage.file("startups.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ProjectStartups].self, from: data) else {
            return
        }
        entries = decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func configs(for projectID: UUID) -> [StartupConfig] {
        entries.first(where: { $0.projectID == projectID })?.configs ?? []
    }

    func primaryConfig(for projectID: UUID) -> StartupConfig? {
        configs(for: projectID).first
    }

    func upsert(_ config: StartupConfig, for projectID: UUID) {
        if let i = entries.firstIndex(where: { $0.projectID == projectID }) {
            if let j = entries[i].configs.firstIndex(where: { $0.id == config.id }) {
                entries[i].configs[j] = config
            } else {
                entries[i].configs.append(config)
            }
        } else {
            entries.append(ProjectStartups(projectID: projectID, configs: [config]))
        }
        save()
    }

    func remove(_ configID: UUID, from projectID: UUID) {
        guard let i = entries.firstIndex(where: { $0.projectID == projectID }) else { return }
        entries[i].configs.removeAll { $0.id == configID }
        if entries[i].configs.isEmpty {
            entries.remove(at: i)
        }
        save()
    }

    func exportConfig(_ config: StartupConfig) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(config)
    }

    func importConfig(from data: Data) -> StartupConfig? {
        try? JSONDecoder().decode(StartupConfig.self, from: data)
    }
}

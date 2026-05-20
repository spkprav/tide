import Foundation
import Observation

@Observable
@MainActor
final class ProjectStore {
    var projects: [Project] = []
    var selectedID: Project.ID?

    @ObservationIgnored var sessions: [UUID: ProjectSession] = [:]
    @ObservationIgnored private let fileURL: URL

    init() {
        self.fileURL = TideStorage.file("projects.json")
        load()
        ensurePinned()
    }

    private func ensurePinned() {
        if projects.contains(where: { $0.isPinned }) { return }
        let scratch = Project(
            name: "Scratch",
            path: NSHomeDirectory(),
            colorHex: "#7DCFFF",
            isPinned: true
        )
        projects.insert(scratch, at: 0)
        if selectedID == nil { selectedID = scratch.id }
        save()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            return
        }
        projects = decoded
        selectedID = decoded.first?.id
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(projects) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ p: Project) {
        projects.append(p)
        selectedID = p.id
        save()
    }

    func remove(id: Project.ID) {
        if let p = projects.first(where: { $0.id == id }), p.isPinned { return }
        projects.removeAll { $0.id == id }
        sessions.removeValue(forKey: id)
        if selectedID == id {
            selectedID = projects.first?.id
        }
        save()
    }

    func update(_ p: Project) {
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i] = p
            save()
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        save()
    }

    var selected: Project? {
        projects.first { $0.id == selectedID }
    }

    func session(for project: Project) -> ProjectSession {
        if let s = sessions[project.id] {
            s.projectName = project.name
            return s
        }
        let s = ProjectSession(cwd: project.expandedPath, projectName: project.name)
        sessions[project.id] = s
        return s
    }

    var totalActivePaneCount: Int {
        sessions.values.reduce(0) { acc, s in
            guard s.started else { return acc }
            return acc + s.tabs.reduce(0) { $0 + $1.terminals.count }
        }
    }

    var totalArmedReminderCount: Int {
        sessions.values.reduce(0) { acc, s in
            acc + s.tabs.reduce(0) { $0 + $1.reminders.count }
        }
    }

    func exportJSON() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(projects)
    }

    @discardableResult
    func importJSON(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode([Project].self, from: data) else {
            return false
        }
        projects = decoded
        save()
        return true
    }
}

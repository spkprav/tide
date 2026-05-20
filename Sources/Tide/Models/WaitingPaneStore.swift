import Foundation
import Observation

struct WaitingPane: Identifiable, Hashable {
    let id: UUID            // sessionID of the pane
    var projectName: String
    var paneTitle: String
    var message: String
    var startedAt: Date
}

@Observable
@MainActor
final class WaitingPaneStore {
    private(set) var waiting: [WaitingPane] = []

    func upsert(_ entry: WaitingPane) {
        if let i = waiting.firstIndex(where: { $0.id == entry.id }) {
            var copy = entry
            copy.startedAt = waiting[i].startedAt   // preserve original arrival time
            waiting[i] = copy
        } else {
            waiting.append(entry)
        }
    }

    func dismiss(id: UUID) {
        waiting.removeAll { $0.id == id }
    }

    func dismissAll() {
        waiting.removeAll()
    }

    func contains(id: UUID) -> Bool {
        waiting.contains { $0.id == id }
    }
}

import Foundation

struct ServiceRuntimeSnapshot: Codable, Hashable {
    let serviceID: UUID
    let pid: pid_t
    let startSec: UInt64
    let startUsec: UInt64
    let execPath: String
    let detectedPort: Int?
}

@MainActor
final class ServiceRuntimeStore {
    private let fileURL: URL
    private(set) var snapshots: [UUID: ServiceRuntimeSnapshot] = [:]

    init() {
        self.fileURL = TideStorage.file("service-runtime.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let arr = try? JSONDecoder().decode([ServiceRuntimeSnapshot].self, from: data) else {
            return
        }
        snapshots = Dictionary(arr.map { ($0.serviceID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let arr = Array(snapshots.values)
        if let data = try? enc.encode(arr) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func upsert(_ snap: ServiceRuntimeSnapshot) {
        snapshots[snap.serviceID] = snap
        save()
    }

    func remove(serviceID: UUID) {
        if snapshots.removeValue(forKey: serviceID) != nil {
            save()
        }
    }

    func snapshot(for serviceID: UUID) -> ServiceRuntimeSnapshot? {
        snapshots[serviceID]
    }
}

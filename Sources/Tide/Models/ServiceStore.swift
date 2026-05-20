import Foundation
import Observation

@Observable
@MainActor
final class ServiceStore {
    var services: [Service] = []

    @ObservationIgnored private let fileURL: URL

    init() {
        self.fileURL = TideStorage.file("services.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Service].self, from: data) else {
            return
        }
        services = decoded
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(services) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func upsert(_ service: Service) {
        if let i = services.firstIndex(where: { $0.id == service.id }) {
            services[i] = service
        } else {
            services.append(service)
        }
        save()
    }

    func remove(id: UUID) {
        services.removeAll { $0.id == id }
        save()
    }

    func service(id: UUID) -> Service? {
        services.first(where: { $0.id == id })
    }
}

import Foundation

struct Snippet: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var command: String
    var scopeProjectID: UUID?

    init(id: UUID = UUID(), name: String, command: String, scopeProjectID: UUID? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.scopeProjectID = scopeProjectID
    }

    var isGlobal: Bool { scopeProjectID == nil }
}

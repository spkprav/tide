import Foundation

struct Service: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var startCommand: String
    var downCommand: String?
    var cwd: String
    var env: [String: String]
    var autoStart: Bool
    var declaredPort: Int?

    init(
        id: UUID = UUID(),
        name: String,
        startCommand: String,
        downCommand: String? = nil,
        cwd: String,
        env: [String: String] = [:],
        autoStart: Bool = false,
        declaredPort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.startCommand = startCommand
        self.downCommand = downCommand
        self.cwd = cwd
        self.env = env
        self.autoStart = autoStart
        self.declaredPort = declaredPort
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startCommand, downCommand, cwd, env, autoStart, declaredPort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        startCommand = try c.decode(String.self, forKey: .startCommand)
        downCommand = try c.decodeIfPresent(String.self, forKey: .downCommand)
        cwd = try c.decode(String.self, forKey: .cwd)
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        declaredPort = try c.decodeIfPresent(Int.self, forKey: .declaredPort)
    }

    var expandedCwd: String {
        (cwd as NSString).expandingTildeInPath
    }
}

enum ServiceStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case down
    case exited(Int32)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping, .down: return true
        default: return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .stopped, .exited, .failed: return true
        default: return false
        }
    }
}

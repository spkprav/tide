import Foundation

/// Central helper for Tide's on-disk locations.
///
/// Debug and Release builds use distinct directories so that an installed copy of Tide.app
/// in /Applications keeps its own services.json / projects.json / etc. while you continue
/// to iterate on a debug build from the repo. Swift Package Manager only defines DEBUG for
/// `swift build -c debug`, so `#if DEBUG` flips automatically at compile time.
enum TideStorage {
    static let dataDirName: String = {
        #if DEBUG
        return "Tide-dev"
        #else
        return "Tide"
        #endif
    }()

    static var supportDir: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent(dataDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ name: String) -> URL {
        supportDir.appendingPathComponent(name)
    }

    /// Human-readable form: "~/Library/Application Support/<dataDirName>/<file>"
    static func displayPath(_ name: String) -> String {
        "~/Library/Application Support/\(dataDirName)/\(name)"
    }
}

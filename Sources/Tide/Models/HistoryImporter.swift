import Foundation

enum HistoryImporter {
    struct Parsed {
        var tag: String
        var command: String
    }

    static var zshHistoryPath: String {
        "\(NSHomeDirectory())/.zsh_history"
    }

    static var bashHistoryPath: String {
        "\(NSHomeDirectory())/.bash_history"
    }

    struct Breakdown {
        var zshCount: Int
        var bashCount: Int
        var tideCount: Int
        var combined: [Parsed]
    }

    static func parseAllWithBreakdown() -> Breakdown {
        let zsh = parseFile(path: zshHistoryPath, kind: .zsh)
        let bash = parseFile(path: bashHistoryPath, kind: .bash)
        let tide = parseTideHistory()
        return Breakdown(
            zshCount: zsh.count,
            bashCount: bash.count,
            tideCount: tide.count,
            combined: dedupe(zsh + bash + tide)
        )
    }

    static func parseAll() -> [Parsed] {
        parseAllWithBreakdown().combined
    }

    static func parseTideHistory() -> [Parsed] {
        let dir = "\(NSHomeDirectory())/.tide/history"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [Parsed] = []
        for file in files where file.hasSuffix(".log") {
            let path = "\(dir)/\(file)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(raw)
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let cmd = String(parts[1])
                if let parsed = extractTag(from: cmd) {
                    out.append(parsed)
                }
            }
        }
        return out
    }

    enum Kind {
        case zsh, bash
    }

    static func parseFile(path: String, kind: Kind) -> [Parsed] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var out: [Parsed] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let cmd: String
            if kind == .zsh, line.hasPrefix(":") {
                guard let semicolon = line.firstIndex(of: ";") else { continue }
                cmd = String(line[line.index(after: semicolon)...])
            } else {
                cmd = line
            }
            guard let parsed = extractTag(from: cmd) else { continue }
            out.append(parsed)
        }
        return out
    }

    private static func extractTag(from command: String) -> Parsed? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"^(.+?)\s+#\s*([A-Za-z0-9_\-\.]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = trimmed as NSString
        guard let m = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3 else {
            return nil
        }
        let cmdPart = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let tag = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        guard !cmdPart.isEmpty, !tag.isEmpty else { return nil }
        return Parsed(tag: tag, command: cmdPart)
    }

    private static func dedupe(_ items: [Parsed]) -> [Parsed] {
        var seen = Set<String>()
        var out: [Parsed] = []
        for it in items {
            let key = "\(it.tag)\u{1F}\(it.command)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(it)
        }
        return out
    }
}

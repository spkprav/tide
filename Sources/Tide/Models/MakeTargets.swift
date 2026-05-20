import Foundation

enum MakeTargets {
    private struct CacheEntry {
        let mtime: Date
        let targets: [String]
    }

    nonisolated(unsafe) private static var cache: [String: CacheEntry] = [:]
    private static let queue = DispatchQueue(label: "tide.maketargets")

    /// Returns the list of `make` targets declared in the project's Makefile,
    /// in source order with duplicates removed. Returns an empty array when
    /// no Makefile exists or it has no callable targets.
    static func targets(forProjectPath path: String) -> [String] {
        let expanded = (path as NSString).expandingTildeInPath
        let candidates = ["Makefile", "makefile", "GNUmakefile"]
        var found: URL?
        var mtime = Date.distantPast
        for name in candidates {
            let url = URL(fileURLWithPath: expanded).appendingPathComponent(name)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                found = url
                mtime = date
                break
            }
        }
        guard let url = found else { return [] }

        return queue.sync {
            if let entry = cache[url.path], entry.mtime == mtime {
                return entry.targets
            }
            let parsed = parse(url: url)
            cache[url.path] = CacheEntry(mtime: mtime, targets: parsed)
            return parsed
        }
    }

    private static func parse(url: URL) -> [String] {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var ordered: [String] = []
        var seen: Set<String> = []
        var phonyExplicit: Set<String> = []

        for rawLine in data.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            // Skip recipe lines (tab-indented) and pure-comment / blank lines.
            if line.first == "\t" { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Strip trailing comment.
            let codeOnly: String
            if let hashIdx = trimmed.firstIndex(of: "#") {
                codeOnly = String(trimmed[..<hashIdx]).trimmingCharacters(in: .whitespaces)
            } else {
                codeOnly = trimmed
            }

            // Capture explicit .PHONY declarations: `.PHONY: build test run`.
            if codeOnly.hasPrefix(".PHONY:") {
                let names = codeOnly.dropFirst(".PHONY:".count)
                    .split(whereSeparator: { $0.isWhitespace })
                for name in names { phonyExplicit.insert(String(name)) }
                continue
            }

            // Find the first `:` that introduces a rule (not a `:=` assignment).
            guard let colonIdx = codeOnly.firstIndex(of: ":") else { continue }
            let next = codeOnly.index(after: colonIdx)
            if next < codeOnly.endIndex, codeOnly[next] == "=" { continue }

            let lhs = codeOnly[..<colonIdx].trimmingCharacters(in: .whitespaces)
            if lhs.isEmpty { continue }

            // Reject variable assignment with no colon (already handled) and
            // pattern rules / suffix rules we can't safely invoke.
            for token in lhs.split(whereSeparator: { $0.isWhitespace }) {
                let name = String(token)
                if name.contains("$") || name.contains("%") { continue }
                if name.first == "." { continue }                  // .SUFFIXES, .DEFAULT, etc.
                if !name.allSatisfy(isTargetChar) { continue }
                if seen.insert(name).inserted { ordered.append(name) }
            }
        }

        // If a .PHONY block listed names we never saw as rule LHS (rare but
        // legal — e.g. forwarded into an include), surface them too.
        for name in phonyExplicit where !seen.contains(name) && name.allSatisfy(isTargetChar) {
            seen.insert(name)
            ordered.append(name)
        }

        return ordered
    }

    private static func isTargetChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-" || c == "." || c == "/"
    }
}

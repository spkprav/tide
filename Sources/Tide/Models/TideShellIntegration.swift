import Foundation
import AppKit

@MainActor
enum TideShellIntegration {
    static let sentinelBegin = "# >>> tide shell integration >>>"
    static let sentinelEnd   = "# <<< tide shell integration <<<"

    static let historyDir: String = {
        let dir = "\(NSHomeDirectory())/.tide/history"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var script: String {
        """
        \(sentinelBegin)
        # Tide captures commands per pane to ~/.tide/history/<pane>.log
        # Loaded only when inside a Tide pane (TIDE_PANE_ID is set).
        if [ -n "$TIDE_PANE_ID" ] && [ -n "$ZSH_VERSION" ]; then
          mkdir -p "$HOME/.tide/history" 2>/dev/null
          autoload -Uz add-zsh-hook 2>/dev/null
          __tide_capture() {
            print -r -- "$(date -u +%FT%TZ)\\t$1" >> "$HOME/.tide/history/$TIDE_PANE_ID.log"
          }
          add-zsh-hook preexec __tide_capture 2>/dev/null
        fi
        if [ -n "$TIDE_PANE_ID" ] && [ -n "$BASH_VERSION" ]; then
          mkdir -p "$HOME/.tide/history" 2>/dev/null
          __tide_capture_bash() {
            local cmd
            cmd=$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9]* *//')
            printf '%s\\t%s\\n' "$(date -u +%FT%TZ)" "$cmd" >> "$HOME/.tide/history/$TIDE_PANE_ID.log"
          }
          PROMPT_COMMAND="__tide_capture_bash;$PROMPT_COMMAND"
        fi
        \(sentinelEnd)
        """
    }

    static var zshrcPath: String { "\(NSHomeDirectory())/.zshrc" }
    static var bashrcPath: String { "\(NSHomeDirectory())/.bashrc" }

    static func isInstalled(rc: String) -> Bool {
        guard let txt = try? String(contentsOfFile: rc, encoding: .utf8) else { return false }
        return txt.contains(sentinelBegin)
    }

    static func install(rc: String) -> Bool {
        let existing = (try? String(contentsOfFile: rc, encoding: .utf8)) ?? ""
        if existing.contains(sentinelBegin) { return false }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let new = existing + separator + "\n" + script + "\n"
        do {
            try new.write(toFile: rc, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func uninstall(rc: String) -> Bool {
        guard let existing = try? String(contentsOfFile: rc, encoding: .utf8) else { return false }
        guard let beginRange = existing.range(of: sentinelBegin) else { return false }
        guard let endRange = existing.range(of: sentinelEnd, range: beginRange.upperBound..<existing.endIndex) else { return false }
        var modified = existing
        var beginLineStart = beginRange.lowerBound
        while beginLineStart > modified.startIndex {
            let prev = modified.index(before: beginLineStart)
            if modified[prev] == "\n" { break }
            beginLineStart = prev
        }
        var endLineEnd = endRange.upperBound
        if endLineEnd < modified.endIndex, modified[endLineEnd] == "\n" {
            endLineEnd = modified.index(after: endLineEnd)
        }
        modified.removeSubrange(beginLineStart..<endLineEnd)
        try? modified.write(toFile: rc, atomically: true, encoding: .utf8)
        return true
    }

    static func clearHistory() {
        let dir = historyDir
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for f in files where f.hasSuffix(".log") {
            try? FileManager.default.removeItem(atPath: "\(dir)/\(f)")
        }
    }

    static func totalLoggedCommands() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: historyDir) else { return 0 }
        var count = 0
        for f in files where f.hasSuffix(".log") {
            let p = "\(historyDir)/\(f)"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                let s = String(decoding: data, as: UTF8.self)
                count += s.split(separator: "\n", omittingEmptySubsequences: true).count
            }
        }
        return count
    }
}

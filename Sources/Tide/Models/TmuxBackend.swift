import Foundation

enum TmuxBackend {
    /// Custom socket name keeps Tide's tmux server isolated from any tmux the
    /// user already runs in iTerm / Terminal.
    static let socketName = "tide"

    static var configPath: String {
        "\(NSHomeDirectory())/.tide/tmux.conf"
    }

    /// Returns the first usable tmux binary path, or nil.
    /// Prefers a tmux bundled inside Tide.app/Contents/Resources/bin so the
    /// .app is self-contained; falls back to common Homebrew + system paths.
    static func locate() -> String? {
        if let bundled = Bundle.main.resourcePath {
            let path = "\(bundled)/bin/tmux"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static var isAvailable: Bool { locate() != nil }

    /// Writes ~/.tide/tmux.conf if missing or out-of-date. Idempotent.
    static func ensureConfig() {
        let dir = "\(NSHomeDirectory())/.tide"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let body = configBody
        if let existing = try? String(contentsOfFile: configPath, encoding: .utf8),
           existing == body {
            return
        }
        try? body.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    private static let configBody = """
    # Tide tmux backend config — managed automatically. Edit at your own risk.
    set -g status off
    set -g mouse on
    set -g history-limit 200000
    set -g default-terminal "xterm-256color"
    set -g escape-time 10
    set -g remain-on-exit off
    # Disable tmux prefix entirely so Tide's keybinds pass through to the shell.
    set -g prefix None
    unbind C-b
    # Wheel: forward to mouse-aware apps; otherwise enter copy-mode and page
    # through pane history (200k lines).
    bind -n WheelUpPane if -F "#{mouse_any_flag}" "send -M" "if -Ft= '#{pane_in_mode}' 'send -M' 'copy-mode -eu'"
    bind -n WheelDownPane send -M
    """

    static func sessionName(for paneID: UUID) -> String {
        "tide-\(paneID.uuidString.lowercased())"
    }

    /// Build the argv for spawning (or reattaching to) a persistent pane.
    /// Uses `new-session -A` so existing sessions are reattached untouched.
    static func spawnArgs(paneID: UUID, cwd: String?) -> [String] {
        var args = [
            "-L", socketName,
            "-f", configPath,
            "new-session", "-A",
            "-s", sessionName(for: paneID)
        ]
        if let cwd, FileManager.default.fileExists(atPath: cwd) {
            args.append(contentsOf: ["-c", cwd])
        }
        return args
    }

    /// Fire-and-forget kill of a single pane's tmux session.
    static func killSession(paneID: UUID) {
        guard let tmux = locate() else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-L", socketName, "kill-session", "-t", sessionName(for: paneID)]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
    }

    /// List active tide-* sessions on our socket.
    static func listSessionPaneIDs() -> [UUID] {
        guard let tmux = locate() else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-L", socketName, "list-sessions", "-F", "#S"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        proc.waitUntilExit()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let s = String(line)
            guard s.hasPrefix("tide-") else { return nil }
            return UUID(uuidString: String(s.dropFirst("tide-".count)))
        }
    }
}

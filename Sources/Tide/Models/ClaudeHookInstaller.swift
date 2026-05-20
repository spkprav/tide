import Foundation
import AppKit

@MainActor
enum ClaudeHookInstaller {
    static let settingsPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/.claude/settings.json"
    }()

    static let tideCommand =
        "[ -n \"$TIDE_PANE_ID\" ] && touch \"${TIDE_NOTIFY_DIR}/$TIDE_PANE_ID\""
    static let tideWaitCommand =
        "[ -n \"$TIDE_PANE_ID\" ] && cat > \"${TIDE_NOTIFY_DIR}/$TIDE_PANE_ID.wait\""

    static func isInstalled() -> Bool {
        guard let settings = loadSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hasTideCommand(in: hooks, event: "Stop")
            && hasTideCommand(in: hooks, event: "Notification")
    }

    private static func hasTideCommand(in hooks: [String: Any], event: String) -> Bool {
        guard let entries = hooks[event] as? [[String: Any]] else { return false }
        for entry in entries {
            guard let inner = entry["hooks"] as? [[String: Any]] else { continue }
            for h in inner {
                if let cmd = h["command"] as? String, cmd.contains("TIDE_PANE_ID") {
                    return true
                }
            }
        }
        return false
    }

    static func install() {
        ensureSettingsDir()

        if isInstalled() {
            showAlert(
                title: "Already Installed",
                informative: "Tide notification hooks (Stop + Notification) are already present in ~/.claude/settings.json."
            )
            return
        }

        var settings = loadSettings() ?? [:]
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

        hooks = appendTideHook(in: hooks, event: "Stop", command: tideCommand)
        hooks = appendTideHook(in: hooks, event: "Notification", command: tideWaitCommand)
        settings["hooks"] = hooks

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            showAlert(title: "Install Failed", informative: "Could not serialize settings JSON.")
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
            showAlert(
                title: "Installed",
                informative: "Tide Stop + Notification hooks added to ~/.claude/settings.json. New Claude Code sessions will notify Tide on completion and when waiting for input (plan approval, tool permission, etc.)."
            )
        } catch {
            showAlert(title: "Install Failed", informative: "Could not write file: \(error.localizedDescription)")
        }
    }

    private static func appendTideHook(in hooks: [String: Any], event: String, command: String) -> [String: Any] {
        var out = hooks
        if hasTideCommand(in: out, event: event) { return out }
        var entries = (out[event] as? [[String: Any]]) ?? []
        entries.append([
            "matcher": "*",
            "hooks": [
                ["type": "command", "command": command]
            ]
        ])
        out[event] = entries
        return out
    }

    static func uninstall() {
        guard var settings = loadSettings(),
              var hooks = settings["hooks"] as? [String: Any]
        else {
            showAlert(title: "Nothing to Remove", informative: "No hook configuration found.")
            return
        }

        var changed = false
        for event in ["Stop", "Notification"] {
            let (newHooks, didChange) = stripTideHook(in: hooks, event: event)
            hooks = newHooks
            if didChange { changed = true }
        }

        if !changed {
            showAlert(title: "Not Found", informative: "Tide hooks not present in settings.")
            return
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            showAlert(title: "Uninstall Failed", informative: "Could not serialize settings JSON.")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
            showAlert(title: "Removed", informative: "Tide Stop + Notification hooks removed from ~/.claude/settings.json.")
        } catch {
            showAlert(title: "Uninstall Failed", informative: "Could not write file: \(error.localizedDescription)")
        }
    }

    private static func stripTideHook(in hooks: [String: Any], event: String) -> ([String: Any], Bool) {
        var out = hooks
        guard let entries = out[event] as? [[String: Any]] else { return (out, false) }

        var changed = false
        var rebuilt: [[String: Any]] = []
        for entry in entries {
            var keep = true
            if let inner = entry["hooks"] as? [[String: Any]] {
                let filtered = inner.filter { ($0["command"] as? String)?.contains("TIDE_PANE_ID") != true }
                if filtered.count != inner.count {
                    changed = true
                    if filtered.isEmpty {
                        keep = false
                    } else {
                        var copy = entry
                        copy["hooks"] = filtered
                        rebuilt.append(copy)
                        continue
                    }
                }
            }
            if keep { rebuilt.append(entry) }
        }

        if rebuilt.isEmpty {
            out.removeValue(forKey: event)
        } else {
            out[event] = rebuilt
        }
        return (out, changed)
    }

    static func revealInFinder() {
        ensureSettingsDir()
        let url = URL(fileURLWithPath: settingsPath)
        if FileManager.default.fileExists(atPath: settingsPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "\(NSHomeDirectory())/.claude")])
        }
    }

    private static func ensureSettingsDir() {
        let dir = "\(NSHomeDirectory())/.claude"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    private static func loadSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func showAlert(title: String, informative: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informative
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

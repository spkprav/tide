import Foundation
import AppKit

@MainActor
enum ClaudeHookInstaller {
    static let settingsPath: String = {
        let home = NSHomeDirectory()
        return "\(home)/.claude/settings.json"
    }()

    static let tideCommand = "[ -n \"$TIDE_PANE_ID\" ] && touch \"${TIDE_NOTIFY_DIR}/$TIDE_PANE_ID\""

    static func isInstalled() -> Bool {
        guard let settings = loadSettings() else { return false }
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        guard let stops = hooks["Stop"] as? [[String: Any]] else { return false }
        for entry in stops {
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

        var settings = loadSettings() ?? [:]
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        var stopHooks = (hooks["Stop"] as? [[String: Any]]) ?? []

        if isInstalled() {
            showAlert(
                title: "Already Installed",
                informative: "Tide notification hook is already present in ~/.claude/settings.json."
            )
            return
        }

        let entry: [String: Any] = [
            "matcher": "*",
            "hooks": [
                [
                    "type": "command",
                    "command": tideCommand
                ]
            ]
        ]
        stopHooks.append(entry)
        hooks["Stop"] = stopHooks
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
                informative: "Tide Stop hook added to ~/.claude/settings.json. Any new Claude Code session will notify Tide on completion."
            )
        } catch {
            showAlert(title: "Install Failed", informative: "Could not write file: \(error.localizedDescription)")
        }
    }

    static func uninstall() {
        guard var settings = loadSettings(),
              var hooks = settings["hooks"] as? [String: Any],
              var stopHooks = hooks["Stop"] as? [[String: Any]]
        else {
            showAlert(title: "Nothing to Remove", informative: "No hook configuration found.")
            return
        }

        var changed = false
        var newStops: [[String: Any]] = []
        for entry in stopHooks {
            var keepEntry = true
            if let inner = entry["hooks"] as? [[String: Any]] {
                let filtered = inner.filter { ($0["command"] as? String)?.contains("TIDE_PANE_ID") != true }
                if filtered.count != inner.count {
                    changed = true
                    if filtered.isEmpty {
                        keepEntry = false
                    } else {
                        var copy = entry
                        copy["hooks"] = filtered
                        newStops.append(copy)
                        continue
                    }
                }
            }
            if keepEntry { newStops.append(entry) }
        }

        if !changed {
            showAlert(title: "Not Found", informative: "Tide hook not present in settings.")
            return
        }

        stopHooks = newStops
        if stopHooks.isEmpty {
            hooks.removeValue(forKey: "Stop")
        } else {
            hooks["Stop"] = stopHooks
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
            showAlert(title: "Removed", informative: "Tide Stop hook removed from ~/.claude/settings.json.")
        } catch {
            showAlert(title: "Uninstall Failed", informative: "Could not write file: \(error.localizedDescription)")
        }
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

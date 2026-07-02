import Foundation
import AppKit

enum EditorLauncher {
    // Ordered by user popularity for code editors on macOS. First installed wins.
    private static let candidateBundleIDs: [String] = [
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.microsoft.VSCode",            // Visual Studio Code
        "com.microsoft.VSCodeInsiders",    // VS Code Insiders
        "com.exafunction.windsurf",        // Windsurf
        "dev.zed.Zed",                     // Zed
        "com.sublimetext.4",               // Sublime Text 4
        "com.panic.Nova",                  // Nova
        "com.jetbrains.intellij",          // IntelliJ IDEA
        "com.jetbrains.pycharm",           // PyCharm
        "com.jetbrains.WebStorm",          // WebStorm
        "com.macromates.TextMate",         // TextMate
        "com.apple.dt.Xcode",              // Xcode (last — folders rarely useful in Xcode without .xcodeproj)
    ]

    @MainActor
    static func open(_ path: String) {
        let url = URL(fileURLWithPath: path)

        let override = UserDefaults.standard.string(forKey: "tide.editor.bundleID") ?? ""
        if !override.isEmpty, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: override) {
            launch(folder: url, with: appURL)
            return
        }

        for bid in candidateBundleIDs {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                launch(folder: url, with: appURL)
                return
            }
        }

        NSWorkspace.shared.open(url)
    }

    private static func launch(folder: URL, with appURL: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: cfg, completionHandler: nil)
    }
}

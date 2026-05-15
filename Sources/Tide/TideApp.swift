import SwiftUI

@main
struct TideApp: App {
    @State private var store = ProjectStore()
    @State private var snippets = SnippetStore()
    @State private var startups = StartupStore()
    @State private var notifier = NotificationWatcher()
    @State private var tracker = UsageTracker()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(snippets)
                .environment(startups)
                .environment(tracker)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    NotificationWatcher.requestPermission()
                    notifier.onPaneDone = { sessionID, message in
                        handlePaneDone(sessionID: sessionID, message: message)
                    }
                    notifier.start()
                }
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(store)
                .environment(snippets)
                .environment(startups)
                .environment(tracker)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Install Claude Notification Hook…") {
                    ClaudeHookInstaller.install()
                }
                Button("Remove Claude Notification Hook") {
                    ClaudeHookInstaller.uninstall()
                }
            }
            CommandMenu("Tab") {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .newTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            CommandMenu("Pane") {
                Button("Split Right") {
                    NotificationCenter.default.post(name: .splitVertical, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Down") {
                    NotificationCenter.default.post(name: .splitHorizontal, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Close Pane / Tab") {
                    NotificationCenter.default.post(name: .closePane, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Pane…") {
                    NotificationCenter.default.post(name: .triggerFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("Snippets") {
                Button("Focus Command Bar") {
                    NotificationCenter.default.post(name: .focusSnippetsBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let splitVertical   = Notification.Name("Tide.splitVertical")
    static let splitHorizontal = Notification.Name("Tide.splitHorizontal")
    static let closePane       = Notification.Name("Tide.closePane")
}

extension TideApp {
    @MainActor
    private func handlePaneDone(sessionID: UUID, message: String?) {
        for project in store.projects {
            guard let session = store.sessions[project.id] else { continue }
            for tab in session.tabs where tab.terminals[sessionID] != nil {
                let paneTitle = tab.leafTitles[sessionID] ?? "pane"
                let armed = session.consumeClaudeDoneReminder(in: tab, sid: sessionID)
                let body = armed ?? message ?? "Pane finished — ready to review"
                NotificationWatcher.deliver(
                    title: "\(project.name) · \(paneTitle)",
                    body: body
                )
                session.flashLeafID = nil
                DispatchQueue.main.async { session.flashLeafID = sessionID }
                return
            }
            if session.hiddenTerminals[sessionID] != nil {
                let title = session.hiddenPanes.first(where: { $0.id == sessionID })?.title ?? "hidden pane"
                NotificationWatcher.deliver(
                    title: "\(project.name) · \(title)",
                    body: message ?? "Hidden pane finished"
                )
                return
            }
        }
    }
}

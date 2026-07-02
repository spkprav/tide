import SwiftUI
import Darwin

@main
struct TideApp: App {
    @State private var store = ProjectStore()
    @State private var snippets = SnippetStore()
    @State private var commandUsage = CommandUsageStore()
    @State private var startups = StartupStore()
    @State private var notifier = NotificationWatcher()
    @State private var tracker = UsageTracker()
    @State private var waiters = WaitingPaneStore()
    @State private var snapshotStore = SessionSnapshotStore()
    @State private var serviceStore: ServiceStore
    @State private var serviceSupervisor: ServiceSupervisor
    @State private var snapshotTimer: Timer?

    init() {
        Self.raiseFileDescriptorLimit()
        NSWindow.allowsAutomaticWindowTabbing = false
        let svcStore = ServiceStore()
        _serviceStore = State(initialValue: svcStore)
        _serviceSupervisor = State(initialValue: ServiceSupervisor(store: svcStore))
    }

    // Raise RLIMIT_NOFILE so shells we spawn inside panes don't inherit the
    // 256-fd launchd default. Tools like the Claude CLI open hundreds of
    // handles at startup (MCP servers, agent definitions, sockets) and hit
    // the cap immediately. Terminal.app / iTerm bump this for the same
    // reason — we match what they do.
    private static func raiseFileDescriptorLimit() {
        var limit = rlimit(rlim_cur: 0, rlim_max: 0)
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
        let target: rlim_t = 65536
        // Cap by hard limit if it's a sane positive value; otherwise just
        // request target and let setrlimit clamp.
        let newSoft = limit.rlim_max > 0 ? min(target, limit.rlim_max) : target
        if limit.rlim_cur >= newSoft { return }
        limit.rlim_cur = newSoft
        _ = setrlimit(RLIMIT_NOFILE, &limit)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(snippets)
                .environment(commandUsage)
                .environment(startups)
                .environment(tracker)
                .environment(waiters)
                .environment(snapshotStore)
                .environment(serviceStore)
                .environment(serviceSupervisor)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    NotificationWatcher.requestPermission()
                    notifier.onPaneDone = { sessionID, message in
                        handlePaneDone(sessionID: sessionID, message: message)
                    }
                    notifier.onPaneWaiting = { sessionID, message in
                        handlePaneWaiting(sessionID: sessionID, message: message)
                    }
                    notifier.start()
                    serviceSupervisor.startAutoStart()
                    startSnapshotTimer()
                    installTerminateHook()
                }
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(store)
                .environment(snippets)
                .environment(commandUsage)
                .environment(startups)
                .environment(tracker)
                .environment(waiters)
                .environment(snapshotStore)
                .environment(serviceStore)
                .environment(serviceSupervisor)
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
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}

extension Notification.Name {
    static let splitVertical   = Notification.Name("Tide.splitVertical")
    static let splitHorizontal = Notification.Name("Tide.splitHorizontal")
    static let closePane       = Notification.Name("Tide.closePane")
    static let toggleSidebar   = Notification.Name("Tide.toggleSidebar")
}

extension TideApp {
    @MainActor
    private func startSnapshotTimer() {
        guard snapshotTimer == nil else { return }
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in
                let snap = SessionSnapshotBuilder.capture(store: store)
                if !snap.projects.isEmpty {
                    snapshotStore.save(snap)
                }
            }
        }
    }

    @MainActor
    private func installTerminateHook() {
        // Save once more on app quit so the snapshot reflects state up to the
        // very last second the user worked in Tide.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let snap = SessionSnapshotBuilder.capture(store: store)
                if !snap.projects.isEmpty {
                    snapshotStore.save(snap)
                }
            }
        }
    }

    @MainActor
    private func handlePaneDone(sessionID: UUID, message: String?) {
        // Claude finished → drop any pending wait card for this pane.
        waiters.dismiss(id: sessionID)
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

    @MainActor
    private func handlePaneWaiting(sessionID: UUID, message: String?) {
        for project in store.projects {
            guard let session = store.sessions[project.id] else { continue }
            for tab in session.tabs where tab.terminals[sessionID] != nil {
                let paneTitle = tab.leafTitles[sessionID] ?? "pane"
                let body = message ?? "Waiting for your input"
                waiters.upsert(WaitingPane(
                    id: sessionID,
                    projectName: project.name,
                    paneTitle: paneTitle,
                    message: body,
                    startedAt: Date()
                ))
                NotificationWatcher.deliver(
                    title: "\(project.name) · \(paneTitle)",
                    body: body
                )
                return
            }
            if session.hiddenTerminals[sessionID] != nil {
                let title = session.hiddenPanes.first(where: { $0.id == sessionID })?.title ?? "hidden pane"
                let body = message ?? "Waiting for your input"
                waiters.upsert(WaitingPane(
                    id: sessionID,
                    projectName: project.name,
                    paneTitle: title,
                    message: body,
                    startedAt: Date()
                ))
                NotificationWatcher.deliver(
                    title: "\(project.name) · \(title)",
                    body: body
                )
                return
            }
        }
    }
}

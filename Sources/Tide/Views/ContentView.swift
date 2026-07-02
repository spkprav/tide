import SwiftUI
import AppKit
import SwiftTerm

struct ContentView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(UsageTracker.self) private var tracker
    @Environment(WaitingPaneStore.self) private var waiters
    @Environment(\.scenePhase) private var scenePhase
    @State private var clickMonitor: Any?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            RestoreSessionBanner()
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
            } detail: {
                detailContent
                    .toolbar {
                        if columnVisibility == .detailOnly {
                            ToolbarItem(placement: .principal) {
                                TopBarChipsRow()
                            }
                            ToolbarItemGroup(placement: .primaryAction) {
                                TopBarActions()
                            }
                        }
                    }
            }
            .navigationSplitViewStyle(.balanced)

            SnippetsBar()
        }
        .overlay(alignment: .topTrailing) {
            WaitingPanesOverlay()
        }
        .onAppear {
            updateFocus(phase: scenePhase, id: store.selectedID)
            installClickMonitor()
        }
        .onChange(of: store.selectedID) { _, newID in
            updateFocus(phase: scenePhase, id: newID)
        }
        .onChange(of: scenePhase) { _, newPhase in
            updateFocus(phase: newPhase, id: store.selectedID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            }
        }
        .onDisappear {
            tracker.flush()
            removeClickMonitor()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if store.selectedID == OVERVIEW_ID {
            OverviewView()
        } else if store.selectedID == STATS_ID {
            StatsView()
        } else if store.selectedID == ACTIVE_SESSIONS_ID {
            ActiveSessionsView()
        } else if store.selectedID == NOTIFICATIONS_ID {
            NotificationsView()
        } else if let project = store.selected {
            TerminalAreaView(project: project)
                .id(project.id)
        } else {
            EmptyStateView()
        }
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [storeRef = store, waitersRef = waiters] event in
            // hitTest expects a point in the receiver's SUPERVIEW coordinate space.
            // For NSWindow.contentView that's window-local, unflipped — same space
            // as event.locationInWindow. Converting first inverted Y on flipped
            // views and made every click target the mirrored pane.
            if let win = event.window, let cv = win.contentView {
                if let hit = cv.hitTest(event.locationInWindow) {
                    activatePaneIfTerminal(hit, store: storeRef, waiters: waitersRef)
                }
            }
            return event
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }

    private func activatePaneIfTerminal(_ view: NSView, store: ProjectStore, waiters: WaitingPaneStore) {
        var v: NSView? = view
        while let current = v {
            if let term = current as? LocalProcessTerminalView {
                for project in store.projects {
                    guard let session = store.sessions[project.id] else { continue }
                    for tab in session.tabs {
                        for (sid, t) in tab.terminals where t === term {
                            if tab.activeLeafID != sid {
                                tab.activeLeafID = sid
                            }
                            if session.activeTabID != tab.id {
                                session.activeTabID = tab.id
                            }
                            waiters.dismiss(id: sid)
                            return
                        }
                    }
                }
                return
            }
            v = current.superview
        }
    }

    private func updateFocus(phase: ScenePhase, id: UUID?) {
        guard phase == .active else {
            tracker.setFocus(projectID: nil)
            return
        }
        guard let id, id != STATS_ID, id != ACTIVE_SESSIONS_ID, id != NOTIFICATIONS_ID, id != OVERVIEW_ID else {
            tracker.setFocus(projectID: nil)
            return
        }
        guard store.projects.contains(where: { $0.id == id }) else {
            tracker.setFocus(projectID: nil)
            return
        }
        if let session = store.sessions[id], session.started {
            tracker.setFocus(projectID: id)
        } else {
            tracker.setFocus(projectID: nil)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No project selected")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Add a project from the sidebar to get started")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color.tnBg)
    }
}

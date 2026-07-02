import SwiftUI
import AppKit

struct TerminalAreaView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(UsageTracker.self) private var tracker
    @Environment(StartupStore.self) private var startupStore
    let project: Project

    var body: some View {
        let session = store.session(for: project)
        Group {
            if session.started {
                VStack(spacing: 0) {
                    TabBar(session: session)
                    if session.activeTabID == HIDDEN_TAB_ID {
                        HiddenTabGridView(session: session)
                    } else if session.activeTabID == DASHBOARD_TAB_ID {
                        ProjectDashboardView(project: project)
                    } else if let tab = session.activeTab {
                        // Always render the split tree. Zoom is implemented by
                        // hiding sibling NSSplitView subviews so the persistent
                        // SwiftTerm NSViews stay mounted across zoom toggle —
                        // see TideSplitView.applyZoom. Switching SwiftUI
                        // subtrees via .id() used to tear down the terminal
                        // hosting view and leave the zoomed pane blank.
                        SplitContainerView(node: tab.root, tab: tab)
                            .id(tab.id)
                    } else {
                        Color.black
                    }
                }
            } else if session.activeTabID == DASHBOARD_TAB_ID {
                ProjectDashboardView(
                    project: project,
                    showStartCTA: true,
                    onStart: {
                        let cfg = startupStore.primaryConfig(for: project.id)
                        session.start(with: cfg)
                        tracker.recordSessionStart(projectID: project.id)
                    },
                    onBackToStart: {
                        if let firstID = session.tabs.first?.id {
                            session.activeTabID = firstID
                        }
                    }
                )
            } else {
                StartScreen(project: project, session: session)
            }
        }
        .background(SwiftUI.Color.tnBg)
        .onReceive(NotificationCenter.default.publisher(for: .splitVertical)) { _ in
            guard !session.isShowingHidden else { return }
            session.activeTab?.split(axis: .vertical)
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitHorizontal)) { _ in
            guard !session.isShowingHidden else { return }
            session.activeTab?.split(axis: .horizontal)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closePane)) { _ in
            session.closeActivePaneOrTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
            session.newTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerFind)) { _ in
            triggerFind()
        }
        .onChange(of: session.started) { _, newValue in
            tracker.setFocus(projectID: newValue ? project.id : nil)
        }
    }

    private func triggerFind() {
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
    }
}

struct SplitContainerView: View {
    @Bindable var node: SplitNode
    let tab: TabSession

    var body: some View {
        switch node.content {
        case .leaf(let sessionID):
            TerminalLeafView(sessionID: sessionID, tab: tab)
        case .split(let axis, let children):
            // TideSplitView wraps NSSplitView so we can read + restore
            // divider positions and absorb a closed pane's space into the
            // adjacent neighbor. Children are tagged by SplitNode.id so the
            // hosting views (and their terminals) are reused across diffs.
            // zoomedChildIndex collapses non-on-path siblings to zero when
            // a descendant leaf is zoomed.
            let zoomedIdx: Int? = tab.zoomedLeafID.flatMap { zid in
                children.firstIndex { $0.containsLeaf(zid) }
            }
            TideSplitView(
                axis: axis,
                childIDs: children.map(\.id),
                initialFractions: tab.fractions(for: node, childCount: children.count),
                minimumChildSize: axis == .vertical ? 80 : 60,
                zoomedChildIndex: zoomedIdx,
                onResize: { fractions in tab.setFractions(fractions, for: node) },
                makeChild: { idx in
                    SplitContainerView(node: children[idx], tab: tab)
                }
            )
        }
    }
}

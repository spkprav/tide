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
                        if let zoomedSid = tab.zoomedLeafID {
                            TerminalLeafView(sessionID: zoomedSid, tab: tab)
                                .id("\(tab.id)-zoom-\(zoomedSid)")
                        } else {
                            SplitContainerView(node: tab.root, tab: tab)
                                .id(tab.id)
                        }
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
        .background(Color.black)
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
            if axis == .vertical {
                HSplitView {
                    ForEach(children) { child in
                        SplitContainerView(node: child, tab: tab)
                            .frame(minWidth: 80)
                    }
                }
                .id(Self.structureKey(children))
            } else {
                VSplitView {
                    ForEach(children) { child in
                        SplitContainerView(node: child, tab: tab)
                            .frame(minHeight: 60)
                    }
                }
                .id(Self.structureKey(children))
            }
        }
    }

    static func structureKey(_ children: [SplitNode]) -> String {
        children.map { shape($0) }.joined(separator: "|")
    }

    static func shape(_ node: SplitNode) -> String {
        switch node.content {
        case .leaf:
            return "L"
        case .split(let axis, let kids):
            let a = axis == .vertical ? "V" : "H"
            return "\(a)(\(kids.map { shape($0) }.joined(separator: ",")))"
        }
    }
}

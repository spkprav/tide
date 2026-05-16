import Foundation
import Observation
import AppKit
@preconcurrency import SwiftTerm

enum SplitAxis {
    case vertical
    case horizontal
}

let HIDDEN_TAB_ID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let ALL_TAB_ID    = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

struct ActivePane: Identifiable, Hashable {
    var id: UUID { sessionID }
    let tabID: UUID
    let tabIndex: Int
    let tabTitle: String
    let sessionID: UUID
    let title: String
}

struct HiddenPane: Identifiable, Hashable {
    let id: UUID
    var title: String
}

enum ReminderKind: Hashable {
    case processExit
    case claudeDone
    case aiMonitor(intervalSec: Int, model: String, taskPrompt: String)

    var label: String {
        switch self {
        case .processExit: return "Process exit"
        case .claudeDone:  return "Claude done"
        case .aiMonitor:   return "AI monitor"
        }
    }
}

struct PaneReminder: Hashable {
    var kind: ReminderKind
    var message: String
    var sawActivity: Bool = false
    var lastAICheck: Date?
}

@Observable
@MainActor
final class SplitNode: Identifiable {
    nonisolated let id = UUID()
    var content: Content

    enum Content {
        case leaf(sessionID: UUID)
        case split(axis: SplitAxis, children: [SplitNode])
    }

    init(content: Content) {
        self.content = content
    }

    static func makeLeaf() -> SplitNode {
        SplitNode(content: .leaf(sessionID: UUID()))
    }
}

@Observable
@MainActor
final class TabSession: Identifiable {
    nonisolated let id: UUID
    var name: String?
    var root: SplitNode
    var activeLeafID: UUID
    var leafTitles: [UUID: String] = [:]
    var zoomedLeafID: UUID?
    var reminders: [UUID: PaneReminder] = [:]

    @ObservationIgnored var terminals: [UUID: LocalProcessTerminalView] = [:]
    @ObservationIgnored var delegates: [UUID: TerminalDelegate] = [:]
    @ObservationIgnored let cwd: String
    @ObservationIgnored weak var session: ProjectSession?

    // Per-split fractions keyed by the parent .split SplitNode.id.
    // Each value is the fractional width/height of each child, summing to 1.0.
    // Missing key or wrong-length value = even split.
    @ObservationIgnored var splitFractions: [UUID: [CGFloat]] = [:]

    func fractions(for parent: SplitNode, childCount: Int) -> [CGFloat] {
        if let f = splitFractions[parent.id], f.count == childCount {
            return TabSession.normalize(f)
        }
        return Array(repeating: 1.0 / CGFloat(childCount), count: childCount)
    }

    func setFractions(_ f: [CGFloat], for parent: SplitNode) {
        splitFractions[parent.id] = TabSession.normalize(f)
    }

    private static func normalize(_ f: [CGFloat]) -> [CGFloat] {
        let sum = f.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: 1.0 / CGFloat(f.count), count: f.count)
        }
        return f.map { $0 / sum }
    }

    init(cwd: String, id: UUID = UUID()) {
        self.id = id
        self.cwd = cwd
        let leaf = SplitNode.makeLeaf()
        self.root = leaf
        if case .leaf(let sid) = leaf.content {
            self.activeLeafID = sid
        } else {
            self.activeLeafID = UUID()
        }
    }

    func terminal(for sessionID: UUID) -> LocalProcessTerminalView {
        if let t = terminals[sessionID] { return t }
        let view = LocalProcessTerminalView(frame: .zero)
        view.applyTideTheme()

        let delegate = TerminalDelegate(session: session, sessionID: sessionID)
        delegates[sessionID] = delegate
        view.processDelegate = delegate

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TIDE=1")
        env.append("TIDE_PANE_ID=\(sessionID.uuidString)")
        env.append("TIDE_NOTIFY_DIR=\(NotificationWatcher.notifyDir)")
        let startCwd: String? = FileManager.default.fileExists(atPath: cwd) ? cwd : nil
        view.startProcess(executable: shell, args: ["-l"], environment: env, execName: shell, currentDirectory: startCwd)
        view.getTerminal().changeHistorySize(100_000)
        terminals[sessionID] = view
        return view
    }

    func split(axis: SplitAxis) {
        zoomedLeafID = nil
        guard let (parent, index, leaf) = locate(sessionID: activeLeafID, in: root, parent: nil, index: 0) else { return }
        guard case .leaf = leaf.content else { return }
        let newLeaf = SplitNode.makeLeaf()
        let preservedLeaf = SplitNode(content: leaf.content)

        if let parent {
            if case .split(let pAxis, var children) = parent.content {
                if pAxis == axis {
                    let oldFractions = fractions(for: parent, childCount: children.count)
                    children.insert(newLeaf, at: index + 1)
                    parent.content = .split(axis: pAxis, children: children)

                    // Split the original leaf's slot in half to make room.
                    var f = oldFractions
                    let share = f[index] / 2
                    f[index] = share
                    f.insert(share, at: index + 1)
                    splitFractions[parent.id] = f

                    if case .leaf(let sid) = newLeaf.content { activeLeafID = sid }
                    return
                }
            }
        }

        leaf.content = .split(axis: axis, children: [preservedLeaf, newLeaf])
        if case .leaf(let sid) = newLeaf.content { activeLeafID = sid }
    }

    func toggleZoom(for sessionID: UUID) {
        if zoomedLeafID == sessionID {
            zoomedLeafID = nil
        } else {
            zoomedLeafID = sessionID
            activeLeafID = sessionID
        }
    }

    @discardableResult
    func closeActive() -> Bool {
        closeLeaf(sessionID: activeLeafID, sendExit: true)
    }

    @discardableResult
    func closeLeaf(sessionID: UUID, sendExit: Bool = false) -> Bool {
        if sendExit, let term = terminals[sessionID] {
            killTerminalProcessTree(term)
        }
        terminals.removeValue(forKey: sessionID)
        delegates.removeValue(forKey: sessionID)
        leafTitles.removeValue(forKey: sessionID)
        if zoomedLeafID == sessionID { zoomedLeafID = nil }
        return removeLeafFromTree(sessionID: sessionID)
    }

    func removeLeafFromTree(sessionID: UUID) -> Bool {
        guard let (parent, index, leaf) = locate(sessionID: sessionID, in: root, parent: nil, index: 0) else { return false }
        guard case .leaf = leaf.content else { return false }

        guard let parent else {
            let fresh = SplitNode.makeLeaf()
            root = fresh
            if case .leaf(let nsid) = fresh.content { activeLeafID = nsid }
            return true
        }

        guard case .split(let axis, var children) = parent.content else { return false }
        let oldFractions = fractions(for: parent, childCount: children.count)
        let removedFraction = oldFractions[index]
        children.remove(at: index)

        if children.count == 1 {
            // Collapse: parent now holds sole survivor's content directly.
            splitFractions.removeValue(forKey: parent.id)
            parent.content = children[0].content
            updateActiveLeafToFirstLeaf(in: parent)
        } else {
            // Adjacent neighbor absorbs removed share. Prefer left/up, fall
            // back to right/down (index 0).
            var newFractions = oldFractions
            newFractions.remove(at: index)
            let absorberIdx = index > 0 ? index - 1 : 0
            newFractions[absorberIdx] += removedFraction
            parent.content = .split(axis: axis, children: children)
            splitFractions[parent.id] = newFractions
            updateActiveLeafToFirstLeaf(in: children[absorberIdx])
        }
        return true
    }

    func insertAsVerticalSplit(sessionID: UUID) {
        let newLeaf = SplitNode(content: .leaf(sessionID: sessionID))
        if let (parent, index, leaf) = locate(sessionID: activeLeafID, in: root, parent: nil, index: 0),
           case .leaf = leaf.content {
            if let parent, case .split(let pAxis, var children) = parent.content, pAxis == .vertical {
                children.insert(newLeaf, at: index + 1)
                parent.content = .split(axis: .vertical, children: children)
            } else {
                let preservedLeaf = SplitNode(content: leaf.content)
                leaf.content = .split(axis: .vertical, children: [preservedLeaf, newLeaf])
            }
        } else {
            root = newLeaf
        }
        activeLeafID = sessionID
    }

    func transferTerminal(_ view: LocalProcessTerminalView, delegate: TerminalDelegate, sessionID: UUID, title: String) {
        terminals[sessionID] = view
        delegates[sessionID] = delegate
        leafTitles[sessionID] = title
    }

    var hasOnlySingleLeaf: Bool {
        if case .leaf = root.content { return true }
        return false
    }

    func leafSessionIDsInOrder() -> [UUID] {
        var out: [UUID] = []
        func walk(_ node: SplitNode) {
            switch node.content {
            case .leaf(let sid):
                if terminals[sid] != nil { out.append(sid) }
            case .split(_, let children):
                for c in children { walk(c) }
            }
        }
        walk(root)
        return out
    }

    private func updateActiveLeafToFirstLeaf(in node: SplitNode) {
        switch node.content {
        case .leaf(let sid):
            activeLeafID = sid
        case .split(_, let children):
            if let first = children.first {
                updateActiveLeafToFirstLeaf(in: first)
            }
        }
    }

    private func locate(sessionID: UUID, in node: SplitNode, parent: SplitNode?, index: Int) -> (SplitNode?, Int, SplitNode)? {
        switch node.content {
        case .leaf(let sid):
            if sid == sessionID { return (parent, index, node) }
            return nil
        case .split(_, let children):
            for (i, child) in children.enumerated() {
                if let f = locate(sessionID: sessionID, in: child, parent: node, index: i) {
                    return f
                }
            }
            return nil
        }
    }
}

@Observable
@MainActor
final class ProjectSession {
    var tabs: [TabSession]
    var activeTabID: UUID
    var started: Bool = false
    var hiddenPanes: [HiddenPane] = []
    var flashLeafID: UUID?
    var projectName: String = ""
    @ObservationIgnored var hiddenTerminals: [UUID: LocalProcessTerminalView] = [:]
    @ObservationIgnored var hiddenDelegates: [UUID: TerminalDelegate] = [:]
    @ObservationIgnored let cwd: String
    @ObservationIgnored private var pollTimer: Timer?

    init(cwd: String, projectName: String = "") {
        self.cwd = cwd
        self.projectName = projectName
        let t = TabSession(cwd: cwd)
        self.tabs = [t]
        self.activeTabID = t.id
        t.session = self
    }

    func armReminder(in tab: TabSession, sessionID: UUID, kind: ReminderKind, message: String) {
        tab.reminders[sessionID] = PaneReminder(kind: kind, message: message)
        if requiresPolling(kind: kind) {
            startPolling()
        }
    }

    func clearReminder(in tab: TabSession, sessionID: UUID) {
        tab.reminders.removeValue(forKey: sessionID)
        if !anyReminders { stopPolling() }
    }

    private func requiresPolling(kind: ReminderKind) -> Bool {
        switch kind {
        case .processExit, .aiMonitor: return true
        case .claudeDone:              return false
        }
    }

    var anyReminders: Bool {
        tabs.contains { !$0.reminders.isEmpty }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickReminders()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tickReminders() {
        for tab in tabs {
            let pairs = tab.reminders.map { ($0.key, $0.value) }
            for (sid, _) in pairs {
                guard let term = tab.terminals[sid] else {
                    tab.reminders.removeValue(forKey: sid)
                    continue
                }
                guard let r = tab.reminders[sid] else { continue }
                switch r.kind {
                case .processExit:
                    tickProcessExit(tab: tab, sid: sid, term: term)
                case .claudeDone:
                    continue
                case .aiMonitor(let intervalSec, let model, let taskPrompt):
                    tickAIMonitor(tab: tab, sid: sid, term: term, intervalSec: intervalSec, model: model, taskPrompt: taskPrompt)
                }
            }
        }
        if !anyReminders { stopPolling() }
    }

    private func tickProcessExit(tab: TabSession, sid: UUID, term: LocalProcessTerminalView) {
        let pid = term.process.shellPid
        let busy = ProjectSession.hasChildProcesses(parentPid: pid)
        guard var r = tab.reminders[sid] else { return }
        if busy {
            if !r.sawActivity {
                r.sawActivity = true
                tab.reminders[sid] = r
            }
        } else if r.sawActivity {
            fire(in: tab, sid: sid, fallback: "Task finished — ready to review")
        }
    }

    private func tickAIMonitor(tab: TabSession, sid: UUID, term: LocalProcessTerminalView, intervalSec: Int, model: String, taskPrompt: String) {
        guard var r = tab.reminders[sid] else { return }
        let now = Date()
        if let last = r.lastAICheck, now.timeIntervalSince(last) < TimeInterval(intervalSec) {
            return
        }
        r.lastAICheck = now
        tab.reminders[sid] = r

        let t = term.getTerminal()
        let lastRow = max(0, t.rows - 1)
        let lastCol = max(0, t.cols - 1)
        let output = t.getText(start: Position(col: 0, row: 0), end: Position(col: lastCol, row: lastRow))

        let snapshotTitle = "\(projectName) · \(tab.leafTitles[sid] ?? "pane")"
        let snapshotMessage = r.message

        Task { [weak self, weak tab] in
            let verdict = await OllamaClient.askIfDone(model: model, task: taskPrompt, output: output)
            if verdict == .done {
                await MainActor.run {
                    guard let self, let tab, tab.reminders[sid] != nil else { return }
                    NotificationWatcher.deliver(
                        title: snapshotTitle,
                        body: snapshotMessage.isEmpty ? "AI says: task complete" : snapshotMessage
                    )
                    tab.reminders.removeValue(forKey: sid)
                    self.flashLeafID = nil
                    DispatchQueue.main.async { self.flashLeafID = sid }
                    if !self.anyReminders { self.stopPolling() }
                }
            }
        }
    }

    private func fire(in tab: TabSession, sid: UUID, fallback: String) {
        guard let r = tab.reminders[sid] else { return }
        let title = "\(projectName) · \(tab.leafTitles[sid] ?? "pane")"
        let body = r.message.isEmpty ? fallback : r.message
        NotificationWatcher.deliver(title: title, body: body)
        tab.reminders.removeValue(forKey: sid)
        flashLeafID = nil
        DispatchQueue.main.async { [weak self] in
            self?.flashLeafID = sid
        }
    }

    func consumeClaudeDoneReminder(in tab: TabSession, sid: UUID) -> String? {
        guard let r = tab.reminders[sid], case .claudeDone = r.kind else { return nil }
        tab.reminders.removeValue(forKey: sid)
        return r.message.isEmpty ? nil : r.message
    }

    nonisolated private static func hasChildProcesses(parentPid: pid_t) -> Bool {
        guard parentPid > 0 else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-P", "\(parentPid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return false
        }
        task.waitUntilExit()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return !data.isEmpty
    }

    var activeTab: TabSession? {
        tabs.first { $0.id == activeTabID }
    }

    var isShowingHidden: Bool {
        activeTabID == HIDDEN_TAB_ID
    }

    var isShowingAll: Bool {
        activeTabID == ALL_TAB_ID
    }

    var isShowingDashboard: Bool {
        activeTabID == DASHBOARD_TAB_ID
    }

    var isSpecialView: Bool {
        isShowingHidden || isShowingAll || isShowingDashboard
    }

    func allActivePanesOrdered() -> [ActivePane] {
        var out: [ActivePane] = []
        for (i, tab) in tabs.enumerated() {
            let tabTitle: String = {
                if let n = tab.name, !n.isEmpty { return n }
                let t = tab.leafTitles[tab.activeLeafID]
                return (t?.isEmpty == false) ? t! : "Tab \(i + 1)"
            }()
            for sid in tab.leafSessionIDsInOrder() {
                let title = tab.leafTitles[sid] ?? "shell"
                out.append(ActivePane(
                    tabID: tab.id,
                    tabIndex: i,
                    tabTitle: tabTitle,
                    sessionID: sid,
                    title: title
                ))
            }
        }
        return out
    }

    func jumpToPane(tabID: UUID, sessionID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        tab.activeLeafID = sessionID
        flashLeafID = nil
        DispatchQueue.main.async { [weak self] in
            self?.flashLeafID = sessionID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.flashLeafID == sessionID {
                self?.flashLeafID = nil
            }
        }
    }

    func closePane(tabID: UUID, sessionID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        _ = tab.closeLeaf(sessionID: sessionID, sendExit: true)
    }

    func newTab() {
        let t = TabSession(cwd: cwd)
        t.session = self
        tabs.append(t)
        activeTabID = t.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        if let i = tabs.firstIndex(where: { $0.id == id }) {
            let target = tabs[i]
            for (_, term) in target.terminals {
                killTerminalProcessTree(term)
            }
            target.terminals.removeAll()
            tabs.remove(at: i)
        }
        if activeTabID == id, let first = tabs.first {
            activeTabID = first.id
        }
    }

    func closeActivePaneOrTab() {
        guard !isSpecialView else { return }
        guard let tab = activeTab else { return }
        if tab.hasOnlySingleLeaf && tabs.count > 1 {
            closeTab(tab.id)
        } else {
            tab.closeActive()
        }
    }

    func hideLeaf(in tab: TabSession, sessionID: UUID) {
        guard let term = tab.terminals[sessionID], let del = tab.delegates[sessionID] else { return }
        let title = tab.leafTitles[sessionID] ?? "shell"

        hiddenPanes.append(HiddenPane(id: sessionID, title: title))
        hiddenTerminals[sessionID] = term
        hiddenDelegates[sessionID] = del

        tab.terminals.removeValue(forKey: sessionID)
        tab.delegates.removeValue(forKey: sessionID)
        tab.leafTitles.removeValue(forKey: sessionID)
        if tab.zoomedLeafID == sessionID { tab.zoomedLeafID = nil }
        _ = tab.removeLeafFromTree(sessionID: sessionID)
    }

    func restoreHidden(_ sessionID: UUID) {
        guard let term = hiddenTerminals[sessionID], let del = hiddenDelegates[sessionID] else { return }
        guard let hp = hiddenPanes.first(where: { $0.id == sessionID }) else { return }

        let destTab: TabSession
        if isShowingHidden {
            destTab = tabs.first ?? {
                let t = TabSession(cwd: cwd); t.session = self; tabs.append(t); return t
            }()
            activeTabID = destTab.id
        } else if let active = activeTab {
            destTab = active
        } else if let first = tabs.first {
            destTab = first
            activeTabID = first.id
        } else {
            return
        }

        hiddenPanes.removeAll { $0.id == sessionID }
        hiddenTerminals.removeValue(forKey: sessionID)
        hiddenDelegates.removeValue(forKey: sessionID)

        destTab.transferTerminal(term, delegate: del, sessionID: sessionID, title: hp.title)
        destTab.insertAsVerticalSplit(sessionID: sessionID)
    }

    func killHidden(_ sessionID: UUID) {
        if let term = hiddenTerminals[sessionID] {
            killTerminalProcessTree(term)
        }
        hiddenTerminals.removeValue(forKey: sessionID)
        hiddenDelegates.removeValue(forKey: sessionID)
        hiddenPanes.removeAll { $0.id == sessionID }
        if hiddenPanes.isEmpty && activeTabID == HIDDEN_TAB_ID {
            activeTabID = tabs.first?.id ?? UUID()
        }
    }

    func removeTerminalAnywhere(sessionID: UUID) {
        if hiddenPanes.contains(where: { $0.id == sessionID }) {
            killHidden(sessionID)
            return
        }
        for tab in tabs {
            if tab.terminals[sessionID] != nil {
                _ = tab.closeLeaf(sessionID: sessionID, sendExit: false)
                return
            }
        }
    }

    func setTitleAnywhere(sessionID: UUID, title: String) {
        if let idx = hiddenPanes.firstIndex(where: { $0.id == sessionID }) {
            hiddenPanes[idx].title = title
            return
        }
        for tab in tabs {
            if tab.terminals[sessionID] != nil {
                tab.leafTitles[sessionID] = title
                return
            }
        }
    }

    func start(with config: StartupConfig?) {
        started = true
        guard let tab = activeTab else { return }
        guard let config = config else {
            _ = tab.terminal(for: tab.activeLeafID)
            return
        }
        applyConfig(config, to: tab)
    }

    func endSession() {
        for tab in tabs {
            for (_, term) in tab.terminals {
                killTerminalProcessTree(term)
            }
            tab.terminals.removeAll()
            tab.delegates.removeAll()
            tab.leafTitles.removeAll()
            tab.zoomedLeafID = nil
        }
        for (_, term) in hiddenTerminals {
            killTerminalProcessTree(term)
        }
        hiddenTerminals.removeAll()
        hiddenDelegates.removeAll()
        hiddenPanes.removeAll()
        let fresh = TabSession(cwd: cwd)
        fresh.session = self
        tabs = [fresh]
        activeTabID = fresh.id
        started = false
    }

    private func applyConfig(_ config: StartupConfig, to tab: TabSession) {
        let leafIDs = (0..<config.layout.paneCount).map { _ in UUID() }
        let root = ProjectSession.buildLayoutTree(config.layout, leafIDs: leafIDs)
        tab.root = root
        tab.activeLeafID = leafIDs.first ?? UUID()

        for (idx, sid) in leafIDs.enumerated() where idx < config.panes.count {
            let pane = config.panes[idx]
            let view = tab.terminal(for: sid)
            if !pane.name.isEmpty {
                tab.leafTitles[sid] = pane.name
            }
            if !pane.command.isEmpty {
                let cmd = pane.command
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    view.send(txt: cmd + "\n")
                }
            }
        }
    }

    private static func buildLayoutTree(_ layout: StartupLayout, leafIDs: [UUID]) -> SplitNode {
        func leaf(_ sid: UUID) -> SplitNode { SplitNode(content: .leaf(sessionID: sid)) }

        switch layout {
        case .singlePane:
            return leaf(leafIDs[0])
        case .grid2x2:
            let colLeft = SplitNode(content: .split(axis: .horizontal, children: [leaf(leafIDs[0]), leaf(leafIDs[2])]))
            let colRight = SplitNode(content: .split(axis: .horizontal, children: [leaf(leafIDs[1]), leaf(leafIDs[3])]))
            return SplitNode(content: .split(axis: .vertical, children: [colLeft, colRight]))
        case .bigTopThreeBottom:
            let top = leaf(leafIDs[0])
            let bot = SplitNode(content: .split(axis: .vertical, children: [leaf(leafIDs[1]), leaf(leafIDs[2]), leaf(leafIDs[3])]))
            return SplitNode(content: .split(axis: .horizontal, children: [top, bot]))
        case .leftMainRightStacked:
            let left = leaf(leafIDs[0])
            let right = SplitNode(content: .split(axis: .horizontal, children: [leaf(leafIDs[1]), leaf(leafIDs[2]), leaf(leafIDs[3])]))
            return SplitNode(content: .split(axis: .vertical, children: [left, right]))
        case .rowsStacked:
            let leaves = leafIDs.map { leaf($0) }
            return SplitNode(content: .split(axis: .horizontal, children: leaves))
        }
    }
}

@MainActor
final class TerminalDelegate: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
    weak var session: ProjectSession?
    let sessionID: UUID

    init(session: ProjectSession?, sessionID: UUID) {
        self.session = session
        self.sessionID = sessionID
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard !title.isEmpty else { return }
        let sid = sessionID
        let s = session
        Task { @MainActor in
            s?.setTitleAnywhere(sessionID: sid, title: title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let sid = sessionID
        let s = session
        // Defer to next runloop tick so SwiftTerm can finish unwinding before
        // we drop our reference to the terminal view. Without this, the view
        // can be released mid-callback and the whole pane tree goes blank.
        Task { @MainActor in
            s?.removeTerminalAnywhere(sessionID: sid)
        }
    }
}

import Foundation
import Observation

struct SessionSnapshot: Codable {
    var savedAt: Date
    var activeProjectID: UUID?
    var projects: [ProjectSnapshot]
}

struct ProjectSnapshot: Codable {
    var projectID: UUID
    var activeTabID: UUID?
    var tabs: [TabSnapshot]
    var hiddenPanes: [PaneSnapshot]
}

struct TabSnapshot: Codable {
    var id: UUID
    var name: String?
    var activeLeafID: UUID?
    var root: LayoutSnap
    var panes: [PaneSnapshot]
    // parent SplitNode.id (as string) → child fractions
    var splitFractions: [String: [Double]]
}

struct PaneSnapshot: Codable, Identifiable {
    var id: UUID            // sessionID (matches LayoutSnap.leaf sid)
    var title: String
    var cwd: String
}

indirect enum LayoutSnap: Codable {
    case leaf(sid: UUID)
    case split(axis: SplitAxisSnap, children: [LayoutSnap])

    enum CodingKeys: String, CodingKey { case kind, sid, axis, children }
    enum Kind: String, Codable { case leaf, split }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .leaf:
            self = .leaf(sid: try c.decode(UUID.self, forKey: .sid))
        case .split:
            self = .split(
                axis: try c.decode(SplitAxisSnap.self, forKey: .axis),
                children: try c.decode([LayoutSnap].self, forKey: .children)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let sid):
            try c.encode(Kind.leaf, forKey: .kind)
            try c.encode(sid, forKey: .sid)
        case .split(let axis, let children):
            try c.encode(Kind.split, forKey: .kind)
            try c.encode(axis, forKey: .axis)
            try c.encode(children, forKey: .children)
        }
    }
}

enum SplitAxisSnap: String, Codable {
    case vertical, horizontal
}

@Observable
@MainActor
final class SessionSnapshotStore {
    @ObservationIgnored let fileURL: URL

    init() {
        self.fileURL = TideStorage.file("session_snapshot.json")
    }

    func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(SessionSnapshot.self, from: data)
    }

    func save(_ snap: SessionSnapshot) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    var hasSavedSnapshot: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func projectSnapshot(for projectID: UUID) -> ProjectSnapshot? {
        load()?.projects.first(where: { $0.projectID == projectID })
    }
}

@MainActor
enum SessionSnapshotBuilder {
    /// Build a snapshot of the current in-memory state across all projects.
    /// Skips projects with no started session (nothing meaningful to persist).
    static func capture(store: ProjectStore) -> SessionSnapshot {
        var projects: [ProjectSnapshot] = []
        for project in store.projects {
            guard let session = store.sessions[project.id], session.started else { continue }
            let tabs = session.tabs.map { tabSnapshot($0) }
            let hidden = session.hiddenPanes.map { hp in
                PaneSnapshot(
                    id: hp.id,
                    title: hp.title,
                    cwd: session.cwd       // hidden panes lose cwd tracking when detached; use project cwd
                )
            }
            projects.append(ProjectSnapshot(
                projectID: project.id,
                activeTabID: session.activeTabID,
                tabs: tabs,
                hiddenPanes: hidden
            ))
        }
        return SessionSnapshot(
            savedAt: Date(),
            activeProjectID: store.selectedID,
            projects: projects
        )
    }

    private static func tabSnapshot(_ tab: TabSession) -> TabSnapshot {
        let layout = encodeLayout(tab.root)
        var panes: [PaneSnapshot] = []
        for sid in tab.leafSessionIDsInOrder() {
            panes.append(PaneSnapshot(
                id: sid,
                title: tab.leafTitles[sid] ?? "",
                cwd: tab.leafCwds[sid] ?? tab.cwd
            ))
        }
        var fractions: [String: [Double]] = [:]
        for (k, v) in tab.splitFractions {
            fractions[k.uuidString] = v.map { Double($0) }
        }
        return TabSnapshot(
            id: tab.id,
            name: tab.name,
            activeLeafID: tab.activeLeafID,
            root: layout,
            panes: panes,
            splitFractions: fractions
        )
    }

    private static func encodeLayout(_ node: SplitNode) -> LayoutSnap {
        switch node.content {
        case .leaf(let sid):
            return .leaf(sid: sid)
        case .split(let axis, let children):
            return .split(
                axis: axis == .vertical ? .vertical : .horizontal,
                children: children.map { encodeLayout($0) }
            )
        }
    }
}

@MainActor
enum SessionRestorer {
    /// Rebuilds the in-memory project sessions from a snapshot and spawns
    /// terminals in their captured cwds. Skips snapshot projects whose
    /// `projectID` no longer exists in the store.
    static func restore(snapshot: SessionSnapshot, into store: ProjectStore) {
        for projSnap in snapshot.projects {
            guard let project = store.projects.first(where: { $0.id == projSnap.projectID }) else { continue }
            let session = store.session(for: project)
            applyProject(projSnap, into: session)
        }
        if let active = snapshot.activeProjectID,
           store.projects.contains(where: { $0.id == active }) {
            store.selectedID = active
        }
    }

    static func restore(projectSnapshot: ProjectSnapshot, into session: ProjectSession) {
        applyProject(projectSnapshot, into: session)
    }

    static func applyProject(_ snap: ProjectSnapshot, into session: ProjectSession) {
        // Wipe any default startup state.
        session.endSession()

        var rebuiltTabs: [TabSession] = []
        for tabSnap in snap.tabs {
            let tab = TabSession(cwd: session.cwd, id: tabSnap.id)
            tab.name = tabSnap.name
            tab.session = session

            let (root, parentIDs) = buildLayout(tabSnap.root)
            tab.root = root

            // Seed cwds before spawning so terminal() uses the right dir.
            for pane in tabSnap.panes {
                tab.leafCwds[pane.id] = pane.cwd
                if !pane.title.isEmpty { tab.leafTitles[pane.id] = pane.title }
            }
            // Map serialized parent IDs onto the freshly-built nodes' UUIDs.
            for (i, parentID) in parentIDs.enumerated() {
                let key = parentID.uuidString
                if let frac = tabSnap.splitFractions[key] {
                    tab.splitFractions[parentIDs[i]] = frac.map { CGFloat($0) }
                }
            }

            if let active = tabSnap.activeLeafID {
                tab.activeLeafID = active
            } else if let first = tabSnap.panes.first {
                tab.activeLeafID = first.id
            }

            // Spawn terminals now so every pane is live on first paint.
            for pane in tabSnap.panes {
                _ = tab.terminal(for: pane.id)
            }
            rebuiltTabs.append(tab)
        }

        if rebuiltTabs.isEmpty {
            // Snapshot was empty for this project — leave a fresh empty tab so
            // `endSession()`'s default state stays usable.
            return
        }

        session.tabs = rebuiltTabs
        session.activeTabID = snap.activeTabID ?? rebuiltTabs.first!.id
        session.started = true
    }

    /// Returns the new SplitNode tree plus the IDs of all split parent nodes
    /// in the order they were created — used to remap splitFractions whose
    /// keys are SplitNode.id strings.
    private static func buildLayout(_ snap: LayoutSnap) -> (SplitNode, [UUID]) {
        var parentIDs: [UUID] = []
        func walk(_ s: LayoutSnap) -> SplitNode {
            switch s {
            case .leaf(let sid):
                return SplitNode(content: .leaf(sessionID: sid))
            case .split(let axis, let children):
                let kids = children.map { walk($0) }
                let node = SplitNode(content: .split(
                    axis: axis == .vertical ? .vertical : .horizontal,
                    children: kids
                ))
                parentIDs.append(node.id)
                return node
            }
        }
        let root = walk(snap)
        return (root, parentIDs)
    }
}

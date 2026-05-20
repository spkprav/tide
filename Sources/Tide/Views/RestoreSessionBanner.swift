import SwiftUI

struct RestoreSessionBanner: View {
    @Environment(SessionSnapshotStore.self) private var snapshotStore
    @Environment(ProjectStore.self) private var store

    @State private var loadedSnap: SessionSnapshot?
    @State private var dismissed = false

    var body: some View {
        Group {
            if let snap = loadedSnap, !dismissed {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color.tnBlue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Restore previous session")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SwiftUI.Color.tnFg)
                        Text(subtitle(for: snap))
                            .font(.system(size: 10))
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button {
                        restore(snap)
                    } label: {
                        Label("Restore", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(TidePrimaryButton())
                    .controlSize(.small)

                    Button {
                        snapshotStore.clear()
                        dismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Discard snapshot")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SwiftUI.Color.tnBg2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(SwiftUI.Color.tnLine).frame(height: 1)
                }
            }
        }
        .onAppear {
            loadedSnap = snapshotStore.load()
        }
    }

    private func subtitle(for snap: SessionSnapshot) -> String {
        let projCount = snap.projects.count
        let paneCount = snap.projects.reduce(0) { acc, p in
            acc + p.tabs.reduce(0) { $0 + $1.panes.count } + p.hiddenPanes.count
        }
        let when = Self.relativeFormatter.localizedString(for: snap.savedAt, relativeTo: Date())
        return "\(projCount) project\(projCount == 1 ? "" : "s"), \(paneCount) pane\(paneCount == 1 ? "" : "s") · saved \(when)"
    }

    private func restore(_ snap: SessionSnapshot) {
        SessionRestorer.restore(snapshot: snap, into: store)
        dismissed = true
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

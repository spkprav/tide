import SwiftUI
import AppKit

let ACTIVE_SESSIONS_ID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

struct GlobalCell: Identifiable, Hashable {
    var id: UUID { sessionID }
    let project: Project
    let tabID: UUID
    let tabIndex: Int
    let tabTitle: String
    let sessionID: UUID
    let title: String
}

struct ActiveSessionsView: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        let cells = collectCells()
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.grid.2x2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                Text("Active Sessions")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(cells.count) panes · \(uniqueProjectCount(cells)) projects")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
            }

            if cells.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Start a project to see its panes here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ],
                        spacing: 8
                    ) {
                        ForEach(cells) { cell in
                            GlobalPaneCell(cell: cell)
                                .frame(height: 140)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black)
            }
        }
    }

    private func collectCells() -> [GlobalCell] {
        var out: [GlobalCell] = []
        for p in store.projects {
            guard let s = store.sessions[p.id], s.started else { continue }
            for pane in s.allActivePanesOrdered() {
                out.append(GlobalCell(
                    project: p,
                    tabID: pane.tabID,
                    tabIndex: pane.tabIndex,
                    tabTitle: pane.tabTitle,
                    sessionID: pane.sessionID,
                    title: pane.title
                ))
            }
        }
        return out
    }

    private func uniqueProjectCount(_ cells: [GlobalCell]) -> Int {
        Set(cells.map { $0.project.id }).count
    }
}

struct GlobalPaneCell: View {
    let cell: GlobalCell
    @Environment(ProjectStore.self) private var store
    @State private var hover = false

    var body: some View {
        Button {
            jumpTo()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(cell.project.color)
                        .frame(width: 10, height: 10)
                        .shadow(color: cell.project.color.opacity(hover ? 0.8 : 0), radius: hover ? 6 : 0)
                    Text(cell.project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        closePane()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle().fill(Color.primary.opacity(hover ? 0.10 : 0.0))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close pane")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(cell.title)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(cell.tabTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 11))
                    Text("Open pane")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    if hover {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.yellow)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(hover ? cell.project.color : Color.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: hover ? 0.13 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        hover ? cell.project.color.opacity(0.75) : Color.white.opacity(0.06),
                        lineWidth: hover ? 1.5 : 1
                    )
            )
            .shadow(color: hover ? cell.project.color.opacity(0.35) : .clear, radius: hover ? 14 : 0)
            .scaleEffect(hover ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hover = isHovering
            }
        }
    }

    private func jumpTo() {
        let session = store.session(for: cell.project)
        store.selectedID = cell.project.id
        session.jumpToPane(tabID: cell.tabID, sessionID: cell.sessionID)
    }

    private func closePane() {
        guard let session = store.sessions[cell.project.id] else { return }
        session.closePane(tabID: cell.tabID, sessionID: cell.sessionID)
    }
}

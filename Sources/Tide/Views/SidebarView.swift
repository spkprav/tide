import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(ProjectStore.self) private var store
    @State private var showAddSheet = false
    @State private var editing: Project?

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedID) {
            Section {
                OverviewRowItem()
                    .tag(OVERVIEW_ID)
                StatsRowItem()
                    .tag(STATS_ID)
                ActiveSessionsRow(count: store.totalActivePaneCount)
                    .tag(ACTIVE_SESSIONS_ID)
                NotificationsRowItem(count: store.totalArmedReminderCount)
                    .tag(NOTIFICATIONS_ID)
            }
            .listRowBackground(SwiftUI.Color.clear)
            Section {
                ForEach(store.projects) { project in
                    SidebarRow(project: project, isSelected: store.selectedID == project.id)
                        .tag(project.id)
                        .listRowBackground(SwiftUI.Color.clear)
                        .contextMenu {
                            Button("Edit…") { editing = project }
                            Button("Open in Editor") {
                                EditorLauncher.open(project.expandedPath)
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: project.expandedPath))
                            }
                            if !project.isPinned {
                                Divider()
                                Button("Remove", role: .destructive) {
                                    store.remove(id: project.id)
                                }
                            }
                        }
                }
                .onMove { from, to in
                    store.move(from: from, to: to)
                }
            } header: {
                Text("Projects")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(SwiftUI.Color.tnFg3)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SwiftUI.Color.tnBg2)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add project")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(SwiftUI.Color.white.opacity(0.02))
                )
            }
            .padding(8)
            .background(SwiftUI.Color.tnBg2)
            .overlay(alignment: .top) {
                Rectangle().fill(SwiftUI.Color.tnLine).frame(height: 1)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddProjectSheet { newProject in
                store.add(newProject)
            }
        }
        .sheet(item: $editing) { project in
            AddProjectSheet(editing: project) { updated in
                store.update(updated)
            }
        }
    }
}

struct OverviewRowItem: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 12))
                .foregroundStyle(SwiftUI.Color.tnBlue)
                .frame(width: 14, height: 14)
            Text("Overview")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwiftUI.Color.tnFg)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct StatsRowItem: View {
    @Environment(UsageTracker.self) private var tracker

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 12))
                .foregroundStyle(SwiftUI.Color.tnCyan)
                .frame(width: 14, height: 14)
            Text("Usage Stats")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwiftUI.Color.tnFg)
            Spacer(minLength: 0)
            Text(UsageTracker.formatDuration(tracker.totalActiveTodaySeconds))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SwiftUI.Color.tnFg3)
        }
        .padding(.vertical, 2)
    }
}

struct NotificationsRowItem: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.system(size: 12))
                .foregroundStyle(SwiftUI.Color.tnYellow)
                .frame(width: 14, height: 14)
            Text("Notifications")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwiftUI.Color.tnFg)
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnBg)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(SwiftUI.Color.tnYellow))
            }
        }
        .padding(.vertical, 2)
    }
}

struct ActiveSessionsRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 12))
                .foregroundStyle(SwiftUI.Color.tnPurple)
                .frame(width: 14, height: 14)
            Text("Active Sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwiftUI.Color.tnFg)
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnBg)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(SwiftUI.Color.tnPurple))
            }
        }
        .padding(.vertical, 2)
    }
}

struct SidebarRow: View {
    let project: Project
    var isSelected: Bool = false
    @AppStorage("tide.sidebar.showProjectPath") private var showPath: Bool = true
    @State private var editorHover = false

    var body: some View {
        HStack(spacing: 10) {
            if project.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(project.color)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(project.color)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SwiftUI.Color.tnFg : SwiftUI.Color.tnFg2)
                if showPath {
                    Text(displayPath(project.expandedPath))
                        .font(.system(size: 11))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Button {
                EditorLauncher.open(project.expandedPath)
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(editorHover ? SwiftUI.Color.tnGreen : SwiftUI.Color.tnFg3)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(editorHover ? SwiftUI.Color.tnGreen.opacity(0.12) : SwiftUI.Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in editor")
            .onHover { editorHover = $0 }
        }
        .padding(.vertical, 2)
    }

    private func displayPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
    }
}

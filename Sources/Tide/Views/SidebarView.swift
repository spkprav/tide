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
            Section {
                ForEach(store.projects) { project in
                    SidebarRow(project: project)
                        .tag(project.id)
                        .contextMenu {
                            Button("Edit…") { editing = project }
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
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 8)
            .background(.bar)
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, height: 14)
            Text("Overview")
                .font(.system(size: 13, weight: .medium))
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, height: 14)
            Text("Usage Stats")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            Text(UsageTracker.formatDuration(tracker.totalActiveTodaySeconds))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.yellow)
                .frame(width: 14, height: 14)
            Text("Notifications")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.yellow.opacity(0.85)))
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, height: 14)
            Text("Active Sessions")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
        .padding(.vertical, 2)
    }
}

struct SidebarRow: View {
    let project: Project
    @AppStorage("tide.sidebar.showProjectPath") private var showPath: Bool = true

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
                    .font(.system(size: 13, weight: .medium))
                if showPath {
                    Text(displayPath(project.expandedPath))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func displayPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
    }
}

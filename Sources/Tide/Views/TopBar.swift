import SwiftUI
import AppKit

// Inline pieces rendered into the macOS window toolbar (via .toolbar in
// ContentView) when the sidebar is collapsed. Lives in the same row as the
// traffic-light cluster — no extra reserved row.

struct TopBarChipsRow: View {
    @Environment(ProjectStore.self) private var store
    @State private var showAddSheet = false

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.projects) { project in
                        ProjectChip(
                            project: project,
                            isActive: store.selectedID == project.id
                        ) {
                            store.selectedID = project.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: 720)

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .frame(width: 26, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add project")
        }
        .sheet(isPresented: $showAddSheet) {
            AddProjectSheet { newProject in
                store.add(newProject)
            }
        }
    }
}

struct TopBarActions: View {
    @Environment(ProjectStore.self) private var store
    @Environment(UsageTracker.self) private var tracker

    var body: some View {
        @Bindable var store = store
        TopBarActionButton(
            systemImage: "square.grid.3x3.fill",
            tint: SwiftUI.Color.tnBlue,
            isActive: store.selectedID == OVERVIEW_ID,
            tooltip: "Overview"
        ) {
            store.selectedID = OVERVIEW_ID
        }

        TopBarActionButton(
            systemImage: "chart.bar.xaxis",
            tint: SwiftUI.Color.tnCyan,
            isActive: store.selectedID == STATS_ID,
            tooltip: "Usage · \(UsageTracker.formatDuration(tracker.totalActiveTodaySeconds)) today"
        ) {
            store.selectedID = STATS_ID
        }

        TopBarActionButton(
            systemImage: "rectangle.grid.2x2",
            tint: SwiftUI.Color.tnPurple,
            badge: store.totalActivePaneCount,
            isActive: store.selectedID == ACTIVE_SESSIONS_ID,
            tooltip: "Active sessions"
        ) {
            store.selectedID = ACTIVE_SESSIONS_ID
        }

        TopBarActionButton(
            systemImage: "bell.badge",
            tint: SwiftUI.Color.tnYellow,
            badge: store.totalArmedReminderCount,
            isActive: store.selectedID == NOTIFICATIONS_ID,
            tooltip: "Notifications"
        ) {
            store.selectedID = NOTIFICATIONS_ID
        }
    }
}

struct ProjectChip: View {
    let project: Project
    let isActive: Bool
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if project.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isActive ? SwiftUI.Color.white : project.color)
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(isActive ? SwiftUI.Color.white : project.color)
                        .frame(width: 8, height: 8)
                }
                Text(project.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? SwiftUI.Color.white : SwiftUI.Color.tnFg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: 160)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? SwiftUI.Color.tnBlue : (hover ? SwiftUI.Color.tnBg3 : SwiftUI.Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isActive ? SwiftUI.Color.clear : (hover ? SwiftUI.Color.tnLine : SwiftUI.Color.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(project.name)
    }
}

struct TopBarActionButton: View {
    let systemImage: String
    let tint: SwiftUI.Color
    var badge: Int? = nil
    let isActive: Bool
    let tooltip: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? tint : (hover ? SwiftUI.Color.tnFg : SwiftUI.Color.tnFg3))
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isActive ? tint.opacity(0.14) : (hover ? SwiftUI.Color.tnBg3 : SwiftUI.Color.clear))
                    )
                if let b = badge, b > 0 {
                    Text("\(b)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SwiftUI.Color.tnBg)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tint))
                        .offset(x: 4, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tooltip)
    }
}

import SwiftUI

let NOTIFICATIONS_ID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!

struct NotificationsView: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        let armed = collectArmedReminders()
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                Text("Active Notifications")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(armed.count) armed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(white: 0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
            }

            if armed.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No armed reminders")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Click 🔔 in a pane title bar to arm a reminder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        ForEach(armed) { card in
                            NotificationCardView(card: card)
                        }
                    }
                    .padding(10)
                }
                .background(Color.black)
            }
        }
    }

    struct ArmedCard: Identifiable {
        var id: UUID { sessionID }
        let project: Project
        let tabID: UUID
        let tabTitle: String
        let sessionID: UUID
        let title: String
        let reminder: PaneReminder
    }

    private func collectArmedReminders() -> [ArmedCard] {
        var out: [ArmedCard] = []
        for project in store.projects {
            guard let session = store.sessions[project.id] else { continue }
            for (i, tab) in session.tabs.enumerated() {
                let tabName: String = {
                    if let n = tab.name, !n.isEmpty { return n }
                    let t = tab.leafTitles[tab.activeLeafID]
                    return (t?.isEmpty == false) ? t! : "Tab \(i + 1)"
                }()
                for (sid, r) in tab.reminders {
                    let paneTitle = tab.leafTitles[sid] ?? "pane"
                    out.append(ArmedCard(
                        project: project,
                        tabID: tab.id,
                        tabTitle: tabName,
                        sessionID: sid,
                        title: paneTitle,
                        reminder: r
                    ))
                }
            }
        }
        return out.sorted { a, b in
            kindRank(a.reminder.kind) < kindRank(b.reminder.kind)
        }
    }

    private func kindRank(_ k: ReminderKind) -> Int {
        switch k {
        case .aiMonitor:   return 0
        case .processExit: return 1
        case .claudeDone:  return 2
        }
    }
}

private struct NotificationCardView: View {
    let card: NotificationsView.ArmedCard
    @Environment(ProjectStore.self) private var store
    @State private var hover = false

    var body: some View {
        let kind = card.reminder.kind
        let info = ReminderUI.info(for: kind, sawActivity: card.reminder.sawActivity)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(card.project.color)
                    .frame(width: 10, height: 10)
                Text(card.project.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: info.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(info.color)
            }

            HStack(spacing: 6) {
                Text(info.kindLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(info.color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(info.color.opacity(0.18)))
                Text(info.statusLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(card.title)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(card.tabTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !card.reminder.message.isEmpty {
                Text(card.reminder.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    jumpTo()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open").font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                }
                Button(role: .destructive) {
                    cancelReminder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.slash")
                        Text("Cancel").font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .frame(minHeight: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: hover ? 0.13 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    hover ? info.color.opacity(0.7) : Color.white.opacity(0.06),
                    lineWidth: hover ? 1.5 : 1
                )
        )
        .shadow(color: hover ? info.color.opacity(0.3) : .clear, radius: hover ? 10 : 0)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.15)) { hover = isHovering }
        }
    }

    private func jumpTo() {
        guard let session = store.sessions[card.project.id] else { return }
        store.selectedID = card.project.id
        session.jumpToPane(tabID: card.tabID, sessionID: card.sessionID)
    }

    private func cancelReminder() {
        guard let session = store.sessions[card.project.id] else { return }
        guard let tab = session.tabs.first(where: { $0.id == card.tabID }) else { return }
        session.clearReminder(in: tab, sessionID: card.sessionID)
    }
}

enum ReminderUI {
    struct Info {
        var icon: String
        var color: Color
        var kindLabel: String
        var statusLabel: String
    }

    static func info(for kind: ReminderKind, sawActivity: Bool) -> Info {
        switch kind {
        case .processExit:
            return Info(
                icon: sawActivity ? "stop.circle.fill" : "stop.circle",
                color: .green,
                kindLabel: "Process exit",
                statusLabel: sawActivity ? "Watching active task" : "Waiting for activity"
            )
        case .claudeDone:
            return Info(
                icon: "sparkle",
                color: .purple,
                kindLabel: "Claude done",
                statusLabel: "Waiting for Claude Stop event"
            )
        case .aiMonitor:
            return Info(
                icon: "eye.circle.fill",
                color: .orange,
                kindLabel: "AI monitor",
                statusLabel: "Polling Ollama"
            )
        }
    }
}

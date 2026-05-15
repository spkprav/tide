import SwiftUI

let STATS_ID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

struct StatsView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(UsageTracker.self) private var tracker

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                Text("Usage Stats")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                HStack(spacing: 12) {
                    StatBadge(title: "Today", value: UsageTracker.formatDuration(tracker.totalActiveTodaySeconds), color: .accentColor)
                    StatBadge(title: "All time", value: UsageTracker.formatDuration(tracker.totalAllTimeSeconds), color: .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.10))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
            }

            let rows = sortedRows()
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No activity recorded yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Start a project to track usage")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            StatsRow(project: row.project, stats: row.stats)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .background(Color.black)
            }
        }
    }

    private struct Row: Identifiable {
        var id: UUID { project.id }
        let project: Project
        let stats: ProjectStats
    }

    private func sortedRows() -> [Row] {
        let rows: [Row] = store.projects.compactMap { p in
            let s = tracker.stats(for: p.id)
            guard s.sessionCount > 0 || s.totalActiveSeconds > 0 else { return nil }
            return Row(project: p, stats: s)
        }
        return rows.sorted { a, b in
            (a.stats.lastFocusedAt ?? a.stats.lastOpened ?? .distantPast)
            > (b.stats.lastFocusedAt ?? b.stats.lastOpened ?? .distantPast)
        }
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

struct StatsRow: View {
    let project: Project
    let stats: ProjectStats

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(project.color)
                .frame(width: 12, height: 12)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .semibold))
                    if project.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(project.color.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                    Text(UsageTracker.formatRelativeDate(stats.lastFocusedAt ?? stats.lastOpened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    StatColumn(label: "Sessions", value: "\(stats.sessionCount)")
                    StatColumn(label: "Today",    value: UsageTracker.formatDuration(stats.dayBuckets[UsageTracker.dayKey(Date())] ?? 0))
                    StatColumn(label: "7 days",   value: UsageTracker.formatDuration(sumLastDays(stats: stats, days: 7)))
                    StatColumn(label: "All time", value: UsageTracker.formatDuration(stats.totalActiveSeconds))
                }

                MiniBarChart(stats: stats, days: 14, color: project.color)
                    .frame(height: 28)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sumLastDays(stats: ProjectStats, days: Int) -> TimeInterval {
        let cal = Calendar.current
        var total: TimeInterval = 0
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = UsageTracker.dayKey(day)
            total += stats.dayBuckets[key] ?? 0
        }
        return total
    }
}

struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

struct MiniBarChart: View {
    let stats: ProjectStats
    let days: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let cal = Calendar.current
            let buckets: [TimeInterval] = (0..<days).reversed().map { offset in
                guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return 0 }
                let key = UsageTracker.dayKey(day)
                return stats.dayBuckets[key] ?? 0
            }
            let maxVal = max(buckets.max() ?? 0, 60)
            let totalWidth = geo.size.width
            let gap: CGFloat = 2
            let count = CGFloat(buckets.count)
            let barWidth = (totalWidth - (count - 1) * gap) / count

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, val in
                    let h = max(2, CGFloat(val / maxVal) * geo.size.height)
                    Rectangle()
                        .fill(val > 0 ? color.opacity(0.8) : Color.primary.opacity(0.10))
                        .frame(width: barWidth, height: h)
                }
            }
            .frame(width: totalWidth, height: geo.size.height, alignment: .bottomLeading)
        }
    }
}

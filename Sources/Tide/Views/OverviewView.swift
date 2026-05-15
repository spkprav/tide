import SwiftUI
import AppKit

let OVERVIEW_ID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!

struct OverviewColumn: Identifiable {
    var id: String { project.id.uuidString + "::" + ref.repo }
    let project: Project
    let ref: GitHubClient.RepoRef
    var issues: [GitHubClient.Issue]
    var prs: [GitHubClient.PR]
    var loading: Bool
    var error: String?
}

struct OverviewView: View {
    @Environment(ProjectStore.self) private var store

    @State private var columns: [OverviewColumn] = []
    @State private var loading: Bool = false
    @State private var lastRefresh: Date?
    @State private var globalError: String?
    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if let err = globalError {
                errorView(err)
            } else if columns.isEmpty && !loading {
                emptyView
            } else {
                HSplitView {
                    kanbanPane
                        .frame(minWidth: 540)
                    prsSidebar
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                }
            }
        }
        .background(Color.black)
        .onAppear {
            if columns.isEmpty { refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
            Text("Overview")
                .font(.system(size: 16, weight: .semibold))

            HStack(spacing: 10) {
                Pill(icon: "exclamationmark.circle.fill", label: "\(totalIssues) issues", color: .green)
                Pill(icon: "arrow.triangle.pull", label: "\(totalPRs) PRs", color: .purple)
                Pill(icon: "shippingbox.fill", label: "\(columns.count) repos", color: .accentColor)
            }

            Spacer()

            TextField("Filter…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            if let lastRefresh {
                Text("updated \(UsageTracker.formatRelativeDate(lastRefresh))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Button {
                refresh()
            } label: {
                if loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(loading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    private var kanbanPane: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(filteredColumns) { column in
                    KanbanColumn(column: column, filter: search)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black)
    }

    private var prsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(Color.purple)
                Text("Pull Requests")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(filteredPRs.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(white: 0.08))

            if filteredPRs.isEmpty {
                Spacer()
                Text("No open PRs")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredPRs) { item in
                            OverviewPRRow(item: item)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color.black)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No GitHub repos detected across your projects")
                .font(.callout).foregroundStyle(.secondary)
            Text("Add projects whose folders contain `git remote -> github.com` to populate this view.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Refresh") { refresh() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.orange)
            Text(msg)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.center)
            Button("Retry") { refresh() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var totalIssues: Int { columns.reduce(0) { $0 + $1.issues.count } }
    private var totalPRs: Int { columns.reduce(0) { $0 + $1.prs.count } }

    private var filteredColumns: [OverviewColumn] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = columns.filter { col in
            if !col.issues.isEmpty { return true }
            if !col.prs.isEmpty { return true }
            return col.loading
        }
        if q.isEmpty { return visible }
        return visible.compactMap { col in
            let matchedIssues = col.issues.filter { issue in
                issue.title.lowercased().contains(q)
                || "\(issue.id)".contains(q)
                || issue.labels.joined(separator: " ").lowercased().contains(q)
                || issue.author.lowercased().contains(q)
            }
            if matchedIssues.isEmpty &&
                !col.project.name.lowercased().contains(q) &&
                !col.ref.repo.lowercased().contains(q) {
                return nil
            }
            var c = col
            c.issues = matchedIssues.isEmpty ? col.issues : matchedIssues
            return c
        }
    }

    struct PRItem: Identifiable {
        var id: String { "\(project.id)-\(ref.repo)-\(pr.id)" }
        let project: Project
        let ref: GitHubClient.RepoRef
        let pr: GitHubClient.PR
    }

    private var filteredPRs: [PRItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all: [PRItem] = columns.flatMap { col in
            col.prs.map { PRItem(project: col.project, ref: col.ref, pr: $0) }
        }
        if q.isEmpty { return all }
        return all.filter { item in
            item.pr.title.lowercased().contains(q)
                || "\(item.pr.id)".contains(q)
                || item.pr.author.lowercased().contains(q)
                || item.pr.head.lowercased().contains(q)
                || item.project.name.lowercased().contains(q)
                || item.ref.repo.lowercased().contains(q)
        }
    }

    private func refresh() {
        guard !loading else { return }
        globalError = nil
        if !GitHubClient.ghBinaryAvailable() {
            globalError = "`gh` CLI not found. Install with: brew install gh"
            return
        }
        loading = true

        let projects = store.projects
        Task {
            var initial: [OverviewColumn] = []
            for project in projects {
                let refs = GitHubClient.detectAllRepos(at: project.expandedPath)
                for ref in refs {
                    initial.append(OverviewColumn(project: project, ref: ref, issues: [], prs: [], loading: true))
                }
            }
            await MainActor.run {
                self.columns = initial
            }

            for project in projects {
                let refs = GitHubClient.detectAllRepos(at: project.expandedPath)
                for ref in refs {
                    let repo = ref.repo
                    async let i = GitHubClient.fetchIssues(repo: repo)
                    async let p = GitHubClient.fetchPRs(repo: repo)
                    let (iRes, pRes) = await (i, p)
                    await MainActor.run {
                        guard let idx = self.columns.firstIndex(where: {
                            $0.project.id == project.id && $0.ref.repo == repo
                        }) else { return }
                        var c = self.columns[idx]
                        c.loading = false
                        c.error = nil
                        switch iRes {
                        case .success(let v): c.issues = v
                        case .failure(let e): c.error = e.message
                        }
                        switch pRes {
                        case .success(let v): c.prs = v
                        case .failure(let e): if c.error == nil { c.error = e.message }
                        }
                        self.columns[idx] = c
                    }
                }
            }
            await MainActor.run {
                self.loading = false
                self.lastRefresh = Date()
            }
        }
    }
}

struct Pill: View {
    let icon: String
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct KanbanColumn: View {
    let column: OverviewColumn
    let filter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(column.project.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(column.project.name)
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    if !column.ref.isMain {
                        Image(systemName: "puzzlepiece.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                    Text(column.ref.repo)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text("\(column.issues.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.18)))
            if column.loading {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(white: 0.11))
        .overlay(alignment: .bottom) {
            Rectangle().fill(column.project.color.opacity(0.4)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let err = column.error {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 80)
        } else if column.issues.isEmpty && !column.loading {
            Text("No open issues")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(column.issues) { issue in
                        KanbanCard(issue: issue, projectColor: column.project.color)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct KanbanCard: View {
    let issue: GitHubClient.Issue
    let projectColor: Color
    @State private var hover = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: issue.url)!)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    stateIcon
                    Text("#\(issue.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(issue.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if !issue.labels.isEmpty {
                    FlowLabels(labels: issue.labels)
                }

                if let m = issue.milestone, !m.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9))
                        Text(m)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.yellow)
                }

                HStack(spacing: 8) {
                    if !issue.author.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "person.fill").font(.system(size: 8))
                            Text(issue.author).font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                    if !issue.assignees.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2.fill").font(.system(size: 8))
                            Text(issue.assignees.prefix(2).joined(separator: ", "))
                                .font(.system(size: 9))
                                .lineLimit(1)
                            if issue.assignees.count > 2 {
                                Text("+\(issue.assignees.count - 2)")
                                    .font(.system(size: 9))
                            }
                        }
                        .foregroundStyle(.cyan)
                    }
                    if issue.commentsCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bubble.left.fill").font(.system(size: 8))
                            Text("\(issue.commentsCount)").font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatDate(displayDate))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(white: hover ? 0.14 : 0.10))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(stateColor)
                    .frame(width: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(hover ? projectColor.opacity(0.6) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var stateColor: Color {
        issue.state.uppercased() == "OPEN" ? .green : .secondary
    }

    private var stateIcon: some View {
        Image(systemName: issue.state.uppercased() == "OPEN" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(stateColor)
    }

    private var displayDate: String {
        issue.updatedAt.isEmpty ? issue.createdAt : issue.updatedAt
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return "" }
        return UsageTracker.formatRelativeDate(date)
    }
}

struct FlowLabels: View {
    let labels: [String]
    var body: some View {
        let rows = labels.prefix(6)
        HStack(spacing: 3) {
            ForEach(Array(rows), id: \.self) { l in
                Text(l)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
        }
    }
}

struct OverviewPRRow: View {
    let item: OverviewView.PRItem
    @State private var hover = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: item.pr.url)!)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    stateIcon
                    Circle().fill(item.project.color).frame(width: 6, height: 6)
                    Text(item.project.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if !item.ref.isMain {
                        Text(item.ref.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    reviewBadge
                    Text("#\(item.pr.id)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(item.pr.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if item.pr.isDraft {
                        Text("DRAFT")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.25)))
                            .foregroundStyle(.secondary)
                    }
                    if !item.pr.author.isEmpty {
                        Text("@\(item.pr.author)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if item.pr.commentsCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 8))
                            Text("\(item.pr.commentsCount)")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                    if item.pr.additions + item.pr.deletions > 0 {
                        HStack(spacing: 2) {
                            Text("+\(item.pr.additions)").foregroundStyle(.green)
                            Text("-\(item.pr.deletions)").foregroundStyle(.red)
                        }
                        .font(.system(size: 9, design: .monospaced))
                    }
                    Spacer()
                    if !item.pr.head.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.branch")
                                .font(.system(size: 8))
                            Text(item.pr.head)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 100)
                        }
                        .foregroundStyle(.tertiary)
                    }
                    Text(formatDate(displayDate))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: hover ? 0.13 : 0.10))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(stateColor)
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(hover ? Color.purple.opacity(0.55) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var displayDate: String {
        item.pr.updatedAt.isEmpty ? item.pr.createdAt : item.pr.updatedAt
    }

    private var stateColor: Color {
        let s = item.pr.state.uppercased()
        if s == "MERGED" { return .purple }
        if s == "CLOSED" { return .secondary }
        if item.pr.isDraft { return Color.secondary.opacity(0.7) }
        if item.pr.mergeable.uppercased() == "CONFLICTING" { return .red }
        return .green
    }

    private var stateIcon: some View {
        Image(systemName: stateIconName)
            .font(.system(size: 11))
            .foregroundStyle(stateColor)
    }

    private var stateIconName: String {
        let s = item.pr.state.uppercased()
        if s == "MERGED" { return "checkmark.circle.fill" }
        if s == "CLOSED" { return "xmark.circle.fill" }
        if item.pr.isDraft { return "circle.dashed" }
        return "arrow.triangle.pull"
    }

    @ViewBuilder
    private var reviewBadge: some View {
        let rd = item.pr.reviewDecision.uppercased()
        if rd == "APPROVED" {
            badge("Approved", icon: "checkmark.seal.fill", color: .green)
        } else if rd == "CHANGES_REQUESTED" {
            badge("Changes", icon: "exclamationmark.bubble.fill", color: .orange)
        } else if rd == "REVIEW_REQUIRED" {
            badge("Review", icon: "eye.fill", color: .yellow)
        } else if item.pr.mergeable.uppercased() == "CONFLICTING" {
            badge("Conflict", icon: "exclamationmark.triangle.fill", color: .red)
        } else {
            EmptyView()
        }
    }

    private func badge(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 8))
            Text(text).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return "" }
        return UsageTracker.formatRelativeDate(date)
    }
}

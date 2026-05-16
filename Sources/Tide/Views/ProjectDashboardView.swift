import SwiftUI
import AppKit

let DASHBOARD_TAB_ID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

struct RepoSection: Identifiable {
    var id: String { ref.repo }
    let ref: GitHubClient.RepoRef
    var issues: [GitHubClient.Issue] = []
    var prs: [GitHubClient.PR] = []
    var loading: Bool = true
    var error: String?

    var title: String {
        ref.isMain ? ref.repo : "\(ref.label) · \(ref.repo)"
    }
}

struct ProjectDashboardView: View {
    let project: Project
    var showStartCTA: Bool = false
    var onStart: (() -> Void)? = nil
    var onBackToStart: (() -> Void)? = nil

    @State private var sections: [RepoSection] = []
    @State private var activeRepoID: String?
    @State private var globalError: String?
    @State private var loading: Bool = false
    @State private var lastRefresh: Date?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if let err = globalError {
                errorView(err)
            } else if sections.isEmpty {
                noRepoView
            } else {
                if sections.count > 1 {
                    repoPickerBar
                }
                if let section = activeSection {
                    if let err = section.error {
                        errorView(err)
                    } else {
                        HSplitView {
                            IssuesPanel(issues: section.issues, loading: section.loading)
                                .frame(minWidth: 240)
                            PRsPanel(prs: section.prs, loading: section.loading)
                                .frame(minWidth: 240)
                        }
                    }
                }
            }
        }
        .background(SwiftUI.Color.tnBg)
        .onAppear {
            if sections.isEmpty { detectAndLoad() }
        }
    }

    private var activeSection: RepoSection? {
        sections.first(where: { $0.id == activeRepoID }) ?? sections.first
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(project.color).frame(width: 10, height: 10)
            Text(project.name)
                .font(.system(size: 14, weight: .semibold))

            if sections.count == 1, let s = sections.first {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox").font(.system(size: 10))
                    Text(s.ref.repo).font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            } else if sections.count > 1 {
                Text("\(sections.count) repos")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastRefresh {
                Text("updated \(UsageTracker.formatRelativeDate(lastRefresh))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if showStartCTA {
                Button {
                    onBackToStart?()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .controlSize(.small)
                Button {
                    onStart?()
                } label: {
                    Label("Start session", systemImage: "play.fill")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            if let activeSection {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(activeSection.ref.repo)")!)
                } label: {
                    Label("Open repo", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
            }

            Button {
                loadAll()
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
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(SwiftUI.Color.tnBg2)
    }

    private var repoPickerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sections) { section in
                    RepoPickerChip(
                        section: section,
                        isActive: section.id == activeRepoID,
                        onSelect: { activeRepoID = section.id }
                    )
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(SwiftUI.Color.tnBg2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
        }
    }

    private var noRepoView: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Not a GitHub repo")
                .font(.callout).foregroundStyle(.secondary)
            Text("No 'origin' remote at \(project.expandedPath)")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Recheck") { detectAndLoad() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.orange)
            Text("gh error").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                Text(msg)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: 500, alignment: .leading)
            }
            .frame(maxHeight: 160)
            HStack {
                Button("Retry") { loadAll() }
                Button("Install gh") {
                    NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detectAndLoad() {
        globalError = nil
        if !GitHubClient.ghBinaryAvailable() {
            globalError = "`gh` CLI not found in PATH. Install with: brew install gh"
            return
        }
        let refs = GitHubClient.detectAllRepos(at: project.expandedPath)
        if refs.isEmpty {
            sections = []
            return
        }
        sections = refs.map { RepoSection(ref: $0) }
        activeRepoID = sections.first?.id
        loadAll()
    }

    private func loadAll() {
        guard !sections.isEmpty, !loading else { return }
        loading = true
        let repos = sections.map { $0.id }
        Task {
            for repo in repos {
                async let i = GitHubClient.fetchIssues(repo: repo)
                async let p = GitHubClient.fetchPRs(repo: repo)
                let (iRes, pRes) = await (i, p)
                await MainActor.run {
                    guard let idx = sections.firstIndex(where: { $0.id == repo }) else { return }
                    var s = sections[idx]
                    s.loading = false
                    s.error = nil
                    switch iRes {
                    case .success(let v): s.issues = v
                    case .failure(let e): s.error = e.message
                    }
                    switch pRes {
                    case .success(let v): s.prs = v
                    case .failure(let e): if s.error == nil { s.error = e.message }
                    }
                    sections[idx] = s
                }
            }
            await MainActor.run {
                loading = false
                lastRefresh = Date()
            }
        }
    }
}

struct RepoPickerChip: View {
    let section: RepoSection
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: section.ref.isMain ? "house.fill" : "puzzlepiece.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(section.ref.isMain ? Color.accentColor : .orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.ref.isMain ? "main" : section.ref.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(section.ref.repo)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
                let total = section.issues.count + section.prs.count
                if total > 0 {
                    Text("\(total)")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .foregroundStyle(.secondary)
                }
                if section.loading {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct IssuesPanel: View {
    let issues: [GitHubClient.Issue]
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Issues")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(issues.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                Spacer()
                if loading {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(SwiftUI.Color.tnBg2)

            if issues.isEmpty && !loading {
                Spacer()
                Text("No open issues")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(issues) { issue in
                            IssueRow(issue: issue)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(SwiftUI.Color.tnBg)
    }
}

struct IssueRow: View {
    let issue: GitHubClient.Issue
    @State private var hover = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: issue.url)!)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text("#\(issue.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(issue.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 4) {
                    if !issue.author.isEmpty {
                        Text("@\(issue.author)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(issue.labels.prefix(4), id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text(formatDate(issue.createdAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? SwiftUI.Color.tnBg4 : SwiftUI.Color.tnBg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(hover ? Color.accentColor.opacity(0.5) : SwiftUI.Color.tnLine)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return "" }
        return UsageTracker.formatRelativeDate(date)
    }
}

struct PRsPanel: View {
    let prs: [GitHubClient.PR]
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(Color.purple)
                Text("Pull Requests")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(prs.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                Spacer()
                if loading {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(SwiftUI.Color.tnBg2)

            if prs.isEmpty && !loading {
                Spacer()
                Text("No open PRs")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(prs) { pr in
                            PRRow(pr: pr)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(SwiftUI.Color.tnBg)
    }
}

struct PRRow: View {
    let pr: GitHubClient.PR
    @State private var hover = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: pr.url)!)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text("#\(pr.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if pr.isDraft {
                        Text("DRAFT")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.3)))
                            .foregroundStyle(.secondary)
                    }
                    Text(pr.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 4) {
                    if !pr.author.isEmpty {
                        Text("@\(pr.author)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if !pr.head.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.branch")
                                .font(.system(size: 8))
                            Text(pr.head)
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(formatDate(pr.createdAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? SwiftUI.Color.tnBg4 : SwiftUI.Color.tnBg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(hover ? Color.purple.opacity(0.55) : SwiftUI.Color.tnLine)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return "" }
        return UsageTracker.formatRelativeDate(date)
    }
}

import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SnippetsSettingsTab()
                .tabItem { Label("Snippets", systemImage: "bookmark") }
            ShellSettingsTab()
                .tabItem { Label("Shell", systemImage: "terminal") }
            ClaudeSettingsTab()
                .tabItem { Label("Claude", systemImage: "sparkle") }
            AISettingsTab()
                .tabItem { Label("AI Monitor", systemImage: "eye") }
            StorageSettingsTab()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 560)
    }
}

struct AppearanceSettingsTab: View {
    @AppStorage("tide.sidebar.showProjectPath") private var showPath: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sidebar")
                .font(.system(size: 14, weight: .semibold))

            Toggle(isOn: $showPath) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show project path under name")
                    Text("Display the folder path (e.g. ~/Desktop/Projects/...) beneath each project's name in the sidebar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct ShellSettingsTab: View {
    @State private var zshInstalled: Bool = false
    @State private var bashInstalled: Bool = false
    @State private var loggedCount: Int = 0
    @State private var status: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shell Integration")
                .font(.system(size: 14, weight: .semibold))
            Text("Tide can capture every command you run inside a pane and write it to ~/.tide/history/<pane>.log — bypassing zsh's HISTSIZE truncation. Tagged commands (`#tag`) become snippets via the Snippets tab.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            shellRow(
                title: "~/.zshrc",
                installed: zshInstalled,
                rcPath: TideShellIntegration.zshrcPath
            )
            shellRow(
                title: "~/.bashrc",
                installed: bashInstalled,
                rcPath: TideShellIntegration.bashrcPath
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Script written to rc file:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(TideShellIntegration.script)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 140, maxHeight: 180)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Color.accentColor)
                Text("\(loggedCount) commands logged so far")
                    .font(.system(size: 12))
                Spacer()
                Button("Refresh count") { refresh() }
                    .controlSize(.small)
                Button("Clear history", role: .destructive) {
                    TideShellIntegration.clearHistory()
                    refresh()
                }
                .controlSize(.small)
            }

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(20)
        .onAppear { refresh() }
    }

    @ViewBuilder
    private func shellRow(title: String, installed: Bool, rcPath: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: installed ? "checkmark.seal.fill" : "circle.dashed")
                .foregroundStyle(installed ? .green : .orange)
            Text(title)
                .font(.system(.body, design: .monospaced))
            Spacer()
            if installed {
                Button("Remove", role: .destructive) {
                    if TideShellIntegration.uninstall(rc: rcPath) {
                        status = "Removed from \(title). Restart shells to take effect."
                        refresh()
                    }
                }
                .controlSize(.small)
            } else {
                Button("Install") {
                    if TideShellIntegration.install(rc: rcPath) {
                        status = "Installed in \(title). New panes will start capturing immediately."
                        refresh()
                    }
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            Button("Reveal") {
                let url = URL(fileURLWithPath: rcPath)
                if FileManager.default.fileExists(atPath: rcPath) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func refresh() {
        zshInstalled = TideShellIntegration.isInstalled(rc: TideShellIntegration.zshrcPath)
        bashInstalled = TideShellIntegration.isInstalled(rc: TideShellIntegration.bashrcPath)
        loggedCount = TideShellIntegration.totalLoggedCommands()
    }
}

struct SnippetsSettingsTab: View {
    @Environment(SnippetStore.self) private var store
    @Environment(ProjectStore.self) private var projects

    @State private var importMessage: String?
    @State private var importMessageColor: Color = .secondary
    @State private var search: String = ""
    @State private var filterScope: ScopeFilter = .all
    @State private var showAdd = false
    @State private var pendingDelete: Snippet?

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case global = "Global"
        case project = "Project"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Snippets")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(filtered.count) of \(store.snippets.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    importFromHistory()
                } label: {
                    Label("Import from shell history", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Tag commands in your shell history with `# tagname` at the end. Tide imports them as snippets, with `tagname` as the snippet name. Example: `git push origin main # deploy`")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let importMessage {
                Text(importMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(importMessageColor)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(importMessageColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 8) {
                TextField("Search by name or command…", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $filterScope) {
                    ForEach(ScopeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bookmark.slash")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(store.snippets.isEmpty ? "No snippets yet" : "No matches")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(filtered) { snippet in
                            SnippetSettingsRow(
                                snippet: snippet,
                                onDelete: { pendingDelete = snippet }
                            )
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(20)
        .sheet(isPresented: $showAdd) {
            AddSnippetSheet(prefillCommand: "", currentProjectID: projects.selectedID) { s in
                store.add(s)
            }
        }
        .alert(item: $pendingDelete) { snippet in
            Alert(
                title: Text("Delete snippet?"),
                message: Text("\"\(snippet.name)\" will be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    store.remove(id: snippet.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var filtered: [Snippet] {
        let base: [Snippet]
        switch filterScope {
        case .all:     base = store.snippets
        case .global:  base = store.snippets.filter { $0.isGlobal }
        case .project: base = store.snippets.filter { !$0.isGlobal }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? base : base.filter {
            $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q)
        }
        return filtered.sorted { (a, b) in
            if a.name == b.name { return a.command < b.command }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    private func importFromHistory() {
        let bd = HistoryImporter.parseAllWithBreakdown()
        let items = bd.combined.map { (name: $0.tag, command: $0.command) }
        let result = store.bulkImport(items)
        let sourceLine = "Sources scanned: \(bd.zshCount) zsh · \(bd.bashCount) bash · \(bd.tideCount) tide"
        if bd.combined.isEmpty {
            importMessage = "\(sourceLine)\nNo tagged commands found. Tag a command with `# tagname` in your shell."
            importMessageColor = .orange
        } else {
            importMessage = "\(sourceLine)\nImported \(result.added) new · skipped \(result.skipped) duplicates"
            importMessageColor = result.added > 0 ? .green : .orange
        }
    }
}

struct SnippetSettingsRow: View {
    let snippet: Snippet
    let onDelete: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "number")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snippet.name)
                        .font(.system(size: 13, weight: .semibold))
                    if snippet.isGlobal {
                        Text("global")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    } else {
                        Text("project")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.18)))
                    }
                }
                Text(snippet.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if hover {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help("Delete")
            }
        }
        .padding(8)
        .background(hover ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .onHover { hover = $0 }
    }
}

struct ClaudeSettingsTab: View {
    @State private var installed: Bool = false
    @State private var fileContent: String = ""
    @State private var fileExists: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: installed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(installed ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installed ? "Hook installed" : "Hook not installed")
                        .font(.system(size: 14, weight: .semibold))
                    Text(installed
                         ? "Claude Code Stop event will ping Tide via $TIDE_NOTIFY_DIR."
                         : "Install to get notifications when Claude finishes a response.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if installed {
                    Button("Uninstall", role: .destructive) {
                        ClaudeHookInstaller.uninstall()
                        refresh()
                    }
                } else {
                    Button("Install") {
                        ClaudeHookInstaller.install()
                        refresh()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command Tide adds to the Stop hook:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(ClaudeHookInstaller.tideCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("~/.claude/settings.json")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !fileExists {
                        Text("(not created yet)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        ClaudeHookInstaller.revealInFinder()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .controlSize(.small)
                    Button {
                        refresh()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
                ScrollView {
                    Text(fileContent.isEmpty ? "// file is empty or missing\n// Click Install to create it" : fileContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 200, maxHeight: .infinity)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
        .onAppear { refresh() }
    }

    private func refresh() {
        installed = ClaudeHookInstaller.isInstalled()
        let path = "\(NSHomeDirectory())/.claude/settings.json"
        fileExists = FileManager.default.fileExists(atPath: path)
        fileContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}

struct AISettingsTab: View {
    @AppStorage("tide.ai.ollamaURL") private var ollamaURL: String = "http://localhost:11434"
    @AppStorage("tide.ai.defaultModel") private var defaultModel: String = "llama3.2"
    @AppStorage("tide.ai.defaultIntervalSec") private var defaultIntervalSec: Int = 30
    @State private var testStatus: String = ""
    @State private var testing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Monitor defaults")
                .font(.system(size: 14, weight: .semibold))
            Text("These pre-fill the bell-reminder popover when you choose AI Monitor.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Form {
                LabeledContent("Ollama URL") {
                    TextField("http://localhost:11434", text: $ollamaURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Default model") {
                    TextField("llama3.2", text: $defaultModel)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Default interval (s)") {
                    TextField("30", value: $defaultIntervalSec, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button {
                    testConnection()
                } label: {
                    if testing {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                    }
                    Text(testing ? "Testing…" : "Test connection")
                }
                .disabled(testing)
                Text(testStatus)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Spacer()
        }
        .padding(20)
    }

    private func testConnection() {
        testing = true
        testStatus = "Pinging \(ollamaURL)…"
        Task {
            let result = await pingOllama(urlString: ollamaURL)
            await MainActor.run {
                testing = false
                testStatus = result
            }
        }
    }

    private func pingOllama(urlString: String) async -> String {
        guard let url = URL(string: "\(urlString)/api/tags") else { return "Invalid URL" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return "Bad response" }
            if http.statusCode != 200 { return "HTTP \(http.statusCode)" }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = obj["models"] as? [[String: Any]] {
                let names = models.compactMap { $0["name"] as? String }
                if names.isEmpty { return "Connected · no models installed" }
                return "Connected · \(names.count) models"
            }
            return "Connected"
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }
}

struct StorageSettingsTab: View {
    private let entries: [(String, String)] = [
        ("Projects",              "~/Library/Application Support/Tide/projects.json"),
        ("Startup configs",       "~/Library/Application Support/Tide/startups.json"),
        ("Snippets",              "~/Library/Application Support/Tide/snippets.json"),
        ("Usage stats",           "~/Library/Application Support/Tide/usage.json"),
        ("Notification watch",    "~/.tide/notify"),
        ("Claude settings",       "~/.claude/settings.json"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data files")
                .font(.system(size: 14, weight: .semibold))
            Text("Tide stores all state as JSON on disk. Edit at your own risk; back up first.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(entries, id: \.0) { name, path in
                        StorageRow(name: name, path: path)
                    }
                }
            }
            Spacer()
        }
        .padding(20)
    }
}

struct StorageRow: View {
    let name: String
    let path: String

    var body: some View {
        let expanded = (path as NSString).expandingTildeInPath
        let exists = FileManager.default.fileExists(atPath: expanded)
        HStack(spacing: 10) {
            Image(systemName: exists ? "doc.text.fill" : "doc.text")
                .foregroundStyle(exists ? Color.accentColor : Color.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if exists {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
                }
                .controlSize(.small)
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
                }
                .controlSize(.small)
            } else {
                Text("not created")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct AboutSettingsTab: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "water.waves")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Tide")
                .font(.system(size: 28, weight: .semibold))
            Text("v0.1.0")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Native macOS terminal organized around projects.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 8)
            Button {
                NotificationWatcher.requestPermission()
            } label: {
                Label("Request notification permission", systemImage: "bell.badge")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

import SwiftUI
import AppKit

struct SnippetsBar: View {
    @Environment(SnippetStore.self) private var snippetStore
    @Environment(ProjectStore.self) private var projectStore

    @State private var input: String = ""
    @State private var showSnippets = false
    @State private var showAdd = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.tnBlue)

                TextField("Type command, ⏎ to send to active pane · ⌘L to focus", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                    .focused($inputFocused)
                    .onSubmit(sendInput)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color.tnBg3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(inputFocused ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnLine, lineWidth: 1)
            )

            Button {
                showSnippets.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill").font(.system(size: 10))
                    Text("Snippets").font(.system(size: 11, weight: .medium))
                    Text("\(relevantCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                }
            }
            .buttonStyle(TideChipButton())
            .popover(isPresented: $showSnippets, arrowEdge: .bottom) {
                SnippetsPopover(
                    snippets: relevantSnippets,
                    onPick: { snippet in
                        send(text: snippet.command, appendNewline: true)
                        showSnippets = false
                    },
                    onRemove: { snippetStore.remove(id: $0) },
                    onAdd: { showAdd = true; showSnippets = false }
                )
            }

            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(TideChipButton(tint: SwiftUI.Color.tnBlue))
            .help("Add snippet from current input")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SwiftUI.Color.tnBg2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SwiftUI.Color.tnLine)
                .frame(height: 1)
        }
        .sheet(isPresented: $showAdd) {
            AddSnippetSheet(prefillCommand: input, currentProjectID: projectStore.selectedID) { snippet in
                snippetStore.add(snippet)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSnippetsBar)) { _ in
            inputFocused = true
        }
    }

    private var relevantSnippets: [Snippet] {
        snippetStore.relevant(for: projectStore.selectedID)
    }
    private var relevantCount: Int { relevantSnippets.count }

    private func sendInput() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(text: trimmed, appendNewline: true)
        input = ""
    }

    private func send(text: String, appendNewline: Bool) {
        guard let project = projectStore.selected else { return }
        let session = projectStore.session(for: project)
        guard let tab = session.activeTab else { return }
        let leaf = tab.activeLeafID
        guard let terminal = tab.terminals[leaf] else { return }
        terminal.send(txt: text + (appendNewline ? "\n" : ""))
    }
}

struct SnippetsPopover: View {
    let snippets: [Snippet]
    let onPick: (Snippet) -> Void
    let onRemove: (UUID) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Snippets").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Add", action: onAdd)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if snippets.isEmpty {
                Text("No snippets yet.\nAdd one with the + button.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(snippets) { snippet in
                            SnippetRow(snippet: snippet, onPick: { onPick(snippet) }, onRemove: { onRemove(snippet.id) })
                            Divider()
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 300)
            }
        }
        .frame(width: 360)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let onPick: () -> Void
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snippet.name).font(.system(size: 12, weight: .medium))
                    if snippet.isGlobal {
                        Text("global")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    } else {
                        Text("project")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                    }
                }
                Text(snippet.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if hover {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hover ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onPick)
    }
}

struct AddSnippetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let prefillCommand: String
    let currentProjectID: UUID?
    let onSave: (Snippet) -> Void

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var scope: ScopeChoice = .global

    enum ScopeChoice: String, CaseIterable, Identifiable {
        case global, project
        var id: String { rawValue }
    }

    init(prefillCommand: String, currentProjectID: UUID?, onSave: @escaping (Snippet) -> Void) {
        self.prefillCommand = prefillCommand
        self.currentProjectID = currentProjectID
        self.onSave = onSave
        _command = State(initialValue: prefillCommand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Snippet").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.callout).foregroundStyle(.secondary)
                TextField("e.g. rails console", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scope").font(.callout).foregroundStyle(.secondary)
                Picker("", selection: $scope) {
                    Text("Global (all projects)").tag(ScopeChoice.global)
                    Text("Current project only").tag(ScopeChoice.project)
                        .disabled(currentProjectID == nil)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480, height: 340)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let scopeID: UUID? = (scope == .project) ? currentProjectID : nil
        let snippet = Snippet(
            name: name.trimmingCharacters(in: .whitespaces),
            command: command,
            scopeProjectID: scopeID
        )
        onSave(snippet)
        dismiss()
    }
}

extension Notification.Name {
    static let focusSnippetsBar = Notification.Name("Tide.focusSnippetsBar")
    static let triggerFind      = Notification.Name("Tide.triggerFind")
    static let newTab           = Notification.Name("Tide.newTab")
}

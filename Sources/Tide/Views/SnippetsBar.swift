import SwiftUI
import AppKit

struct SnippetsBar: View {
    @Environment(SnippetStore.self) private var snippetStore
    @Environment(ProjectStore.self) private var projectStore

    @State private var input: String = ""
    @State private var showAdd = false
    @State private var hoveredSnippet: UUID?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Row 1 — chip pills for relevant snippets + "Save current"
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(relevantSnippets) { snippet in
                        SnippetChip(
                            snippet: snippet,
                            hover: hoveredSnippet == snippet.id,
                            onPick: { send(text: snippet.command, appendNewline: true) },
                            onRemove: { snippetStore.remove(id: snippet.id) }
                        )
                        .onHover { hoveredSnippet = $0 ? snippet.id : nil }
                    }
                    Button {
                        showAdd = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            Text(input.trimmingCharacters(in: .whitespaces).isEmpty ? "Save snippet" : "Save current")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(TideChipButton(tint: SwiftUI.Color.tnBlue))
                    .help(input.trimmingCharacters(in: .whitespaces).isEmpty
                          ? "Save a new snippet" : "Save current input as a snippet")
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: relevantSnippets.isEmpty && input.isEmpty ? 0 : 28)
            .opacity(relevantSnippets.isEmpty && input.isEmpty ? 0 : 1)

            // Row 2 — input
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
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color.tnBg3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(inputFocused ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnLine, lineWidth: 1)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

struct SnippetChip: View {
    let snippet: Snippet
    let hover: Bool
    let onPick: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(snippet.name.isEmpty ? snippet.command : snippet.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SwiftUI.Color.tnFg2)
                .lineLimit(1)
            if !snippet.isGlobal {
                Circle()
                    .fill(SwiftUI.Color.tnBlue)
                    .frame(width: 5, height: 5)
            }
            if hover {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(hover ? SwiftUI.Color.tnBg4 : SwiftUI.Color.tnBg3)
        )
        .overlay(
            Capsule().strokeBorder(hover ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnLine, lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onPick)
        .help(snippet.command)
    }
}

// Kept for compatibility with older callers; the popover is no longer shown
// from the snippets bar (chips are inline) but the view is still referenced
// from a couple of places.
struct SnippetsPopover: View {
    let snippets: [Snippet]
    let onPick: (Snippet) -> Void
    let onRemove: (UUID) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Snippets")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                Spacer()
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(TideChipButton(tint: SwiftUI.Color.tnBlue))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(SwiftUI.Color.tnBg2)
            Rectangle().fill(SwiftUI.Color.tnLine).frame(height: 1)
            if snippets.isEmpty {
                Text("No snippets yet.\nAdd one with the + button.")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(snippets) { snippet in
                            SnippetRow(snippet: snippet, onPick: { onPick(snippet) }, onRemove: { onRemove(snippet.id) })
                            Rectangle().fill(SwiftUI.Color.tnLine.opacity(0.5)).frame(height: 1)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 300)
            }
        }
        .frame(width: 360)
        .background(SwiftUI.Color.tnBg3)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let onPick: () -> Void
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snippet.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color.tnFg)
                    if snippet.isGlobal {
                        Text("global")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(SwiftUI.Color.tnBg))
                    } else {
                        Text("project")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(SwiftUI.Color.tnBlue)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(SwiftUI.Color.tnBlue.opacity(0.15)))
                    }
                }
                Text(snippet.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if hover {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(SwiftUI.Color.tnRed)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hover ? SwiftUI.Color.tnBg4.opacity(0.6) : SwiftUI.Color.clear)
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
            Text("New snippet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.tnFg)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                TideTextField(placeholder: "e.g. rails console", text: $name)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                TextEditor(text: $command)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SwiftUI.Color.tnBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scope")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                HStack(spacing: 8) {
                    ScopeChip(label: "Global", active: scope == .global) { scope = .global }
                    ScopeChip(
                        label: "Current project",
                        active: scope == .project,
                        disabled: currentProjectID == nil
                    ) { if currentProjectID != nil { scope = .project } }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(TideSecondaryButton())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(TidePrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(22)
        .frame(width: 500, height: 360)
        .background(SwiftUI.Color.tnBg3)
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

struct ScopeChip: View {
    let label: String
    let active: Bool
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(disabled ? SwiftUI.Color.tnFg3.opacity(0.5)
                                 : (active ? SwiftUI.Color.white : SwiftUI.Color.tnFg2))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(active ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnBg3)
                )
                .overlay(
                    Capsule().strokeBorder(active ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnLine, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

extension Notification.Name {
    static let focusSnippetsBar = Notification.Name("Tide.focusSnippetsBar")
    static let triggerFind      = Notification.Name("Tide.triggerFind")
    static let newTab           = Notification.Name("Tide.newTab")
}

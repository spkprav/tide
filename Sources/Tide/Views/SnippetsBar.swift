import SwiftUI
import AppKit
import SwiftTerm

struct SnippetsBar: View {
    @Environment(SnippetStore.self) private var snippetStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(CommandUsageStore.self) private var commandUsage
    @Environment(ServiceSupervisor.self) private var serviceSupervisor

    enum ChipScope: String, CaseIterable, Identifiable {
        case project, global
        var id: String { rawValue }
        var label: String { self == .project ? "Project" : "Global" }
        var icon: String { self == .project ? "folder" : "globe" }
    }

    @AppStorage("Tide.snippetScope") private var scope: ChipScope = .project

    @State private var input: String = ""
    @State private var showAdd = false
    @State private var hoveredSnippet: UUID?
    @State private var hoveredMake: String?
    @State private var copyFlash: String?
    @State private var showServices = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Row 1 — scope switch + chip pills (snippets + make targets) + "Save current"
            HStack(spacing: 8) {
                ScopeSwitch(scope: $scope, projectAvailable: projectStore.selected != nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(orderedChips, id: \.key) { chip in
                            switch chip {
                            case .snippet(let snippet):
                                SnippetChip(
                                    snippet: snippet,
                                    hover: hoveredSnippet == snippet.id,
                                    onPick: { send(text: snippet.command, appendNewline: true) },
                                    onRemove: { snippetStore.remove(id: snippet.id) }
                                )
                                .onHover { hoveredSnippet = $0 ? snippet.id : nil }
                            case .make(let target):
                                MakeTargetChip(
                                    target: target,
                                    hover: hoveredMake == target,
                                    onPick: { send(text: "make \(target)", appendNewline: true) }
                                )
                                .onHover { hoveredMake = $0 ? target : nil }
                            }
                        }
                        if orderedChips.isEmpty {
                            Text(emptyHint)
                                .font(.system(size: 11))
                                .foregroundStyle(SwiftUI.Color.tnFg3)
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
                ServicesBarButton(showing: $showServices)
                if let copied = copyFlash {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Copied")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(SwiftUI.Color.tnGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(SwiftUI.Color.tnGreen.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(SwiftUI.Color.tnGreen.opacity(0.4), lineWidth: 1))
                    .transition(.opacity)
                    .help("Copied: \(copied)")
                }
            }
            .frame(maxHeight: rowVisible ? 28 : 0)
            .opacity(rowVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: copyFlash)

            // Row 2 — input (⏎ send · ⇧⏎ newline)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.tnBlue)
                    .padding(.top, 3)

                TextField("Type command · ⏎ send · ⇧⏎ newline · ⌘L focus",
                          text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                    .focused($inputFocused)
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            return .ignored                      // let TextField insert "\n"
                        }
                        sendInput()
                        return .handled
                    }
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

    private var effectiveScope: ChipScope {
        projectStore.selected == nil ? .global : scope
    }

    private var globalSnippets: [Snippet] {
        snippetStore.snippets.filter { $0.isGlobal }
    }

    private var projectSnippets: [Snippet] {
        guard let pid = projectStore.selectedID else { return [] }
        return snippetStore.snippets.filter { $0.scopeProjectID == pid }
    }

    private var makeTargets: [String] {
        guard let project = projectStore.selected else { return [] }
        return MakeTargets.targets(forProjectPath: project.expandedPath)
    }

    private enum Chip {
        case snippet(Snippet)
        case make(String)

        var key: String {
            switch self {
            case .snippet(let s): return "s:\(s.id.uuidString)"
            case .make(let t):    return "m:\(t)"
            }
        }

        var command: String {
            switch self {
            case .snippet(let s): return s.command
            case .make(let t):    return "make \(t)"
            }
        }
    }

    private var orderedChips: [Chip] {
        let chips: [Chip]
        switch effectiveScope {
        case .global:
            chips = globalSnippets.map(Chip.snippet)
        case .project:
            let snippets = projectSnippets
            // Don't duplicate make chip if user saved the same command as a project snippet.
            let snippetCommands = Set(snippets.map { $0.command.trimmingCharacters(in: .whitespacesAndNewlines) })
            let makeChips = makeTargets
                .filter { !snippetCommands.contains("make \($0)") }
                .map(Chip.make)
            chips = snippets.map(Chip.snippet) + makeChips
        }

        return chips.sorted { lhs, rhs in
            let l = commandUsage.priority(for: lhs.command)
            let r = commandUsage.priority(for: rhs.command)
            if l.count != r.count { return l.count > r.count }
            if l.lastUsed != r.lastUsed { return l.lastUsed > r.lastUsed }
            return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
        }
    }

    private var rowVisible: Bool {
        !orderedChips.isEmpty || !input.isEmpty ||
        !globalSnippets.isEmpty || !projectSnippets.isEmpty || !makeTargets.isEmpty
    }

    private var emptyHint: String {
        switch effectiveScope {
        case .global:  return "No global snippets yet."
        case .project: return projectStore.selected == nil
            ? "No project selected."
            : "No project snippets or make targets."
        }
    }

    private func sendInput() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(text: trimmed, appendNewline: true)
        input = ""
    }

    private func send(text: String, appendNewline: Bool) {
        if let terminal = activeTerminal() {
            terminal.send(txt: text + (appendNewline ? "\n" : ""))
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            copyFlash = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copyFlash == text { copyFlash = nil }
            }
        }
        commandUsage.record(text)
    }

    private func activeTerminal() -> LocalProcessTerminalView? {
        guard let project = projectStore.selected else { return nil }
        let session = projectStore.session(for: project)
        guard let tab = session.activeTab else { return nil }
        return tab.terminals[tab.activeLeafID]
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

struct ServicesBarButton: View {
    @Environment(ServiceSupervisor.self) private var supervisor
    @Binding var showing: Bool

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: supervisor.runningCount > 0 ? .semibold : .regular))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(SwiftUI.Color.tnBg3))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(supervisor.runningCount > 0 ? "Services (\(supervisor.runningCount) running)" : "Services")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ServicesPopover()
        }
    }

    private var label: String {
        supervisor.runningCount > 0 ? "Services · \(supervisor.runningCount)" : "Services"
    }
    private var tint: SwiftUI.Color {
        supervisor.runningCount > 0 ? SwiftUI.Color.tnGreen : SwiftUI.Color.tnFg2
    }
    private var border: SwiftUI.Color {
        supervisor.runningCount > 0 ? SwiftUI.Color.tnGreen.opacity(0.5) : SwiftUI.Color.tnLine
    }
}

struct ScopeSwitch: View {
    @Binding var scope: SnippetsBar.ChipScope
    let projectAvailable: Bool

    var body: some View {
        HStack(spacing: 0) {
            seg(.project)
            seg(.global)
        }
        .padding(2)
        .background(Capsule().fill(SwiftUI.Color.tnBg))
        .overlay(Capsule().strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1))
    }

    @ViewBuilder
    private func seg(_ value: SnippetsBar.ChipScope) -> some View {
        let active = scope == value
        let disabled = value == .project && !projectAvailable
        Button {
            guard !disabled else { return }
            scope = value
        } label: {
            HStack(spacing: 4) {
                Image(systemName: value.icon).font(.system(size: 9, weight: .semibold))
                Text(value.label).font(.system(size: 10, weight: active ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(
                disabled ? SwiftUI.Color.tnFg3.opacity(0.5) :
                (active ? SwiftUI.Color.white : SwiftUI.Color.tnFg2)
            )
            .background(Capsule().fill(active ? SwiftUI.Color.tnBlue : SwiftUI.Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(value == .project ? "Show project snippets and make targets"
                                : "Show global snippets")
    }
}

struct MakeTargetChip: View {
    let target: String
    let hover: Bool
    let onPick: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text("make")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SwiftUI.Color.tnOrange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(SwiftUI.Color.tnOrange.opacity(0.15)))
            Text(target)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(SwiftUI.Color.tnFg2)
                .lineLimit(1)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(hover ? SwiftUI.Color.tnBg4 : SwiftUI.Color.tnBg3)
        )
        .overlay(
            Capsule().strokeBorder(hover ? SwiftUI.Color.tnOrange : SwiftUI.Color.tnLine, lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onPick)
        .help("make \(target)")
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

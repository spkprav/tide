import SwiftUI
import AppKit

struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editing: Project?
    let onSave: (Project) -> Void

    @State private var name: String = ""
    @State private var path: String = ""
    @State private var colorHex: String = "#7AA2F7"

    private let presetColors: [String] = [
        "#7AA2F7", "#9ECE6A", "#F7768E", "#E0AF68",
        "#BB9AF7", "#7DCFFF", "#FF9E64", "#73DACA",
    ]

    init(editing: Project? = nil, onSave: @escaping (Project) -> Void) {
        self.editing = editing
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        _path = State(initialValue: editing?.path ?? "")
        _colorHex = State(initialValue: editing?.colorHex ?? "#7AA2F7")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "Add Project" : "Edit Project")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.callout).foregroundStyle(.secondary)
                TextField("e.g. reefstore", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Folder").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("/path/to/project", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Choose…") { pickFolder() }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(presetColors, id: \.self) { hex in
                        ColorSwatch(hex: hex, selected: hex == colorHex)
                            .onTapGesture { colorHex = hex }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 460, height: 320)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = path.trimmingCharacters(in: .whitespaces)
        if var p = editing {
            p.name = trimmedName
            p.path = trimmedPath
            p.colorHex = colorHex
            onSave(p)
        } else {
            onSave(Project(name: trimmedName, path: trimmedPath, colorHex: colorHex))
        }
        dismiss()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty { name = url.lastPathComponent }
        }
    }
}

struct ColorSwatch: View {
    let hex: String
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 22, height: 22)
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(selected ? 0.9 : 0.1), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Circle())
    }
}

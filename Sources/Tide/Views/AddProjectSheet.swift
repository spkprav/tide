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
            Text(editing == nil ? "New project" : "Edit project")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.tnFg)

            sheetField(label: "Name") {
                TideTextField(placeholder: "e.g. acme-web", text: $name)
            }

            sheetField(label: "Working directory") {
                HStack(spacing: 8) {
                    TideTextField(placeholder: "/path/to/project", text: $path, mono: true)
                    Button("Choose…") { pickFolder() }
                        .buttonStyle(TideSecondaryButton())
                }
            }

            sheetField(label: "Color tag") {
                HStack(spacing: 10) {
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
                    .buttonStyle(TideSecondaryButton())
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add" : "Save") { save() }
                    .buttonStyle(TidePrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(22)
        .frame(width: 480, height: 340)
        .background(SwiftUI.Color.tnBg3)
    }

    @ViewBuilder
    private func sheetField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SwiftUI.Color.tnFg3)
            content()
        }
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
            .fill(SwiftUI.Color(hex: hex) ?? .gray)
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .strokeBorder(SwiftUI.Color.white.opacity(selected ? 1 : 0), lineWidth: 2)
                    .padding(2)
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        selected ? SwiftUI.Color(hex: hex) ?? .gray : SwiftUI.Color.tnLine,
                        lineWidth: selected ? 2 : 1
                    )
            )
            .contentShape(Circle())
    }
}

// Reusable styled text field matching mockup inputs.
struct TideTextField: View {
    let placeholder: String
    @Binding var text: String
    var mono: Bool = false

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
            .foregroundStyle(SwiftUI.Color.tnFg)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color.tnBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(focused ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnLine, lineWidth: 1)
            )
            .focused($focused)
    }
}

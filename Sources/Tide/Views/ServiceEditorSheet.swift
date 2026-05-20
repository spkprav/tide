import SwiftUI
import AppKit

struct ServiceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editing: Service?
    let onSave: (Service) -> Void

    @State private var name: String
    @State private var startCommand: String
    @State private var downCommand: String
    @State private var cwd: String
    @State private var autoStart: Bool
    @State private var declaredPortText: String

    init(editing: Service?, defaultCwd: String, onSave: @escaping (Service) -> Void) {
        self.editing = editing
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        _startCommand = State(initialValue: editing?.startCommand ?? "")
        _downCommand = State(initialValue: editing?.downCommand ?? "")
        _cwd = State(initialValue: editing?.cwd ?? defaultCwd)
        _autoStart = State(initialValue: editing?.autoStart ?? false)
        if let port = editing?.declaredPort {
            _declaredPortText = State(initialValue: String(port))
        } else {
            _declaredPortText = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "New service" : "Edit service")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.tnFg)

            field(label: "Name") {
                TideTextField(placeholder: "e.g. web", text: $name)
            }

            field(label: "Start command") {
                multiLine(text: $startCommand, placeholder: "e.g. pnpm dev")
            }

            field(label: "Down command (optional — runs after stop or kill)") {
                multiLine(text: $downCommand, placeholder: "e.g. pnpm clean")
            }

            field(label: "Working directory") {
                HStack(spacing: 8) {
                    TideTextField(placeholder: "/path/to/dir", text: $cwd, mono: true)
                    Button("Choose…") { pickFolder() }
                        .buttonStyle(TideSecondaryButton())
                }
            }

            HStack(spacing: 18) {
                Toggle(isOn: $autoStart) {
                    Text("Auto-start on launch")
                        .font(.system(size: 11))
                        .foregroundStyle(SwiftUI.Color.tnFg2)
                }
                .toggleStyle(.checkbox)

                field(label: "Hint port") {
                    TideTextField(placeholder: "optional", text: $declaredPortText, mono: true)
                        .frame(width: 90)
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
        .frame(width: 540, height: 520)
        .background(SwiftUI.Color.tnBg3)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SwiftUI.Color.tnFg3)
            content()
        }
    }

    @ViewBuilder
    private func multiLine(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.tnFg3.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SwiftUI.Color.tnFg)
                .frame(minHeight: 54, maxHeight: 84)
                .padding(6)
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SwiftUI.Color.tnBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
        )
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !startCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cwd.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmedDown = downCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(declaredPortText.trimmingCharacters(in: .whitespaces))
        let svc = Service(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            downCommand: trimmedDown.isEmpty ? nil : trimmedDown,
            cwd: cwd.trimmingCharacters(in: .whitespaces),
            env: editing?.env ?? [:],
            autoStart: autoStart,
            declaredPort: port
        )
        onSave(svc)
        dismiss()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let start = (cwd as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: start) {
            panel.directoryURL = URL(fileURLWithPath: start)
        } else {
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }
        if panel.runModal() == .OK, let url = panel.url {
            cwd = url.path
        }
    }
}

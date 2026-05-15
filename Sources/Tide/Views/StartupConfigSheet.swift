import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StartupConfigSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let onSave: (StartupConfig) -> Void

    @State private var config: StartupConfig

    init(project: Project, existing: StartupConfig?, onSave: @escaping (StartupConfig) -> Void) {
        self.project = project
        self.onSave = onSave
        _config = State(initialValue: existing ?? StartupConfig(name: "default", layout: .grid2x2, panes: []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Setup for \(project.name)").font(.title2.weight(.semibold))
                Spacer()
                Menu {
                    Button("Export Setup…", action: exportConfig)
                    Button("Import Setup…", action: importConfig)
                } label: {
                    Image(systemName: "arrow.up.arrow.down.square")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.callout).foregroundStyle(.secondary)
                    TextField("default", text: $config.name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layout").font(.callout).foregroundStyle(.secondary)
                    Picker("", selection: $config.layout) {
                        ForEach(StartupLayout.allCases) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: config.layout) { _, _ in
                        config.ensurePaneCount()
                    }
                }
            }

            LayoutVisualizer(layout: config.layout, panes: config.panes)
                .frame(height: 100)

            Text("Commands").font(.callout).foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(config.panes.enumerated()), id: \.offset) { idx, _ in
                        PaneEditor(
                            position: config.layout.positionLabel(for: idx),
                            pane: $config.panes[idx]
                        )
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 320)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580, height: 660)
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(project.name)-\(config.name).tide.json"
        if panel.runModal() == .OK, let url = panel.url {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(config) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            if let imported = try? JSONDecoder().decode(StartupConfig.self, from: data) {
                var c = imported
                c.ensurePaneCount()
                config = c
            }
        }
    }
}

struct PaneEditor: View {
    let position: String
    @Binding var pane: StartupPane

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(position)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                TextField("pane name (e.g. server)", text: $pane.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            TextField("command (e.g. bundle exec rails s)", text: $pane.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

struct LayoutVisualizer: View {
    let layout: StartupLayout
    let panes: [StartupPane]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3))
                content(in: geo.size)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch layout {
        case .singlePane:
            paneBox(label: paneLabel(0))
                .frame(width: size.width, height: size.height)
        case .grid2x2:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    paneBox(label: paneLabel(0))
                    paneBox(label: paneLabel(1))
                }
                HStack(spacing: 2) {
                    paneBox(label: paneLabel(2))
                    paneBox(label: paneLabel(3))
                }
            }
            .padding(4)
        case .bigTopThreeBottom:
            VStack(spacing: 2) {
                paneBox(label: paneLabel(0))
                    .frame(maxHeight: .infinity)
                HStack(spacing: 2) {
                    paneBox(label: paneLabel(1))
                    paneBox(label: paneLabel(2))
                    paneBox(label: paneLabel(3))
                }
                .frame(maxHeight: .infinity)
            }
            .padding(4)
        case .leftMainRightStacked:
            HStack(spacing: 2) {
                paneBox(label: paneLabel(0))
                    .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    paneBox(label: paneLabel(1))
                    paneBox(label: paneLabel(2))
                    paneBox(label: paneLabel(3))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(4)
        case .rowsStacked:
            VStack(spacing: 2) {
                paneBox(label: paneLabel(0))
                paneBox(label: paneLabel(1))
                paneBox(label: paneLabel(2))
                paneBox(label: paneLabel(3))
            }
            .padding(4)
        }
    }

    private func paneLabel(_ idx: Int) -> String {
        if idx < panes.count, !panes[idx].name.isEmpty { return panes[idx].name }
        return layout.positionLabel(for: idx)
    }

    private func paneBox(label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.12))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

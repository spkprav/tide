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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Startup configuration")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color.tnFg)
                    Text(project.name)
                        .font(.system(size: 11))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                }
                Spacer()
                Button(action: exportConfig) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(TideChipButton())
                Button(action: importConfig) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(TideChipButton())
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 11))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                    TideTextField(placeholder: "default", text: $config.name)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Layout")
                        .font(.system(size: 11))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                    LayoutPicker(layout: $config.layout)
                        .onChange(of: config.layout) { _, _ in
                            config.ensurePaneCount()
                        }
                }
            }

            LayoutVisualizer(layout: config.layout, panes: config.panes)
                .frame(height: 100)

            HStack {
                Text("Pane commands")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                Text("\(config.panes.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(SwiftUI.Color.tnBg))
                Spacer()
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(config.panes.enumerated()), id: \.offset) { idx, _ in
                        PaneEditor(
                            position: config.layout.positionLabel(for: idx),
                            accent: paneAccent(idx),
                            pane: $config.panes[idx]
                        )
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 320)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(TideSecondaryButton())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(config)
                    dismiss()
                }
                .buttonStyle(TidePrimaryButton())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620, height: 700)
        .background(SwiftUI.Color.tnBg3)
    }

    private func paneAccent(_ i: Int) -> SwiftUI.Color {
        let palette: [SwiftUI.Color] = [.tnBlue, .tnGreen, .tnPurple, .tnOrange, .tnCyan, .tnYellow]
        return palette[i % palette.count]
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

struct LayoutPicker: View {
    @Binding var layout: StartupLayout

    var body: some View {
        Menu {
            ForEach(StartupLayout.allCases) { l in
                Button(l.displayName) { layout = l }
            }
        } label: {
            HStack(spacing: 6) {
                Text(layout.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color.tnBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

struct PaneEditor: View {
    let position: String
    let accent: SwiftUI.Color
    @Binding var pane: StartupPane

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(position)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.tnBg)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(accent))
                TideTextField(placeholder: "pane name (e.g. server)", text: $pane.name)
            }
            TideTextField(placeholder: "command (e.g. bundle exec rails s)", text: $pane.command, mono: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SwiftUI.Color.tnBg.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
        )
    }
}

struct LayoutVisualizer: View {
    let layout: StartupLayout
    let panes: [StartupPane]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color.tnBg)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
                content(in: geo.size)
                    .padding(6)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch layout {
        case .singlePane:
            paneBox(0)
        case .grid2x2:
            VStack(spacing: 3) {
                HStack(spacing: 3) { paneBox(0); paneBox(1) }
                HStack(spacing: 3) { paneBox(2); paneBox(3) }
            }
        case .bigTopThreeBottom:
            VStack(spacing: 3) {
                paneBox(0).frame(maxHeight: .infinity)
                HStack(spacing: 3) { paneBox(1); paneBox(2); paneBox(3) }
                    .frame(maxHeight: .infinity)
            }
        case .leftMainRightStacked:
            HStack(spacing: 3) {
                paneBox(0).frame(maxWidth: .infinity)
                VStack(spacing: 3) { paneBox(1); paneBox(2); paneBox(3) }
                    .frame(maxWidth: .infinity)
            }
        case .rowsStacked:
            VStack(spacing: 3) {
                paneBox(0); paneBox(1); paneBox(2); paneBox(3)
            }
        }
    }

    private func paneLabel(_ idx: Int) -> String {
        if idx < panes.count, !panes[idx].name.isEmpty { return panes[idx].name }
        return layout.positionLabel(for: idx)
    }

    private func accent(_ idx: Int) -> SwiftUI.Color {
        let palette: [SwiftUI.Color] = [.tnBlue, .tnGreen, .tnPurple, .tnOrange, .tnCyan, .tnYellow]
        return palette[idx % palette.count]
    }

    private func paneBox(_ idx: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(accent(idx).opacity(0.18))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(accent(idx).opacity(0.4), lineWidth: 1)
            Text(paneLabel(idx))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.tnFg)
                .lineLimit(1)
        }
    }
}

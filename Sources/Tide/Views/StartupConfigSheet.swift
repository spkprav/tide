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
            // Title
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Startup configuration · \(project.name)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SwiftUI.Color.tnFg)
                    Text(displayPath(project.expandedPath))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                }
                Spacer()
            }

            // Config name
            VStack(alignment: .leading, spacing: 6) {
                Text("Configuration name")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                TideTextField(placeholder: "default", text: $config.name)
            }

            // Layout — horizontal cards
            VStack(alignment: .leading, spacing: 8) {
                Text("Layout")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                HStack(spacing: 10) {
                    ForEach(StartupLayout.allCases) { layout in
                        LayoutCard(
                            layout: layout,
                            active: layout == config.layout
                        ) {
                            config.layout = layout
                            config.ensurePaneCount()
                        }
                    }
                }
            }

            // Pane commands — 2-col grid
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
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
                    paneGrid
                }
                .frame(minHeight: 220, maxHeight: 340)
            }

            Spacer(minLength: 0)

            // Actions
            HStack {
                Button(action: exportConfig) {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(TideChipButton())

                Button(action: importConfig) {
                    Label("Import…", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(TideChipButton())

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
        .frame(width: 780, height: 700)
        .background(SwiftUI.Color.tnBg3)
    }

    @ViewBuilder
    private var paneGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(config.panes.enumerated()), id: \.offset) { idx, _ in
                PaneEditor(
                    index: idx,
                    position: config.layout.positionLabel(for: idx),
                    accent: Self.paneAccent(idx),
                    pane: $config.panes[idx]
                )
            }
        }
    }

    static func paneAccent(_ i: Int) -> SwiftUI.Color {
        let palette: [SwiftUI.Color] = [.tnBlue, .tnGreen, .tnPurple, .tnOrange, .tnCyan, .tnYellow]
        return palette[i % palette.count]
    }

    private func displayPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
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

struct LayoutCard: View {
    let layout: StartupLayout
    let active: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                LayoutPreview(layout: layout)
                    .frame(height: 60)
                Text(shortName(layout))
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? SwiftUI.Color.tnFg : SwiftUI.Color.tnFg2)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SwiftUI.Color.tnBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnLine, lineWidth: active ? 2 : 1)
            )
            .shadow(color: active ? SwiftUI.Color.tnBlue.opacity(0.3) : .clear, radius: active ? 8 : 0)
        }
        .buttonStyle(.plain)
    }

    private func shortName(_ l: StartupLayout) -> String {
        switch l {
        case .singlePane:            return "Single"
        case .grid2x2:               return "2 × 2 grid"
        case .bigTopThreeBottom:     return "Top + 3"
        case .leftMainRightStacked:  return "Left + stack"
        case .rowsStacked:           return "Rows"
        }
    }
}

struct LayoutPreview: View {
    let layout: StartupLayout

    var body: some View {
        GeometryReader { _ in
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SwiftUI.Color.tnBg2)
                content
                    .padding(4)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .singlePane:
            cell(0)
        case .grid2x2:
            VStack(spacing: 2) {
                HStack(spacing: 2) { cell(0); cell(1) }
                HStack(spacing: 2) { cell(2); cell(3) }
            }
        case .bigTopThreeBottom:
            VStack(spacing: 2) {
                cell(0).frame(maxHeight: .infinity)
                HStack(spacing: 2) { cell(1); cell(2); cell(3) }
                    .frame(maxHeight: .infinity)
            }
        case .leftMainRightStacked:
            HStack(spacing: 2) {
                cell(0).frame(maxWidth: .infinity)
                VStack(spacing: 2) { cell(1); cell(2); cell(3) }
                    .frame(maxWidth: .infinity)
            }
        case .rowsStacked:
            VStack(spacing: 2) { cell(0); cell(1); cell(2); cell(3) }
        }
    }

    private func cell(_ idx: Int) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(StartupConfigSheet.paneAccent(idx).opacity(0.35))
    }
}

struct PaneEditor: View {
    let index: Int
    let position: String
    let accent: SwiftUI.Color
    @Binding var pane: StartupPane

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Colored header label like mockup: "Pane 1 — server"
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text("Pane \(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                if !pane.name.isEmpty {
                    Text("— \(pane.name)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text(position)
                    .font(.system(size: 9))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
            }

            TideTextField(placeholder: "name (e.g. server, tests, logs)", text: $pane.name)

            CommandEditor(text: $pane.command)
                .frame(height: 56)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SwiftUI.Color.tnBg.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
    }
}

struct CommandEditor: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(SwiftUI.Color.tnFg)
            .padding(8)
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

import SwiftUI

struct StartScreen: View {
    @Environment(StartupStore.self) private var startupStore
    @Environment(UsageTracker.self) private var tracker
    let project: Project
    let session: ProjectSession
    @State private var showConfigure = false

    private var config: StartupConfig? {
        startupStore.primaryConfig(for: project.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Gradient icon badge — project initial.
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [project.color, SwiftUI.Color.tnPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: project.color.opacity(0.4), radius: 16, y: 4)
                    Text(project.name.prefix(1).uppercased())
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(project.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg)

                statusLine

                if let cfg = config {
                    HStack(spacing: 10) {
                        Button {
                            showConfigure = true
                        } label: {
                            Text("Configure")
                        }
                        .buttonStyle(TideSecondaryButton())

                        Button {
                            session.start(with: cfg)
                            tracker.recordSessionStart(projectID: project.id)
                        } label: {
                            HStack(spacing: 6) {
                                Text("Start")
                                Image(systemName: "return")
                                    .font(.system(size: 10))
                                    .foregroundStyle(SwiftUI.Color.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(TidePrimaryButton())
                        .keyboardShortcut(.return, modifiers: [])
                    }
                    .padding(.top, 4)

                    Button {
                        session.activeTabID = DASHBOARD_TAB_ID
                    } label: {
                        Label("View Dashboard", systemImage: "chart.bar.doc.horizontal")
                            .font(.system(size: 12))
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                    }
                    .buttonStyle(.borderless)

                    ConfigPreview(config: cfg).padding(.top, 6)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            session.start(with: nil)
                            tracker.recordSessionStart(projectID: project.id)
                        } label: {
                            Text("Open plain shell")
                        }
                        .buttonStyle(TideSecondaryButton())

                        Button {
                            showConfigure = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 11))
                                Text("Configure setup")
                            }
                        }
                        .buttonStyle(TidePrimaryButton())
                        .keyboardShortcut(.return, modifiers: [])
                    }
                    .padding(.top, 4)

                    Button {
                        session.activeTabID = DASHBOARD_TAB_ID
                    } label: {
                        Label("View Dashboard", systemImage: "chart.bar.doc.horizontal")
                            .font(.system(size: 12))
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SwiftUI.Color.tnBg)
        .sheet(isPresented: $showConfigure) {
            StartupConfigSheet(project: project, existing: config) { newConfig in
                startupStore.upsert(newConfig, for: project.id)
            }
        }
    }

    private var statusLine: some View {
        let pathText = displayPath(project.expandedPath)
        let paneText = config.map { "\($0.panes.count)-pane startup configured" } ?? "no setup configured"
        return Text("\(pathText) · \(paneText)")
            .font(.system(size: 13))
            .foregroundStyle(SwiftUI.Color.tnFg3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
    }

    private func displayPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
    }
}

struct ConfigPreview: View {
    let config: StartupConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(config.layout.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(SwiftUI.Color.tnBg3))
                    .overlay(Capsule().strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1))
                Text("\(config.panes.count) panes")
                    .font(.system(size: 11))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(config.panes.enumerated()), id: \.offset) { idx, pane in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(paneAccent(idx))
                        Text(pane.name.isEmpty ? config.layout.positionLabel(for: idx) : pane.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SwiftUI.Color.tnFg)
                        Text("·")
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                        Text(pane.command.isEmpty ? "(no command)" : pane.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(SwiftUI.Color.tnFg3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SwiftUI.Color.tnBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
        )
        .frame(maxWidth: 460)
    }

    private func paneAccent(_ i: Int) -> SwiftUI.Color {
        let palette: [SwiftUI.Color] = [.tnBlue, .tnGreen, .tnPurple, .tnOrange, .tnCyan, .tnYellow]
        return palette[i % palette.count]
    }
}

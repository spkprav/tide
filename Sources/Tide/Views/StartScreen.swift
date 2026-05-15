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

            VStack(spacing: 24) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(project.color)
                        .frame(width: 14, height: 14)
                    Text(project.name)
                        .font(.system(size: 24, weight: .semibold))
                }

                Text(project.expandedPath)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let cfg = config {
                    ConfigPreview(config: cfg)
                        .padding(.top, 8)

                    Button {
                        session.start(with: cfg)
                        tracker.recordSessionStart(projectID: project.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 13))
                            Text("Start").font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(project.color))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        showConfigure = true
                    } label: {
                        Label("Edit Setup…", systemImage: "slider.horizontal.3").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                    Button {
                        session.activeTabID = DASHBOARD_TAB_ID
                    } label: {
                        Label("View Dashboard", systemImage: "chart.bar.doc.horizontal")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    Text("No setup configured for this project")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    Button {
                        showConfigure = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                            Text("Configure Setup").font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(project.color))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        session.start(with: nil)
                        tracker.recordSessionStart(projectID: project.id)
                    } label: {
                        Text("Skip — open plain shell").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                    Button {
                        session.activeTabID = DASHBOARD_TAB_ID
                    } label: {
                        Label("View Dashboard", systemImage: "chart.bar.doc.horizontal")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .sheet(isPresented: $showConfigure) {
            StartupConfigSheet(project: project, existing: config) { newConfig in
                startupStore.upsert(newConfig, for: project.id)
            }
        }
    }
}

struct ConfigPreview: View {
    let config: StartupConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(config.layout.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Text("\(config.panes.count) panes")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(config.panes.enumerated()), id: \.offset) { idx, pane in
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                        Text(pane.name.isEmpty ? config.layout.positionLabel(for: idx) : pane.name)
                            .font(.system(size: 11, weight: .medium))
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(pane.command.isEmpty ? "(no command)" : pane.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: 460)
    }
}

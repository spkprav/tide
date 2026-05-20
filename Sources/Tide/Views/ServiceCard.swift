import SwiftUI

struct ServiceCard: View {
    let service: Service
    let runner: ServiceRunner
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(status: runner.status)
                Text(service.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                    .lineLimit(1)
                Spacer()
                if let port = displayPort {
                    Text(":\(port)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SwiftUI.Color.tnCyan)
                }
            }

            HStack(spacing: 8) {
                Text(service.startCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if runner.pid > 0 {
                    Text("pid \(runner.pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                }
            }

            statusLine

            HStack(spacing: 6) {
                ActionIcon(symbol: "play.fill", tint: .tnGreen, help: "Start", enabled: canStart) { runner.start() }
                ActionIcon(symbol: "stop.fill", tint: .tnYellow, help: "Stop", enabled: canStop) { runner.stop() }
                ActionIcon(symbol: "xmark.octagon.fill", tint: .tnRed, help: "Kill", enabled: canKill) { runner.kill() }
                ActionIcon(symbol: "arrow.clockwise", tint: .tnBlue, help: "Restart", enabled: canRestart) { runner.restart() }
                Spacer()
                ActionIcon(symbol: "pencil", tint: .tnFg2, help: "Edit", enabled: runner.status.isTerminal, action: onEdit)
                ActionIcon(symbol: "trash", tint: .tnRed, help: "Delete service", enabled: runner.status.isTerminal, action: onDelete)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SwiftUI.Color.tnBg3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .onHover { hover = $0 }
    }

    private var displayPort: Int? {
        runner.detectedPort ?? service.declaredPort
    }

    @ViewBuilder private var statusLine: some View {
        HStack(spacing: 6) {
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
            if case .failed(let msg) = runner.status {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(SwiftUI.Color.tnFg3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var statusText: String {
        switch runner.status {
        case .stopped: return "stopped"
        case .starting: return "starting…"
        case .running: return "running"
        case .stopping: return "stopping…"
        case .down: return "running down command…"
        case .exited(let code):
            if code < 0 { return "exited (signal \(-code))" }
            return "exited (\(code))"
        case .failed: return "failed"
        }
    }

    private var statusColor: SwiftUI.Color {
        switch runner.status {
        case .running: return .tnGreen
        case .starting, .stopping, .down: return .tnYellow
        case .failed: return .tnRed
        case .exited: return .tnFg3
        case .stopped: return .tnFg3
        }
    }

    private var borderColor: SwiftUI.Color {
        if hover { return SwiftUI.Color.tnBlue.opacity(0.4) }
        switch runner.status {
        case .running: return SwiftUI.Color.tnGreen.opacity(0.3)
        case .failed: return SwiftUI.Color.tnRed.opacity(0.4)
        default: return SwiftUI.Color.tnLine
        }
    }

    private var canStart: Bool {
        switch runner.status {
        case .stopped, .exited, .failed: return true
        default: return false
        }
    }
    private var canStop: Bool {
        runner.status == .running
    }
    private var canKill: Bool {
        switch runner.status {
        case .running, .starting, .stopping, .down: return true
        default: return false
        }
    }
    private var canRestart: Bool {
        switch runner.status {
        case .running, .stopped, .exited, .failed: return true
        default: return false
        }
    }
}

private struct StatusDot: View {
    let status: ServiceStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().fill(color.opacity(0.25)).frame(width: 16, height: 16)
                    .opacity(pulse ? 1 : 0)
            )
    }

    private var color: SwiftUI.Color {
        switch status {
        case .running: return .tnGreen
        case .starting, .stopping, .down: return .tnYellow
        case .failed: return .tnRed
        case .exited: return .tnFg3
        case .stopped: return .tnFg3.opacity(0.6)
        }
    }

    private var pulse: Bool {
        switch status {
        case .running, .starting, .stopping, .down: return true
        default: return false
        }
    }
}

private struct ActionIcon: View {
    let symbol: String
    let tint: SwiftUI.Color
    let help: String
    let enabled: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? tint : SwiftUI.Color.tnFg3.opacity(0.4))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hover && enabled ? tint.opacity(0.15) : SwiftUI.Color.tnBg2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(enabled ? tint.opacity(hover ? 0.55 : 0.25) : SwiftUI.Color.tnLine.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hover = $0 }
    }
}

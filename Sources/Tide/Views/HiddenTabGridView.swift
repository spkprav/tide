import SwiftUI
import AppKit
import SwiftTerm

struct HiddenTabGridView: View {
    @Bindable var session: ProjectSession

    var body: some View {
        let cols = columnCount(session.hiddenPanes.count)
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols),
                spacing: 4
            ) {
                ForEach(session.hiddenPanes) { hp in
                    HiddenPaneCell(hidden: hp, session: session)
                        .frame(minHeight: 180)
                }
            }
            .padding(8)
        }
        .background(SwiftUI.Color.tnBg)
    }

    private func columnCount(_ n: Int) -> Int {
        switch n {
        case ...1:   return 1
        case 2:      return 2
        case 3...4:  return 2
        case 5...6:  return 3
        case 7...9:  return 3
        case 10...12: return 4
        default:     return 4
        }
    }
}

struct HiddenPaneCell: View {
    let hidden: HiddenPane
    let session: ProjectSession

    @State private var hover = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(hidden.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    session.restoreHidden(hidden.id)
                } label: {
                    Image(systemName: "eye").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Restore pane")
                Button {
                    session.killHidden(hidden.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Kill")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SwiftUI.Color.tnBg2)

            HiddenTerminalRepresentable(sessionID: hidden.id, session: session)
                .background(SwiftUI.Color.tnBg)
        }
        .background(SwiftUI.Color.tnBg)
        .overlay(
            Rectangle().stroke(hover ? Color.accentColor.opacity(0.6) : SwiftUI.Color.tnLine, lineWidth: 1)
        )
        .onHover { hover = $0 }
    }
}

struct HiddenTerminalRepresentable: NSViewRepresentable {
    let sessionID: UUID
    let session: ProjectSession

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        attachTerminal(to: host)
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attachTerminal(to: nsView)
    }

    private func attachTerminal(to host: NSView) {
        guard let terminal = session.hiddenTerminals[sessionID] else { return }
        if terminal.superview === host { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = [.width, .height]
        terminal.frame = host.bounds
        host.addSubview(terminal)
        DispatchQueue.main.async {
            let size = host.bounds.size
            if size.width > 0 && size.height > 0 {
                terminal.setFrameSize(size)
            }
            terminal.getTerminal().updateFullScreen()
            terminal.needsDisplay = true
            terminal.displayIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                terminal.getTerminal().updateFullScreen()
                terminal.needsDisplay = true
                terminal.displayIfNeeded()
            }
        }
    }
}

import AppKit
import SwiftTerm

/// Bridges macOS scroll-wheel events into SGR mouse-report bytes on the pty
/// when the running app has mouse reporting enabled. Lets tmux's
/// `bind -n WheelUpPane` / `WheelDownPane` engage and lets mouse-aware apps
/// (vim/htop) handle their own scrolling. When no app wants mouse events,
/// the wheel falls through to SwiftTerm's local viewport scrolling.
@MainActor
enum TerminalScrollForwarder {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            var pass = true
            MainActor.assumeIsolated {
                guard event.deltaY != 0,
                      let win = event.window,
                      let hit = win.contentView?.hitTest(event.locationInWindow),
                      let term = findTerminalView(from: hit)
                else { return }
                let terminal = term.getTerminal()
                guard terminal.mouseMode != .off else { return }
                let button = event.deltaY > 0 ? 4 : 5
                let flags = event.modifierFlags
                let encoded = terminal.encodeButton(
                    button: button, release: false,
                    shift: flags.contains(.shift),
                    meta: flags.contains(.option),
                    control: flags.contains(.control)
                )
                terminal.sendEvent(buttonFlags: encoded, x: terminal.cols / 2, y: terminal.rows / 2)
                pass = false
            }
            return pass ? event : nil
        }
    }

    private static func findTerminalView(from view: NSView) -> LocalProcessTerminalView? {
        var v: NSView? = view
        while let cur = v {
            if let t = cur as? LocalProcessTerminalView { return t }
            v = cur.superview
        }
        return nil
    }
}

import AppKit
import SwiftTerm

/// Subclass marker so we can spot Tide-owned terminal views from a global
/// event monitor and know it's safe to drive `scrollUp`/`scrollDown`
/// ourselves. The behavioral work lives in `TerminalScrollForwarder`
/// because SwiftTerm's `scrollWheel` is `public` (not `open`), so we
/// can't override it from outside the module.
final class TideTerminalView: LocalProcessTerminalView {}

/// Intercepts scroll-wheel events over any Tide terminal pane and replaces
/// SwiftTerm's stock handler with a pixel-accurate, iTerm-style accumulator.
///
/// The upstream handler uses `event.deltaY` with a velocity boost
/// (`delta>9 → max(rows,20)`), which turns a single trackpad swipe into a
/// full-screen jump — that's the "glitchy / jumps too quickly" feel users
/// hit when scrolling scrollback or tmux copy-mode. Trackpads emit dozens
/// of pixel-precise events per second; we accumulate the pixel delta and
/// only step the buffer when a full line's worth of pixels has been
/// gathered, so scroll feels continuous and proportional to finger travel.
///
/// When the running app has mouse reporting enabled (tmux mouse-mode,
/// vim, htop), the same accumulator emits one SGR mouse-wheel button event
/// per line so the host app sees a smooth, line-rate stream rather than a
/// torrent of per-pixel events.
@MainActor
enum TerminalScrollForwarder {
    private static var installed = false
    /// Per-view pixel accumulator. Keyed by ObjectIdentifier so each pane
    /// keeps its own residual delta across events in a single gesture.
    private static var accumulators: [ObjectIdentifier: CGFloat] = [:]

    /// Auto-scroll-during-selection state. SwiftTerm declares
    /// `autoScrollDelta` + `scrollingTimerElapsed` but never schedules the
    /// timer, so dragging the mouse past the top/bottom edge of the view
    /// stops extending the selection — the user only copies the visible
    /// slice instead of the full selection iTerm gives them. We restore
    /// the behavior here: while a `.leftMouseDragged` is happening over
    /// a Tide terminal pane and the mouse is inside an edge band, we tick
    /// `scrollUp`/`scrollDown` on the view and replay the last drag event
    /// via the public `mouseDragged(with:)` entry point so SwiftTerm's
    /// `selection.dragExtend` walks into the newly-revealed rows.
    private static var autoScrollTimer: Timer?
    private static var autoScrollLastEvent: NSEvent?
    private static weak var autoScrollTarget: TideTerminalView?
    private static var autoScrollDirection: Int = 0

    static func install() {
        guard !installed else { return }
        installed = true
        installKeyMonitor()
        installSelectionDragMonitor()
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            var pass = true
            MainActor.assumeIsolated {
                guard let win = event.window,
                      let hit = win.contentView?.hitTest(event.locationInWindow),
                      let term = findTerminalView(from: hit)
                else { return }

                let lineHeight = computeLineHeight(for: term)
                guard lineHeight > 0 else { return }

                let key = ObjectIdentifier(term)
                if event.phase == .began {
                    accumulators[key] = 0
                }

                // hasPreciseScrollingDeltas: trackpad / Magic Mouse →
                // scrollingDeltaY is in points. Otherwise it's in line
                // units, which we widen to a pixel delta so the same
                // accumulator handles both input devices.
                let pixelDelta: CGFloat
                if event.hasPreciseScrollingDeltas {
                    pixelDelta = event.scrollingDeltaY
                } else {
                    pixelDelta = event.scrollingDeltaY * lineHeight
                }
                guard pixelDelta != 0 else {
                    // Always swallow the event for our panes; otherwise
                    // SwiftTerm's stock handler runs and reintroduces the
                    // velocity-boost jumps we're trying to suppress.
                    pass = false
                    return
                }

                var acc = (accumulators[key] ?? 0) + pixelDelta
                let lines = Int((acc / lineHeight).rounded(.towardZero))
                acc -= CGFloat(lines) * lineHeight
                accumulators[key] = acc
                pass = false

                guard lines != 0 else { return }

                let terminal = term.getTerminal()
                if terminal.mouseMode != .off {
                    let count = abs(lines)
                    let button = lines > 0 ? 4 : 5
                    let flags = event.modifierFlags
                    let encoded = terminal.encodeButton(
                        button: button, release: false,
                        shift: flags.contains(.shift),
                        meta: flags.contains(.option),
                        control: flags.contains(.control)
                    )
                    for _ in 0..<count {
                        terminal.sendEvent(buttonFlags: encoded, x: terminal.cols / 2, y: terminal.rows / 2)
                    }
                    return
                }

                if lines > 0 {
                    term.scrollUp(lines: lines)
                } else {
                    term.scrollDown(lines: -lines)
                }
            }
            return pass ? event : nil
        }
    }

    /// Maps Shift+Return / Shift+Keypad-Enter to a literal newline byte
    /// (`\n`) on the pty, matching iTerm2's default behavior. Stock
    /// SwiftTerm sends `\r` for both plain and shifted Return, which makes
    /// it impossible to insert a soft newline in CLIs that distinguish the
    /// two (Claude Code, python REPL, bash heredoc continuations, etc.).
    /// Without this, users have to chord Option+Return for every line break.
    private static func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            var pass = true
            MainActor.assumeIsolated {
                // 36 = Return, 76 = Keypad Enter.
                guard event.keyCode == 36 || event.keyCode == 76 else { return }
                let mods = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                // Pure Shift+Return only — leave Cmd/Ctrl/Option combos to
                // SwiftTerm and the app's existing menu shortcuts.
                guard mods == .shift else { return }
                guard let win = event.window,
                      let responder = win.firstResponder as? NSView,
                      let term = findTerminalView(from: responder)
                else { return }
                term.send(txt: "\n")
                pass = false
            }
            return pass ? event : nil
        }
    }

    private static func installSelectionDragMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            MainActor.assumeIsolated { stopAutoScroll() }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            MainActor.assumeIsolated { stopAutoScroll() }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { event in
            MainActor.assumeIsolated {
                guard let win = event.window,
                      let hit = win.contentView?.hitTest(event.locationInWindow)
                            ?? win.firstResponder as? NSView,
                      let term = findTideTerminalView(from: hit)
                else {
                    stopAutoScroll()
                    return
                }
                handleSelectionDrag(term: term, event: event)
            }
            return event
        }
    }

    private static func handleSelectionDrag(term: TideTerminalView, event: NSEvent) {
        // SwiftTerm processes this same event after our monitor returns,
        // so selection.dragExtend has already widened the selection to
        // the visible edge by the time our timer fires.
        autoScrollLastEvent = event
        autoScrollTarget = term

        guard term.selectionActive,
              term.getTerminal().mouseMode == .off
        else {
            stopAutoScroll()
            return
        }

        let local = term.convert(event.locationInWindow, from: nil)
        let band: CGFloat = 16
        let aboveTop = local.y > term.bounds.maxY - band
        let belowBottom = local.y < term.bounds.minY + band

        if aboveTop {
            startAutoScroll(direction: -1)
        } else if belowBottom {
            startAutoScroll(direction: 1)
        } else {
            stopAutoScroll()
        }
    }

    private static func startAutoScroll(direction: Int) {
        if autoScrollDirection == direction, autoScrollTimer != nil { return }
        stopAutoScroll()
        autoScrollDirection = direction
        let timer = Timer(timeInterval: 0.04, repeats: true) { _ in
            MainActor.assumeIsolated { autoScrollTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
    }

    private static func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDirection = 0
    }

    private static func autoScrollTick() {
        guard autoScrollDirection != 0,
              let event = autoScrollLastEvent,
              let term = autoScrollTarget
        else { return }
        if autoScrollDirection < 0 {
            term.scrollUp(lines: 1)
        } else {
            term.scrollDown(lines: 1)
        }
        // Public on NSResponder — calling it from outside is fine; only
        // overriding it across modules is blocked. SwiftTerm's
        // implementation re-runs calculateMouseHit with the updated
        // yDisp, so dragExtend pulls the selection into the newly
        // revealed rows.
        term.mouseDragged(with: event)
    }

    private static func findTideTerminalView(from view: NSView) -> TideTerminalView? {
        var v: NSView? = view
        while let cur = v {
            if let t = cur as? TideTerminalView { return t }
            v = cur.superview
        }
        return nil
    }

    private static func computeLineHeight(for view: LocalProcessTerminalView) -> CGFloat {
        let rows = view.getTerminal().rows
        guard rows > 0, view.frame.height > 0 else { return 0 }
        return view.frame.height / CGFloat(rows)
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

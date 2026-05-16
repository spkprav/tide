import SwiftUI
import AppKit
import SwiftTerm

struct TerminalLeafView: View {
    let sessionID: UUID
    @Bindable var tab: TabSession
    @State private var flash: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            PaneTitleBar(
                title: paneTitle,
                isActive: tab.activeLeafID == sessionID,
                isZoomed: tab.zoomedLeafID == sessionID,
                reminder: tab.reminders[sessionID],
                onArmReminder: { kind, msg in
                    tab.session?.armReminder(in: tab, sessionID: sessionID, kind: kind, message: msg)
                },
                onCancelReminder: {
                    tab.session?.clearReminder(in: tab, sessionID: sessionID)
                },
                onClose: {
                    tab.closeLeaf(sessionID: sessionID, sendExit: true)
                },
                onHide: {
                    tab.session?.hideLeaf(in: tab, sessionID: sessionID)
                },
                onToggleZoom: {
                    tab.toggleZoom(for: sessionID)
                }
            )
            TerminalRepresentable(sessionID: sessionID, tab: tab)
                .background(SwiftUI.Color.tnBg)
        }
        .background(SwiftUI.Color.tnBg)
        .overlay(
            Rectangle()
                .stroke(tab.activeLeafID == sessionID ? SwiftUI.Color.tnBlue : SwiftUI.Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .overlay(
            Rectangle()
                .stroke(SwiftUI.Color.tnBlue, lineWidth: 2 + flash * 4)
                .shadow(color: SwiftUI.Color.tnBlue.opacity(flash), radius: 18 * flash)
                .opacity(flash)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tab.activeLeafID = sessionID
        }
        .onAppear {
            if tab.session?.flashLeafID == sessionID {
                runFlash()
            }
        }
        .onChange(of: tab.session?.flashLeafID) { _, newVal in
            if newVal == sessionID {
                runFlash()
            }
        }
    }

    private func runFlash() {
        flash = 0
        withAnimation(.easeOut(duration: 0.18)) { flash = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeIn(duration: 0.18)) { flash = 0.35 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.15)) { flash = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeIn(duration: 0.18)) { flash = 0.4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.7)) { flash = 0 }
        }
    }

    private var paneTitle: String {
        let t = tab.leafTitles[sessionID]
        if let t, !t.isEmpty { return t }
        return "shell"
    }
}

struct PaneTitleBar: View {
    let title: String
    let isActive: Bool
    let isZoomed: Bool
    let reminder: PaneReminder?
    let onArmReminder: (ReminderKind, String) -> Void
    let onCancelReminder: () -> Void
    let onClose: () -> Void
    let onHide: () -> Void
    let onToggleZoom: () -> Void

    @State private var hover = false
    @State private var showReminder = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? SwiftUI.Color.tnBlue : SwiftUI.Color.tnFg3.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? SwiftUI.Color.tnFg : SwiftUI.Color.tnFg3)
                .lineLimit(1)
                .truncationMode(.middle)
            if isZoomed {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.tnYellow)
            }
            if reminder != nil {
                Image(systemName: reminder?.sawActivity == true ? "bell.badge.waveform" : "bell.badge")
                    .font(.system(size: 9))
                    .foregroundStyle(SwiftUI.Color.tnYellow)
            }
            Spacer(minLength: 0)
            if hover || isActive || reminder != nil {
                Button {
                    showReminder.toggle()
                } label: {
                    Image(systemName: reminder != nil ? "bell.fill" : "bell")
                        .font(.system(size: 10))
                        .foregroundStyle(reminder != nil ? SwiftUI.Color.tnYellow : SwiftUI.Color.tnFg3)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(reminder != nil ? "Reminder armed — click to manage" : "Notify me when this pane finishes")
                .popover(isPresented: $showReminder, arrowEdge: .top) {
                    ReminderPopover(
                        reminder: reminder,
                        onArm: { kind, msg in
                            onArmReminder(kind, msg)
                            showReminder = false
                        },
                        onCancel: {
                            onCancelReminder()
                            showReminder = false
                        }
                    )
                }

                Button(action: onToggleZoom) {
                    Image(systemName: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(isZoomed ? "Unzoom" : "Zoom (double-click title)")

                Button(action: onHide) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Hide pane (keep running)")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Close pane")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(SwiftUI.Color.tnBg2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SwiftUI.Color.tnLine).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) {
            onToggleZoom()
        }
    }
}

enum ReminderKindOption: String, CaseIterable, Identifiable {
    case processExit
    case claudeDone
    case aiMonitor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processExit: return "Process exit"
        case .claudeDone:  return "Claude done"
        case .aiMonitor:   return "AI monitor"
        }
    }

    var icon: String {
        switch self {
        case .processExit: return "stop.circle"
        case .claudeDone:  return "sparkle"
        case .aiMonitor:   return "eye.circle"
        }
    }

    var blurb: String {
        switch self {
        case .processExit:
            return "Fires when the current foreground task exits and the shell returns idle. Works for any command."
        case .claudeDone:
            return "Fires when Claude Code finishes a response or waits for plan approval. Requires global hook installed (Tide → Install Claude Notification Hook)."
        case .aiMonitor:
            return "Every N seconds Tide sends the pane's visible output to a local Ollama model and asks if your task is complete. Requires Ollama running locally."
        }
    }
}

struct ReminderPopover: View {
    let reminder: PaneReminder?
    let onArm: (ReminderKind, String) -> Void
    let onCancel: () -> Void

    @State private var kindOption: ReminderKindOption = .processExit
    @State private var message: String = ""
    @State private var aiInterval: Int = 30
    @State private var aiModel: String = "llama3.2"
    @State private var aiTask: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = reminder {
                armedView(r: r)
            } else {
                arrangementView()
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear {
            if reminder == nil { focused = true }
        }
    }

    @ViewBuilder
    private func armedView(r: PaneReminder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: r.sawActivity ? "bell.badge.waveform.fill" : "bell.badge.fill")
                .foregroundStyle(.yellow)
            Text(armedHeadline(r: r))
                .font(.system(size: 12, weight: .semibold))
        }
        HStack(spacing: 5) {
            Image(systemName: kindIcon(r.kind))
                .font(.system(size: 10))
            Text(r.kind.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        Text("Message:")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        Text(r.message.isEmpty ? "(default message)" : r.message)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        Button(role: .destructive) {
            onCancel()
        } label: {
            HStack {
                Image(systemName: "bell.slash.fill")
                Text("Cancel reminder")
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func arrangementView() -> some View {
        Text("Notify me when…")
            .font(.system(size: 12, weight: .semibold))

        Picker("Kind", selection: $kindOption) {
            ForEach(ReminderKindOption.allCases) { opt in
                Label(opt.title, systemImage: opt.icon).tag(opt)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text(kindOption.blurb)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if kindOption == .aiMonitor {
            VStack(alignment: .leading, spacing: 6) {
                Text("Task description")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("e.g. running db migration", text: $aiTask)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Interval (s)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("30", value: $aiInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama model")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("llama3.2", text: $aiModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Notification message")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("Optional (e.g. 'rails seed done')", text: $message)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { arm() }
        }

        Button {
            arm()
        } label: {
            HStack {
                Image(systemName: "bell.fill")
                Text("Watch this pane")
            }
            .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(armDisabled)
    }

    private var armDisabled: Bool {
        if kindOption == .aiMonitor {
            return aiTask.trimmingCharacters(in: .whitespaces).isEmpty
                || aiInterval < 3
                || aiModel.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return false
    }

    private func arm() {
        let kind: ReminderKind
        switch kindOption {
        case .processExit: kind = .processExit
        case .claudeDone:  kind = .claudeDone
        case .aiMonitor:
            kind = .aiMonitor(
                intervalSec: max(3, aiInterval),
                model: aiModel.trimmingCharacters(in: .whitespaces),
                taskPrompt: aiTask.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        onArm(kind, message)
    }

    private func armedHeadline(r: PaneReminder) -> String {
        switch r.kind {
        case .processExit:
            return r.sawActivity ? "Watching active task" : "Waiting for activity"
        case .claudeDone:
            return "Waiting for Claude to finish"
        case .aiMonitor:
            return "AI monitor running"
        }
    }

    private func kindIcon(_ k: ReminderKind) -> String {
        switch k {
        case .processExit: return "stop.circle"
        case .claudeDone:  return "sparkle"
        case .aiMonitor:   return "eye.circle"
        }
    }
}

struct TerminalRepresentable: NSViewRepresentable {
    let sessionID: UUID
    let tab: TabSession

    func makeNSView(context: Context) -> NSView {
        let host = HostingNSView()
        attach(to: host)
        host.onFocus = { [weak tab] in
            tab?.activeLeafID = sessionID
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let host = nsView as? HostingNSView {
            attach(to: host)
        }
    }

    private func attach(to host: NSView) {
        let terminal = tab.terminal(for: sessionID)
        if terminal.superview === host { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = []
        terminal.frame = host.bounds
        host.addSubview(terminal)
        (host as? HostingNSView)?.resizeSubviewsNow()
    }
}

final class HostingNSView: NSView {
    var onFocus: (() -> Void)?
    private var resizeWorkItem: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleDebouncedResize()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // Skip default auto-resize; debounced timer drives terminal resize.
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        resizeSubviewsNow()
    }

    private func scheduleDebouncedResize() {
        resizeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.resizeSubviewsNow()
        }
        resizeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    func resizeSubviewsNow() {
        resizeWorkItem?.cancel()
        resizeWorkItem = nil
        for sub in subviews {
            sub.frame = bounds
        }
    }
}

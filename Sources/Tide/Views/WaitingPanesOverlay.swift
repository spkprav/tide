import SwiftUI

struct WaitingPanesOverlay: View {
    @Environment(WaitingPaneStore.self) private var waiters
    @Environment(ProjectStore.self) private var projectStore

    var body: some View {
        if waiters.waiting.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(waiters.waiting.reversed()) { item in
                    WaitingPaneCard(
                        item: item,
                        onFocus: { focus(item) },
                        onDismiss: { waiters.dismiss(id: item.id) }
                    )
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 14)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .animation(.easeOut(duration: 0.18), value: waiters.waiting)
        }
    }

    private func focus(_ item: WaitingPane) {
        for project in projectStore.projects {
            guard let session = projectStore.sessions[project.id] else { continue }
            for tab in session.tabs where tab.terminals[item.id] != nil {
                projectStore.selectedID = project.id
                session.activeTabID = tab.id
                tab.activeLeafID = item.id
                session.flashLeafID = nil
                DispatchQueue.main.async { session.flashLeafID = item.id }
                waiters.dismiss(id: item.id)
                return
            }
        }
        // Pane not located (hidden / closed). Still dismiss so the card clears.
        waiters.dismiss(id: item.id)
    }
}

private struct WaitingPaneCard: View {
    let item: WaitingPane
    let onFocus: () -> Void
    let onDismiss: () -> Void

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.tnYellow)
                Text("\(item.projectName) · \(item.paneTitle)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color.tnFg)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SwiftUI.Color.tnFg3)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            Text(item.message.isEmpty ? "Claude is waiting for your input" : item.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SwiftUI.Color.tnFg2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(SwiftUI.Color.tnBg2)
                .shadow(color: SwiftUI.Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(hover ? SwiftUI.Color.tnYellow : SwiftUI.Color.tnYellow.opacity(0.55), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onFocus() }
        .help("Click to focus pane")
    }
}

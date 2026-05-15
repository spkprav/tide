import SwiftUI

struct TabBar: View {
    @Bindable var session: ProjectSession

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if !session.hiddenPanes.isEmpty {
                        TabChip(
                            title: "Hidden",
                            badge: session.hiddenPanes.count,
                            isActive: session.activeTabID == HIDDEN_TAB_ID,
                            canClose: false,
                            isHidden: true,
                            onSelect: { session.activeTabID = HIDDEN_TAB_ID },
                            onClose: {}
                        )
                    }
                    ForEach(Array(session.tabs.enumerated()), id: \.element.id) { idx, tab in
                        TabChip(
                            title: titleFor(tab: tab, index: idx + 1),
                            badge: nil,
                            isActive: tab.id == session.activeTabID,
                            canClose: session.tabs.count > 1,
                            isHidden: false,
                            onSelect: { session.activeTabID = tab.id },
                            onClose: { session.closeTab(tab.id) }
                        )
                    }
                    TabChip(
                        title: "Dashboard",
                        badge: nil,
                        isActive: session.activeTabID == DASHBOARD_TAB_ID,
                        canClose: false,
                        isHidden: false,
                        onSelect: { session.activeTabID = DASHBOARD_TAB_ID },
                        onClose: {}
                    )
                }
            }
            Spacer(minLength: 0)

            Button {
                session.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("New Tab (\u{2318}T)")

            Divider().frame(height: 16).padding(.horizontal, 4)

            Button {
                session.endSession()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 11))
                    Text("End")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.red.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help("End session")
            .padding(.trailing, 6)
        }
        .frame(height: 28)
        .background(Color(white: 0.10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func titleFor(tab: TabSession, index: Int) -> String {
        if let n = tab.name, !n.isEmpty { return n }
        let title = tab.leafTitles[tab.activeLeafID]
        if let t = title, !t.isEmpty { return t }
        return "Tab \(index)"
    }
}

struct TabChip: View {
    let title: String
    let badge: Int?
    let isActive: Bool
    let canClose: Bool
    let isHidden: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            if isHidden {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let badge {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
            }
            if canClose && (hover || isActive) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: 200)
        .background(isActive ? Color.primary.opacity(0.08) : (hover ? Color.primary.opacity(0.04) : Color.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .frame(width: 1, height: 14)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
    }
}

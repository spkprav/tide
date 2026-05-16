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
                    .foregroundStyle(Color.tnFg3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("New Tab (\u{2318}T)")

            Rectangle()
                .fill(Color.tnLine)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 6)

            Button {
                session.endSession()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill").font(.system(size: 10))
                    Text("End").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.tnRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.tnRed.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.tnRed.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("End session")
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(Color.tnBg2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.tnLine)
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
        HStack(spacing: 6) {
            if isHidden {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.tnFg3)
            }
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.tnFg : Color.tnFg3)
                .lineLimit(1)
                .truncationMode(.middle)
            if let badge {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.tnBg)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.tnPurple))
            }
            if canClose && (hover || isActive) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.tnFg3)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .frame(maxWidth: 220)
        .background(isActive ? Color.tnBg : (hover ? Color.tnBg.opacity(0.5) : Color.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.tnBlue)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.tnLine)
                .frame(width: 1, height: 16)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
    }
}

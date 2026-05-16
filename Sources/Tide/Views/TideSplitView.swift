import SwiftUI
import AppKit

// NSViewRepresentable wrapping NSSplitView so we can read + restore divider
// positions (SwiftUI's HSplitView/VSplitView don't expose these).
//
// The single NSSplitView is reused across SwiftUI re-renders. updateNSView
// diffs `childIDs` against tagged arranged subviews so existing
// LocalProcessTerminalView instances stay mounted when a sibling splits or
// closes (this is what prevents the all-panes-go-blank symptom).
struct TideSplitView<Child: View>: NSViewRepresentable {
    let axis: SplitAxis
    let childIDs: [UUID]
    let initialFractions: [CGFloat]
    let minimumChildSize: CGFloat
    let onResize: ([CGFloat]) -> Void
    let makeChild: (Int) -> Child

    init(
        axis: SplitAxis,
        childIDs: [UUID],
        initialFractions: [CGFloat],
        minimumChildSize: CGFloat,
        onResize: @escaping ([CGFloat]) -> Void,
        @ViewBuilder makeChild: @escaping (Int) -> Child
    ) {
        self.axis = axis
        self.childIDs = childIDs
        self.initialFractions = initialFractions
        self.minimumChildSize = minimumChildSize
        self.onResize = onResize
        self.makeChild = makeChild
    }

    func makeNSView(context: Context) -> TideNSSplitView {
        let split = TideNSSplitView()
        split.isVertical = (axis == .vertical)
        split.dividerStyle = .thin
        split.arrangesAllSubviews = true
        split.translatesAutoresizingMaskIntoConstraints = false
        split.delegate = context.coordinator
        context.coordinator.split = split
        context.coordinator.minimumChildSize = minimumChildSize
        return split
    }

    func updateNSView(_ split: TideNSSplitView, context: Context) {
        context.coordinator.onResize = onResize
        context.coordinator.minimumChildSize = minimumChildSize

        // Make sure orientation matches in case axis ever flips at runtime.
        let wantsVertical = (axis == .vertical)
        if split.isVertical != wantsVertical {
            split.isVertical = wantsVertical
        }

        diffChildren(in: split, ids: childIDs, coordinator: context.coordinator)
        context.coordinator.applyFractions(initialFractions, in: split)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onResize: onResize, minimumChildSize: minimumChildSize)
    }

    // MARK: - Subview diff

    private func diffChildren(
        in split: TideNSSplitView,
        ids: [UUID],
        coordinator: Coordinator
    ) {
        // Existing tagged subviews by id — typed to the same Child so the
        // inner NSHostingView<Child> diffs SwiftUI subtrees properly (no
        // AnyView identity churn → no terminal-view re-mount → no blank pane).
        let existing: [UUID: TideSplitChildView<Child>] = Dictionary(
            uniqueKeysWithValues: split.arrangedSubviews.compactMap { sub in
                guard let child = sub as? TideSplitChildView<Child> else { return nil }
                return (child.childID, child)
            }
        )

        var newOrder: [TideSplitChildView<Child>] = []
        for (idx, id) in ids.enumerated() {
            if let existingChild = existing[id] {
                existingChild.update(rootView: makeChild(idx))
                newOrder.append(existingChild)
            } else {
                let host = TideSplitChildView(childID: id, rootView: makeChild(idx))
                newOrder.append(host)
            }
        }

        // Remove ones that disappeared.
        let newIDs = Set(ids)
        for sub in split.arrangedSubviews {
            if let child = sub as? TideSplitChildView<Child>, !newIDs.contains(child.childID) {
                split.removeArrangedSubview(child)
                child.removeFromSuperview()
            }
        }

        // Reorder / insert.
        for (idx, host) in newOrder.enumerated() {
            let currentIdx = split.arrangedSubviews.firstIndex(of: host)
            if currentIdx == nil {
                split.insertArrangedSubview(host, at: idx)
            } else if currentIdx != idx {
                split.removeArrangedSubview(host)
                split.insertArrangedSubview(host, at: idx)
            }
        }

        coordinator.suppressWriteback = true
        split.adjustSubviews()
        coordinator.suppressWriteback = false
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var onResize: ([CGFloat]) -> Void
        var minimumChildSize: CGFloat
        weak var split: NSSplitView?
        var suppressWriteback = false
        private var pendingFractions: [CGFloat]?

        init(onResize: @escaping ([CGFloat]) -> Void, minimumChildSize: CGFloat) {
            self.onResize = onResize
            self.minimumChildSize = minimumChildSize
        }

        func applyFractions(_ fractions: [CGFloat], in split: NSSplitView) {
            let subviews = split.arrangedSubviews
            guard subviews.count == fractions.count, subviews.count > 1 else {
                pendingFractions = nil
                return
            }
            let total = split.isVertical ? split.bounds.width : split.bounds.height
            // If layout hasn't sized us yet, defer until first resize.
            if total <= 0 {
                pendingFractions = fractions
                return
            }
            pendingFractions = nil

            let dividerThickness = split.dividerThickness
            let available = total - dividerThickness * CGFloat(subviews.count - 1)
            guard available > 0 else { return }

            suppressWriteback = true
            var running: CGFloat = 0
            for i in 0..<(subviews.count - 1) {
                running += fractions[i] * available
                let position = running + dividerThickness * CGFloat(i)
                split.setPosition(position, ofDividerAt: i)
            }
            suppressWriteback = false
        }

        // Disallow draggable header collapse.
        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            false
        }

        // Per-subview minimum: each subview must be at least minimumChildSize.
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Divider can't go before previous subview's min edge.
            let subviews = splitView.arrangedSubviews
            guard dividerIndex < subviews.count else { return proposedMinimumPosition }
            let priorEdge: CGFloat
            if dividerIndex == 0 {
                priorEdge = 0
            } else {
                let prior = subviews[dividerIndex - 1].frame
                priorEdge = splitView.isVertical ? prior.minX : prior.minY
            }
            return priorEdge + minimumChildSize
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Leave room for remaining subviews after this divider.
            let subviews = splitView.arrangedSubviews
            let trailingCount = subviews.count - (dividerIndex + 1)
            guard trailingCount > 0 else { return proposedMaximumPosition }
            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            let reserved = minimumChildSize * CGFloat(trailingCount) + dividerThickness * CGFloat(trailingCount)
            return min(proposedMaximumPosition, total - reserved)
        }

        // Window-resize / drag: writes back current fractions.
        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !suppressWriteback, let split else { return }
            // If we had pending fractions waiting on first layout, apply now.
            if let p = pendingFractions {
                applyFractions(p, in: split)
                return
            }
            let fractions = currentFractions(of: split)
            guard !fractions.isEmpty else { return }
            onResize(fractions)
        }

        private func currentFractions(of split: NSSplitView) -> [CGFloat] {
            let subviews = split.arrangedSubviews
            guard subviews.count > 1 else { return [] }
            let sizes: [CGFloat] = subviews.map { sub in
                split.isVertical ? sub.frame.width : sub.frame.height
            }
            let total = sizes.reduce(0, +)
            guard total > 0 else { return [] }
            return sizes.map { $0 / total }
        }
    }
}

// NSSplitView subclass purely so we can give it a stable type name in diffs.
final class TideNSSplitView: NSSplitView {}

// Hosting view tagged with the SplitNode child id so we can diff across
// updateNSView calls without recreating subviews. Generic over Child so
// NSHostingView<Child> preserves SwiftUI structural identity — assigning
// rootView with the same concrete type lets SwiftUI diff in place instead
// of tearing down the inner tree (which would yank the LocalProcessTerminalView
// subview out and leave the pane blank).
final class TideSplitChildView<Child: View>: NSView {
    let childID: UUID
    private let hosting: NSHostingView<Child>

    init(childID: UUID, rootView: Child) {
        self.childID = childID
        self.hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(rootView: Child) {
        hosting.rootView = rootView
    }
}

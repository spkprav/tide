import Foundation

enum StartupLayout: String, Codable, CaseIterable, Identifiable {
    case singlePane            = "single"
    case grid2x2               = "grid2x2"
    case bigTopThreeBottom     = "bigTopThreeBottom"
    case leftMainRightStacked  = "leftMainRightStacked"
    case rowsStacked           = "rowsStacked"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singlePane:            return "Single Pane"
        case .grid2x2:               return "2×2 Grid"
        case .bigTopThreeBottom:     return "Big Top + 3 Bottom"
        case .leftMainRightStacked:  return "Left Main + Right Stacked"
        case .rowsStacked:           return "Rows Stacked"
        }
    }

    var paneCount: Int {
        switch self {
        case .singlePane:           return 1
        case .grid2x2,
             .bigTopThreeBottom,
             .leftMainRightStacked,
             .rowsStacked:          return 4
        }
    }

    func positionLabel(for index: Int) -> String {
        switch self {
        case .singlePane:
            return "pane"
        case .grid2x2:
            return ["top-left", "top-right", "bottom-left", "bottom-right"][safe: index] ?? "pane \(index + 1)"
        case .bigTopThreeBottom:
            return ["top (big)", "bottom-left", "bottom-middle", "bottom-right"][safe: index] ?? "pane \(index + 1)"
        case .leftMainRightStacked:
            return ["left (big)", "right-top", "right-middle", "right-bottom"][safe: index] ?? "pane \(index + 1)"
        case .rowsStacked:
            return "row \(index + 1)"
        }
    }
}

struct StartupPane: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var command: String

    init(id: UUID = UUID(), name: String = "", command: String = "") {
        self.id = id
        self.name = name
        self.command = command
    }
}

struct StartupConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var layout: StartupLayout
    var panes: [StartupPane]

    init(id: UUID = UUID(), name: String = "default", layout: StartupLayout = .grid2x2, panes: [StartupPane] = []) {
        self.id = id
        self.name = name
        self.layout = layout
        self.panes = panes
        ensurePaneCount()
    }

    mutating func ensurePaneCount() {
        let needed = layout.paneCount
        while panes.count < needed { panes.append(StartupPane()) }
        if panes.count > needed { panes = Array(panes.prefix(needed)) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

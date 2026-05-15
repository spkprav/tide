import Foundation
import SwiftUI

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var colorHex: String
    var isPinned: Bool

    init(id: UUID = UUID(), name: String, path: String, colorHex: String = "#7AA2F7", isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.colorHex = colorHex
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, colorHex, isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var expandedPath: String {
        (path as NSString).expandingTildeInPath
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let val = UInt32(s, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xff) / 255
        let g = Double((val >> 8)  & 0xff) / 255
        let b = Double( val        & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

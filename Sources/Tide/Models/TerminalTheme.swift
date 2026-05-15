import AppKit
import SwiftTerm

@MainActor
enum TerminalTheme {
    static let backgroundHex = "1A1B26"
    static let foregroundHex = "C0CAF5"

    static let backgroundNS: NSColor = nsColor(hex: backgroundHex)
    static let foregroundNS: NSColor = nsColor(hex: foregroundHex)

    static let palette: [SwiftTerm.Color] = [
        c("15161E"), c("F7768E"), c("9ECE6A"), c("E0AF68"),
        c("7AA2F7"), c("BB9AF7"), c("7DCFFF"), c("A9B1D6"),
        c("414868"), c("F7768E"), c("9ECE6A"), c("E0AF68"),
        c("7AA2F7"), c("BB9AF7"), c("7DCFFF"), c("C0CAF5"),
    ]

    private static func c(_ hex: String) -> SwiftTerm.Color {
        let val = UInt32(hex, radix: 16) ?? 0
        let r = UInt16((val >> 16) & 0xff) * 257
        let g = UInt16((val >> 8) & 0xff) * 257
        let b = UInt16(val & 0xff) * 257
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    private static func nsColor(hex: String) -> NSColor {
        let val = UInt32(hex, radix: 16) ?? 0
        let r = CGFloat((val >> 16) & 0xff) / 255
        let g = CGFloat((val >> 8) & 0xff) / 255
        let b = CGFloat(val & 0xff) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

@MainActor
extension LocalProcessTerminalView {
    func applyTideTheme() {
        installColors(TerminalTheme.palette)
        nativeForegroundColor = TerminalTheme.foregroundNS
        nativeBackgroundColor = TerminalTheme.backgroundNS
    }
}

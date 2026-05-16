import AppKit
import SwiftUI
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

// Tokyo Night palette as SwiftUI Color tokens — single source of truth.
extension SwiftUI.Color {
    static let tnBg       = SwiftUI.Color(tnHex: 0x1A1B26)
    static let tnBg2      = SwiftUI.Color(tnHex: 0x16161E)  // sidebar / title-bars / chrome
    static let tnBg3      = SwiftUI.Color(tnHex: 0x1F2030)  // inputs / chips
    static let tnBg4      = SwiftUI.Color(tnHex: 0x24283B)  // active row / hover
    static let tnLine     = SwiftUI.Color(tnHex: 0x2A2E42)  // borders / dividers
    static let tnFg       = SwiftUI.Color(tnHex: 0xC0CAF5)
    static let tnFg2      = SwiftUI.Color(tnHex: 0xA9B1D6)
    static let tnFg3      = SwiftUI.Color(tnHex: 0x565F89)  // muted / placeholder

    static let tnBlue     = SwiftUI.Color(tnHex: 0x7AA2F7)
    static let tnCyan     = SwiftUI.Color(tnHex: 0x7DCFFF)
    static let tnPurple   = SwiftUI.Color(tnHex: 0xBB9AF7)
    static let tnGreen    = SwiftUI.Color(tnHex: 0x9ECE6A)
    static let tnYellow   = SwiftUI.Color(tnHex: 0xE0AF68)
    static let tnOrange   = SwiftUI.Color(tnHex: 0xFF9E64)
    static let tnRed      = SwiftUI.Color(tnHex: 0xF7768E)
    static let tnPink     = SwiftUI.Color(tnHex: 0xF4B8E4)

    init(tnHex: UInt32, alpha: Double = 1) {
        let r = Double((tnHex >> 16) & 0xff) / 255
        let g = Double((tnHex >> 8)  & 0xff) / 255
        let b = Double( tnHex        & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// Custom ButtonStyles matching the HTML mockups.
struct TidePrimaryButton: ButtonStyle {
    var tint: SwiftUI.Color = .tnBlue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}

struct TideSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .foregroundStyle(SwiftUI.Color.tnFg)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SwiftUI.Color.tnBg3.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

struct TideChipButton: ButtonStyle {
    var tint: SwiftUI.Color = .tnFg2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(SwiftUI.Color.tnBg3.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(Capsule().strokeBorder(SwiftUI.Color.tnLine, lineWidth: 1))
            .contentShape(Capsule())
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

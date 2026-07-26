import SwiftUI

/// Ground Control ops-room palette. Dark only.
enum Theme {
    /// Ink black — window background.
    static let bg = Color(red: 0x0B / 255, green: 0x0E / 255, blue: 0x11 / 255)
    /// Raised panel background.
    static let panel = Color(red: 0x12 / 255, green: 0x16 / 255, blue: 0x1B / 255)
    /// Radar green — go / working.
    static let radar = Color(red: 0x3D / 255, green: 1.0, blue: 0x88 / 255)
    /// Amber — waiting / needs input.
    static let amber = Color(red: 1.0, green: 0xB4 / 255, blue: 0x54 / 255)
    /// White-blue — landed / done.
    static let landed = Color(red: 0xDC / 255, green: 0xE8 / 255, blue: 0xF5 / 255)
    /// Red — blocked / error.
    static let red = Color(red: 1.0, green: 0x5C / 255, blue: 0x5C / 255)
    /// Hairline borders between panels.
    static let hairline = Color(red: 0x1E / 255, green: 0x26 / 255, blue: 0x30 / 255)
    /// Dimmed labels.
    static let dim = Color(red: 0x5A / 255, green: 0x66 / 255, blue: 0x72 / 255)

    /// Data font (flight numbers, branches, paths).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Letterspaced caps section header.
    static func header(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension NSColor {
    static let gcPanel = NSColor(calibratedRed: 0x12 / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 1)
    static let gcRadar = NSColor(calibratedRed: 0x3D / 255, green: 1.0, blue: 0x88 / 255, alpha: 1)
    static let gcText = NSColor(calibratedWhite: 0.87, alpha: 1)
}

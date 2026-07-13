import SwiftUI

/// Kawaii pastel palette shared across every screen. Soft cream-pink page,
/// candy accents that rotate per card, and a warm charcoal ink (never pure
/// black) so the whole app reads soft and sweet.
public enum Palette {
    // Page + card surfaces
    public static let background = Color(hex: 0xFFF6FA)
    public static let card = Color.white

    // Pastel accent pairs (strong accent + its soft fill)
    public static let pink = Color(hex: 0xFF9EC4)
    public static let pinkSoft = Color(hex: 0xFFE3EE)
    public static let mint = Color(hex: 0x86E0BE)
    public static let mintSoft = Color(hex: 0xDCF7EE)
    public static let lavender = Color(hex: 0xC0A9FF)
    public static let lavenderSoft = Color(hex: 0xEBE3FF)
    public static let butter = Color(hex: 0xFFD36E)
    public static let butterSoft = Color(hex: 0xFFF2CE)
    public static let sky = Color(hex: 0x8FC9FF)
    public static let skySoft = Color(hex: 0xDCEEFF)
    public static let coral = Color(hex: 0xFFAF87)
    public static let coralSoft = Color(hex: 0xFFE8D8)

    // Text
    public static let ink = Color(hex: 0x6B5563)
    public static let inkSoft = Color(hex: 0xA8929E)

    // Primary brand accent (candy pink)
    public static let accent = Color(hex: 0xFF80B5)

    /// Soft-fill + accent pairs cycled across cards for the playful, multi-color
    /// kitsch look.
    public static let rotation: [(soft: Color, accent: Color)] = [
        (pinkSoft, pink),
        (mintSoft, mint),
        (lavenderSoft, lavender),
        (butterSoft, butter),
        (skySoft, sky),
    ]

    /// Stable tint for a given index so the same row always gets the same color.
    public static func tint(_ index: Int) -> (soft: Color, accent: Color) {
        rotation[((index % rotation.count) + rotation.count) % rotation.count]
    }
}

extension Color {
    /// 0xRRGGBB initializer for the palette literals above.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

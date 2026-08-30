import SwiftUI

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}

// MARK: - App palette

enum Palette {
    static let bg0 = Color(hex: "0b0e14")
    static let bg1 = Color(hex: "121722")
    static let panel = Color(hex: "1a2130")
    static let panelHi = Color(hex: "232c40")
    static let stroke = Color(hex: "2c3750")
    static let text = Color(hex: "e7ecf5")
    static let subtle = Color(hex: "8a94a6")
    static let money = Color(hex: "5be08a")
    /// Accent reserved for "this is interactive" cues (e.g. the duplicates on a
    /// pack summary that are waiting for a keep-or-sell decision).
    static let tapCue = Color(hex: "4f9dff")

    static let screen = LinearGradient(
        colors: [bg1, bg0],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Rarity styling

extension Rarity {
    var accent: Color {
        switch self {
        case .common: return Color(hex: "8a94a6")
        case .uncommon: return Color(hex: "3fbf7f")
        case .rare: return Color(hex: "3b82f6")
        case .ultra: return Color(hex: "b06cf7")
        }
    }

    /// Gradient used for borders / labels. Ultra shimmers gold→violet.
    var frameColors: [Color] {
        switch self {
        case .ultra: return [Color(hex: "ffd54a"), Color(hex: "ff8ad6"), Color(hex: "b06cf7")]
        default: return [accent, accent.opacity(0.65)]
        }
    }

    var gemGradient: LinearGradient {
        LinearGradient(colors: frameColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Element art palettes (mirror of cards.js TYPE_PALETTES)

extension Element {
    var palette: [Color] {
        switch self {
        case .fire:     return ["ffd15c", "ff7a1a", "e01f1f", "5c1004"].map { Color(hex: $0) }
        case .rock:     return ["f0c27a", "c98a3c", "8a5a2b", "3d2413"].map { Color(hex: $0) }
        case .water:    return ["9fe8ff", "39a7ff", "1e5bd6", "0a2a66"].map { Color(hex: $0) }
        case .grass:    return ["c6f68d", "5fd35f", "2f9e44", "12481f"].map { Color(hex: $0) }
        case .electric: return ["fff3a3", "ffd21a", "f5a300", "6b4a00"].map { Color(hex: $0) }
        case .shadow:   return ["d9b3ff", "9b5cf6", "5b2bb3", "1f0d3d"].map { Color(hex: $0) }
        }
    }

    /// Faint element color used to tint the type badge (text + capsule wash).
    var badgeTint: Color {
        switch self {
        case .fire:     return Color(hex: "ff9a6b")
        case .rock:     return Color(hex: "e0b483")
        case .water:    return Color(hex: "8fd3ff")
        case .grass:    return Color(hex: "9fe08a")
        case .electric: return Color(hex: "ffdf66")
        case .shadow:   return Color(hex: "c6a3ff")
        }
    }

    /// The SF Symbol that stands for this element — a clean icon used for the
    /// Catalyst card faces (Fire→flame, Water→droplet, Grass→leaf, Electric→bolt,
    /// Shadow→crescent moon). Kept here beside the palette so element identity and
    /// its glyph live together.
    var glyphSymbol: String {
        switch self {
        case .fire:     return "flame.fill"
        case .rock:     return "mountain.2.fill"
        case .water:    return "drop.fill"
        case .grass:    return "leaf.fill"
        case .electric: return "bolt.fill"
        case .shadow:   return "moon.fill"
        }
    }

    /// Background wash inside the art window.
    var artGradient: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [palette[1].opacity(0.55), palette[2], palette[3]]),
            center: .center, startRadius: 4, endRadius: 150
        )
    }

    /// The signature element used to theme each set's shop banner.
    static func theme(forSet set: Int) -> Element {
        switch set {
        case 1: return .fire
        case 2: return .water
        case 3: return .grass
        case 4: return .electric
        default: return .shadow
        }
    }
}

// MARK: - Money formatting

extension Double {
    var money: String {
        let s = String(format: "%.2f", self)
        return "$\(s)"
    }
    var moneyShort: String {
        if self >= 1000 {
            return "$" + String(format: "%.1fk", self / 1000)
        }
        return money
    }
}

func pad3(_ n: Int) -> String { String(format: "%03d", n) }

/// Color used for a PSA grade badge / reveal.
func gradeColor(_ g: Int) -> Color {
    switch g {
    case 9...10: return Color(hex: "ffd54a")
    case 8:      return Color(hex: "8a94a6")
    case 1:      return Color(hex: "ff5cf0")
    default:     return Color(hex: "e0663b")
    }
}

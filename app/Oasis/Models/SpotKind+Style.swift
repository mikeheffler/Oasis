import SwiftUI
import OasisCore

/// App-only styling for the OasisCore kinds. Same colors and symbols as the explorer.
/// Change the branding here and in `Views/SpotPin.swift`.
extension SpotKind {
    var symbol: String {
        switch self {
        case .fountain: "drop.fill"
        case .tap: "spigot.fill"
        case .business: "cup.and.saucer.fill"
        case .convenience: "fuelpump.fill"
        case .grocery: "cart.fill"
        case .restaurant: "fork.knife"
        case .other: "circle.fill"
        }
    }

    /// Public water is blue. Businesses (free or buy) are amber. Other is slate.
    /// The buy categories share amber and differ by symbol, to keep the palette small.
    /// Each color has at least 4.5:1 contrast with a white symbol.
    var tint: Color {
        switch self {
        case .business, .convenience, .grocery, .restaurant: .oasisAmber
        case .other: .oasisSlate
        case .fountain, .tap: .oasisBlue
        }
    }
}

extension Color {
    /// #1668C7
    static let oasisBlue = Color(red: 0x16 / 255, green: 0x68 / 255, blue: 0xC7 / 255)
    /// #A8650A
    static let oasisAmber = Color(red: 0xA8 / 255, green: 0x65 / 255, blue: 0x0A / 255)
    /// #5E6E7C
    static let oasisSlate = Color(red: 0x5E / 255, green: 0x6E / 255, blue: 0x7C / 255)
    /// #14212B, dark text on light badges.
    static let oasisInk = Color(red: 0x14 / 255, green: 0x21 / 255, blue: 0x2B / 255)
}

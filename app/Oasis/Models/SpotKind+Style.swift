import SwiftUI
import OasisCore

/// App-only styling for the OasisCore kinds.
extension SpotKind {
    var symbol: String {
        switch self {
        case .fountain: "drop.fill"
        case .tap: "spigot.fill"
        case .business: "cup.and.saucer.fill"
        case .convenience: "fuelpump.fill"
        case .grocery: "cart.fill"
        case .restaurant: "fork.knife"
        case .other: "mappin"
        }
    }

    /// Public water is blue. Businesses (free or buy) are amber. Other is slate.
    /// The buy categories share amber and differ by symbol, to keep the palette small.
    var tint: Color {
        switch self {
        case .business, .convenience, .grocery, .restaurant: Color(red: 0.85, green: 0.55, blue: 0.10)
        case .other: Color(red: 0.35, green: 0.45, blue: 0.55)
        case .fountain, .tap: Color(red: 0.10, green: 0.45, blue: 0.85)
        }
    }
}

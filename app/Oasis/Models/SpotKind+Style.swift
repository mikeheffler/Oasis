import SwiftUI
import OasisCore

/// App-only styling for the OasisCore kinds.
extension SpotKind {
    /// Kinds that the map view loads. Buy water loads along a route only (phase 3).
    static let mapKinds: [SpotKind] = [.fountain, .tap, .business, .other]

    var symbol: String {
        switch self {
        case .fountain: "drop.fill"
        case .tap: "spigot.fill"
        case .business: "cup.and.saucer.fill"
        case .buy: "cart.fill"
        case .other: "mappin"
        }
    }

    /// Public water is blue. Businesses (free or buy) are amber. Other is slate.
    var tint: Color {
        switch self {
        case .business, .buy: Color(red: 0.85, green: 0.55, blue: 0.10)
        case .other: Color(red: 0.35, green: 0.45, blue: 0.55)
        case .fountain, .tap: Color(red: 0.10, green: 0.45, blue: 0.85)
        }
    }
}

import Foundation

/// The type of water point. `business` gives free water (ask first).
/// `convenience`, `grocery`, and `restaurant` sell water: you must pay.
/// Colors and SF Symbols stay in the app, because they need SwiftUI.
public enum SpotKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case fountain
    case tap
    case business
    case convenience
    case grocery
    case restaurant
    case other

    public var id: String { rawValue }

    /// The kinds where you must buy something.
    public static let buyKinds: [SpotKind] = [.convenience, .grocery, .restaurant]

    public var label: String {
        switch self {
        case .fountain: "Fountain"
        case .tap: "Tap"
        case .business: "Business (free)"
        case .convenience: "Gas & convenience"
        case .grocery: "Grocery"
        case .restaurant: "Restaurant & cafe"
        case .other: "Other"
        }
    }

    /// Free water with no purchase: fountains, taps, businesses that give water, and other.
    public var isFree: Bool { !Self.buyKinds.contains(self) }

    public var longLabel: String {
        switch self {
        case .fountain: "Drinking fountain"
        case .tap: "Tap or spigot"
        case .business: "Business that gives free water"
        case .convenience: "Gas station, convenience store, or drink machine"
        case .grocery: "Grocery store"
        case .restaurant: "Restaurant, cafe, or fast food"
        case .other: "Other water source"
        }
    }
}

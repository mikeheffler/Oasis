import Foundation

/// The type of water point. `business` gives free water (ask first).
/// `buy` is the only kind where you must pay. The app shows each type with its own symbol and color.
/// Colors and SF Symbols stay in the app, because they need SwiftUI.
public enum SpotKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case fountain
    case tap
    case business
    case buy
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fountain: "Fountain"
        case .tap: "Tap"
        case .business: "Business"
        case .buy: "Buy water"
        case .other: "Other"
        }
    }

    /// Free water with no purchase: fountains, taps, businesses that give water, and other.
    public var isFree: Bool { self != .buy }

    public var longLabel: String {
        switch self {
        case .fountain: "Drinking fountain"
        case .tap: "Tap or spigot"
        case .business: "Business that gives free water"
        case .buy: "Store that sells water"
        case .other: "Other water source"
        }
    }
}

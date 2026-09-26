import Foundation

/// The type of water point. The app shows each type with its own symbol and color.
/// Colors and SF Symbols stay in the app, because they need SwiftUI.
public enum SpotKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case fountain
    case tap
    case business
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fountain: "Fountain"
        case .tap: "Tap"
        case .business: "Business"
        case .other: "Other"
        }
    }

    public var longLabel: String {
        switch self {
        case .fountain: "Drinking fountain"
        case .tap: "Tap or spigot"
        case .business: "Business that gives water"
        case .other: "Other water source"
        }
    }
}

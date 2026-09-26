import Foundation

/// The two data layers. Each loads and caches on its own.
public enum SpotLayer: String, Codable, CaseIterable, Hashable, Sendable {
    /// Free drinking water: fountains, taps, free businesses, other.
    case freeWater
    /// Places that sell drinks. Dense in towns, so load it only when zoomed in or along a route.
    case buyWater
}

extension SpotKind {
    /// The layer that owns spots of this kind.
    public var layer: SpotLayer { self == .buy ? .buyWater : .freeWater }
}

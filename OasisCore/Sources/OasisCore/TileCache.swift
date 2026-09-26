import Foundation

/// Loaded spots plus the time each tile was loaded, per layer.
/// The app store keeps one of these and saves it to disk.
public struct TileCache: Codable, Sendable {
    public private(set) var spots: [String: WaterSpot] = [:]
    /// layer raw value -> tile -> load time.
    private var loaded: [String: [TileKey: Date]] = [:]

    public init() {}

    /// Tiles in the box that were never loaded for the layer, or are older than `maxAge`.
    public func missingTiles(covering box: BoundingBox, layer: SpotLayer,
                             now: Date, maxAge: TimeInterval) -> [TileKey] {
        let dates = loaded[layer.rawValue] ?? [:]
        return TileKey.tiles(covering: box).filter { key in
            guard let date = dates[key] else { return true }
            return now.timeIntervalSince(date) > maxAge
        }
    }

    /// Replaces the layer's spots in the given tiles with a fresh fetch.
    /// Only spots whose kind belongs to `layer` are kept, so a free-water spot that
    /// the buy-water query also returns stays owned by the free-water layer.
    public mutating func merge(_ fetched: [WaterSpot], tiles: [TileKey], layer: SpotLayer, at date: Date) {
        let tileSet = Set(tiles)
        func inScope(_ spot: WaterSpot) -> Bool {
            spot.kind.layer == layer && tileSet.contains(TileKey(containing: spot.coordinate))
        }
        spots = spots.filter { !inScope($0.value) }
        for spot in fetched where inScope(spot) {
            spots[spot.id] = spot
        }
        var dates = loaded[layer.rawValue] ?? [:]
        for key in tiles { dates[key] = date }
        loaded[layer.rawValue] = dates
    }
}

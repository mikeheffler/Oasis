import Foundation

/// A south/west/north/east box in degrees. The box does not cross the antimeridian.
public struct BoundingBox: Hashable, Codable, Sendable {
    public let south: Double
    public let west: Double
    public let north: Double
    public let east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// A box around a center point, for example from a map region.
    public init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        self.init(south: center.latitude - latitudeDelta / 2,
                  west: center.longitude - longitudeDelta / 2,
                  north: center.latitude + latitudeDelta / 2,
                  east: center.longitude + longitudeDelta / 2)
    }

    /// The smallest box that holds all the given tiles. Nil for an empty list.
    public init?(covering tiles: some Collection<TileKey>) {
        guard let minX = tiles.map(\.x).min(), let maxX = tiles.map(\.x).max(),
              let minY = tiles.map(\.y).min(), let maxY = tiles.map(\.y).max() else { return nil }
        self.init(south: Double(minY) * TileKey.size,
                  west: Double(minX) * TileKey.size,
                  north: Double(maxY + 1) * TileKey.size,
                  east: Double(maxX + 1) * TileKey.size)
    }

    public var latitudeSpan: Double { north - south }
    public var longitudeSpan: Double { east - west }

    public func contains(_ c: Coordinate) -> Bool {
        (south...north).contains(c.latitude) && (west...east).contains(c.longitude)
    }

    /// The same box, made larger on each side by `meters`.
    public func expanded(byMeters meters: Double) -> BoundingBox {
        let padLat = meters / Geo.metersPerDegreeLatitude
        let midLat = (south + north) / 2
        let padLon = meters / Geo.metersPerDegreeLongitude(atLatitude: midLat)
        return BoundingBox(south: south - padLat, west: west - padLon,
                           north: north + padLat, east: east + padLon)
    }
}

/// A fixed 0.25° grid cell. The store loads and caches data one tile at a time,
/// so a pan of the map does not load the same area again.
public struct TileKey: Hashable, Codable, Sendable {
    public static let size = 0.25
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public init(containing c: Coordinate) {
        x = Int((c.longitude / Self.size).rounded(.down))
        y = Int((c.latitude / Self.size).rounded(.down))
    }

    public var box: BoundingBox {
        BoundingBox(south: Double(y) * Self.size, west: Double(x) * Self.size,
                    north: Double(y + 1) * Self.size, east: Double(x + 1) * Self.size)
    }

    /// All tiles that touch the box, west to east, then south to north.
    public static func tiles(covering box: BoundingBox) -> [TileKey] {
        let minX = Int((box.west / size).rounded(.down)), maxX = Int((box.east / size).rounded(.down))
        let minY = Int((box.south / size).rounded(.down)), maxY = Int((box.north / size).rounded(.down))
        guard minX <= maxX, minY <= maxY else { return [] }
        return (minX...maxX).flatMap { x in (minY...maxY).map { TileKey(x: x, y: $0) } }
    }
}

/// Flat-earth scale factors. Same constants as the explorer.
public enum Geo {
    public static let metersPerDegreeLatitude = 110_540.0
    public static func metersPerDegreeLongitude(atLatitude lat: Double) -> Double {
        111_320.0 * cos(lat * .pi / 180)
    }
    public static let metersPerMile = 1_609.344
}

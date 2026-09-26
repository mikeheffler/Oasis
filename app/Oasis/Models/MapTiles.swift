import Foundation
import MapKit

/// A south/west/north/east box in degrees.
struct BoundingBox: Hashable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
}

/// A fixed 0.25° grid cell. The store loads and caches data one tile at a time,
/// so a pan of the map does not load the same area again.
struct TileKey: Hashable, Codable {
    static let size = 0.25
    let x: Int
    let y: Int

    init(x: Int, y: Int) { self.x = x; self.y = y }

    init(containing c: CLLocationCoordinate2D) {
        x = Int((c.longitude / Self.size).rounded(.down))
        y = Int((c.latitude / Self.size).rounded(.down))
    }

    static func tiles(covering region: MKCoordinateRegion) -> [TileKey] {
        let s = region.center.latitude - region.span.latitudeDelta / 2
        let n = region.center.latitude + region.span.latitudeDelta / 2
        let w = region.center.longitude - region.span.longitudeDelta / 2
        let e = region.center.longitude + region.span.longitudeDelta / 2
        let minX = Int((w / size).rounded(.down)), maxX = Int((e / size).rounded(.down))
        let minY = Int((s / size).rounded(.down)), maxY = Int((n / size).rounded(.down))
        guard minX <= maxX, minY <= maxY else { return [] }
        return (minX...maxX).flatMap { x in (minY...maxY).map { TileKey(x: x, y: $0) } }
    }
}

extension BoundingBox {
    /// The smallest box that holds all the given tiles.
    init(covering tiles: [TileKey]) {
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        south = Double(ys.min() ?? 0) * TileKey.size
        north = Double((ys.max() ?? 0) + 1) * TileKey.size
        west = Double(xs.min() ?? 0) * TileKey.size
        east = Double((xs.max() ?? 0) + 1) * TileKey.size
    }
}

extension MKCoordinateRegion {
    /// True if the point is in the region, with a small margin.
    func contains(_ c: CLLocationCoordinate2D, margin: Double = 1.2) -> Bool {
        abs(c.latitude - center.latitude) <= span.latitudeDelta / 2 * margin &&
        abs(c.longitude - center.longitude) <= span.longitudeDelta / 2 * margin
    }
}

import Foundation

/// A WGS 84 latitude/longitude pair in degrees.
/// OasisCore uses this type instead of CoreLocation, so it builds on Linux.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Mean Earth radius in meters (IUGG). Same value as the explorer.
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in meters (haversine).
    public func distance(to other: Coordinate) -> Double {
        let r = Double.pi / 180
        let dLat = (other.latitude - latitude) * r
        let dLon = (other.longitude - longitude) * r
        let h = pow(sin(dLat / 2), 2)
            + cos(latitude * r) * cos(other.latitude * r) * pow(sin(dLon / 2), 2)
        return 2 * Self.earthRadius * asin(min(1, sqrt(h)))
    }
}

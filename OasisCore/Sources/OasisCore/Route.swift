import Foundation

/// A route as a polyline, for example from a GPX file.
/// Distances are in meters along the route. Ported from the explorer's route check.
public struct Route: Sendable {
    public let name: String
    public let points: [Coordinate]
    /// `cumulative[i]` is the distance from the start to `points[i]`.
    public let cumulative: [Double]
    public let bounds: BoundingBox

    public var length: Double { cumulative.last ?? 0 }

    /// Nil if there are fewer than 2 points.
    public init?(points: [Coordinate], name: String = "") {
        guard points.count >= 2 else { return nil }
        var cum = [0.0]
        cum.reserveCapacity(points.count)
        for i in 1..<points.count {
            cum.append(cum[i - 1] + points[i - 1].distance(to: points[i]))
        }
        self.name = name
        self.points = points
        self.cumulative = cum
        self.bounds = BoundingBox(
            south: points.map(\.latitude).min()!, west: points.map(\.longitude).min()!,
            north: points.map(\.latitude).max()!, east: points.map(\.longitude).max()!)
    }

    public struct Projection: Equatable, Sendable {
        /// Meters from the point to the nearest place on the route.
        public let distanceFromRoute: Double
        /// Meters from the route start to that nearest place.
        public let distanceAlong: Double
    }

    /// The nearest place on the route. If the route passes the point more than once,
    /// this gives the first pass that is nearest.
    /// Uses a local flat-earth projection. Good to well under 1% at buffer distances.
    public func project(_ c: Coordinate) -> Projection {
        let kx = Geo.metersPerDegreeLongitude(atLatitude: c.latitude)
        let ky = Geo.metersPerDegreeLatitude
        var bestD = Double.infinity, bestAlong = 0.0
        for i in 0..<(points.count - 1) {
            let ax = (points[i].longitude - c.longitude) * kx, ay = (points[i].latitude - c.latitude) * ky
            let bx = (points[i + 1].longitude - c.longitude) * kx, by = (points[i + 1].latitude - c.latitude) * ky
            let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let d = hypot(ax + t * dx, ay + t * dy)
            if d < bestD {
                bestD = d
                bestAlong = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
            }
        }
        return Projection(distanceFromRoute: bestD, distanceAlong: bestAlong)
    }

    /// The position at a distance along the route. Clamped to the route ends.
    public func point(atDistance distance: Double) -> Coordinate {
        let dist = min(max(distance, 0), length)
        var i = 0
        while i < cumulative.count - 2 && cumulative[i + 1] < dist { i += 1 }
        let seg = cumulative[i + 1] - cumulative[i]
        let t = seg > 0 ? (dist - cumulative[i]) / seg : 0
        let a = points[i], b = points[i + 1]
        return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                          longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// The part of the route between two distances, for example to draw a gap.
    public func slice(from start: Double, to end: Double) -> [Coordinate] {
        var out = [point(atDistance: start)]
        for i in points.indices where cumulative[i] > start && cumulative[i] < end {
            out.append(points[i])
        }
        out.append(point(atDistance: end))
        return out
    }

    /// A thinned copy of the route for an Overpass `around` query.
    /// Keeps points at least `minSpacing` meters apart, and makes the spacing larger
    /// until there are at most `maxPoints`. Always keeps the first and last points.
    public func sampled(minSpacing: Double = 400, maxPoints: Int = 500) -> [Coordinate] {
        var step = minSpacing
        while true {
            var out = [points[0]]
            var last = 0
            for i in 1..<points.count where cumulative[i] - cumulative[last] >= step {
                out.append(points[i])
                last = i
            }
            if last != points.count - 1 { out.append(points[points.count - 1]) }
            if out.count <= max(maxPoints, 2) { return out }
            step *= 1.5
        }
    }
}

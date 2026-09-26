import Foundation

/// A water point near a route.
public struct RouteStop: Sendable {
    public let spot: WaterSpot
    /// Meters from the route start.
    public let distanceAlong: Double
    /// Meters off the route.
    public let distanceFromRoute: Double
}

/// A part of the route with no water. From the start, between stops, or to the end.
public struct RouteGap: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public var length: Double { end - start }
}

/// Water along a route, and the distances with no water. Ported from the explorer.
public struct RouteAnalysis: Sendable {
    public let route: Route
    public let bufferMeters: Double
    /// Sorted by distance along the route.
    public let stops: [RouteStop]
    /// In route order. Covers the full route: start to first stop, ..., last stop to end.
    public let gaps: [RouteGap]

    /// Finds spots within `bufferMeters` of the route. Only spots of the given kinds count.
    public init(route: Route, spots: some Sequence<WaterSpot>, bufferMeters: Double,
                kinds: Set<SpotKind> = Set(SpotKind.allCases)) {
        let area = route.bounds.expanded(byMeters: bufferMeters)
        var stops: [RouteStop] = []
        for spot in spots where kinds.contains(spot.kind) && area.contains(spot.coordinate) {
            let p = route.project(spot.coordinate)
            if p.distanceFromRoute <= bufferMeters {
                stops.append(RouteStop(spot: spot, distanceAlong: p.distanceAlong,
                                       distanceFromRoute: p.distanceFromRoute))
            }
        }
        stops.sort { ($0.distanceAlong, $0.spot.id) < ($1.distanceAlong, $1.spot.id) }

        let marks = [0] + stops.map(\.distanceAlong) + [route.length]
        self.route = route
        self.bufferMeters = bufferMeters
        self.stops = stops
        self.gaps = zip(marks, marks.dropFirst()).map { RouteGap(start: $0, end: $1) }
    }

    /// The longest gaps, longest first. Ties keep route order.
    public func longestGaps(_ count: Int = 3) -> [RouteGap] {
        let ranked = gaps.enumerated().sorted {
            ($0.element.length, -$0.offset) > ($1.element.length, -$1.offset)
        }
        return ranked.prefix(count).map(\.element)
    }

    /// The first stop after a distance along the route, for "distance to next water".
    public func nextStop(after distanceAlong: Double) -> RouteStop? {
        stops.first { $0.distanceAlong > distanceAlong }
    }
}

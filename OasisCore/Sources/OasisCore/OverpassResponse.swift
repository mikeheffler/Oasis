import Foundation

/// The JSON that Overpass returns for `[out:json]`.
public struct OverpassResponse: Decodable, Sendable {
    public struct Center: Decodable, Sendable {
        public let lat: Double
        public let lon: Double
    }

    public struct Element: Decodable, Sendable {
        public let type: String
        public let id: Int64
        public let lat: Double?
        public let lon: Double?
        public let center: Center?
        public let tags: [String: String]?
        // Present only with `out meta`.
        public let timestamp: String?
        public let version: Int?
        public let user: String?

        /// The node position, or the center of a way or relation.
        public var coordinate: Coordinate? {
            if let lat, let lon { return Coordinate(latitude: lat, longitude: lon) }
            if let center { return Coordinate(latitude: center.lat, longitude: center.lon) }
            return nil
        }
    }

    public let elements: [Element]
    /// Overpass sends HTTP 200 with a remark when a query times out or runs out of memory.
    /// The elements are then incomplete.
    public let remark: String?

    public var isIncomplete: Bool {
        remark?.localizedCaseInsensitiveContains("error") ?? false
    }
}

public enum OverpassParseError: Error, Equatable, Sendable {
    /// The server stopped early. Do not cache the result as complete.
    case incomplete(remark: String)
}

extension OverpassResponse {
    public static func decode(_ data: Data) throws -> OverpassResponse {
        try JSONDecoder().decode(OverpassResponse.self, from: data)
    }

    /// Public drinking water spots. Drops excluded features and elements with no position.
    /// Throws `OverpassParseError.incomplete` if the server stopped early.
    public func waterSpots() throws -> [WaterSpot] {
        if isIncomplete, let remark { throw OverpassParseError.incomplete(remark: remark) }
        return elements.compactMap { el in
            guard let c = el.coordinate else { return nil }
            return WaterSpot(osmType: el.type, osmID: el.id,
                             latitude: c.latitude, longitude: c.longitude, tags: el.tags ?? [:])
        }
    }
}

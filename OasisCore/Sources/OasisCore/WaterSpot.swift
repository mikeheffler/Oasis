import Foundation

/// One water point. Phase 1 gets all points from OpenStreetMap.
/// Phase 2 adds community points from the backend with the same model.
///
/// The Codable keys match the phase 1 app disk cache
/// (id, source, latitude, longitude, kind, tags).
public struct WaterSpot: Identifiable, Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case openStreetMap, community }

    public let id: String            // "node/123" for OSM
    public let source: Source
    public let latitude: Double
    public let longitude: Double
    public let kind: SpotKind
    public let tags: [String: String]
    /// The latest Oasis user report, from the backend. Nil for Overpass data or no reports.
    /// Optional, so disk caches written before this field still decode.
    public let lastReport: LastReport?

    public init(id: String, source: Source, latitude: Double, longitude: Double,
                kind: SpotKind, tags: [String: String], lastReport: LastReport? = nil) {
        self.id = id
        self.source = source
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.tags = tags
        self.lastReport = lastReport
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    public var displayName: String { tags["name"] ?? kind.longLabel }
    public var hasBottleFiller: Bool { tags["bottle"] == "yes" }
    public var seasonal: String? { tags["seasonal"].flatMap { $0 == "no" ? nil : $0 } }
    public var fee: String? { tags["fee"] }
    public var openingHours: String? { tags["opening_hours"] }
    public var access: String? { tags["access"] }
    public var lastChecked: String? { tags["check_date"] ?? tags["survey:date"] }
    public var note: String? { tags["description"] ?? tags["note"] }

    public var osmURL: URL? {
        guard source == .openStreetMap else { return nil }
        return URL(string: "https://www.openstreetmap.org/\(id)")
    }
}

/// The latest report for a point: its type ("working", "not_working", ...) and time.
public struct LastReport: Codable, Hashable, Sendable {
    public let type: String
    public let date: Date

    public init(type: String, date: Date) {
        self.type = type
        self.date = date
    }
}

extension WaterSpot {
    /// Makes a spot from OSM data. Returns nil if `OSMRules` hides the feature.
    public init?(osmType: String, osmID: Int64, latitude: Double, longitude: Double, tags: [String: String]) {
        guard case .show(let kind) = OSMRules.evaluate(tags) else { return nil }
        self.init(id: "\(osmType)/\(osmID)", source: .openStreetMap,
                  latitude: latitude, longitude: longitude, kind: kind, tags: tags)
    }
}

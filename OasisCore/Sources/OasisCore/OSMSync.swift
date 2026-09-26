import Foundation

/// A region that the backend sync copies from OSM, split into square tiles.
public struct SyncRegion: Sendable, Equatable {
    public let name: String
    public let bounds: BoundingBox

    public init(name: String, bounds: BoundingBox) {
        self.name = name
        self.bounds = bounds
    }

    /// The state of Colorado, with a small margin (about 37.0–41.0 N, 102.04–109.06 W).
    public static let colorado = SyncRegion(
        name: "colorado",
        bounds: BoundingBox(south: 36.95, west: -109.10, north: 41.05, east: -102.00))

    public static let all: [SyncRegion] = [.colorado]

    public static func named(_ name: String) -> SyncRegion? {
        all.first { $0.name == name.lowercased() }
    }

    /// Whole-degree tiles (aligned to integer degrees) that cover the region,
    /// clipped to the region bounds. West to east, then south to north.
    public func tiles(size: Double = 1) -> [BoundingBox] {
        var out: [BoundingBox] = []
        var x = (bounds.west / size).rounded(.down) * size
        while x < bounds.east {
            var y = (bounds.south / size).rounded(.down) * size
            while y < bounds.north {
                out.append(BoundingBox(south: max(y, bounds.south), west: max(x, bounds.west),
                                       north: min(y + size, bounds.north), east: min(x + size, bounds.east)))
                y += size
            }
            x += size
        }
        return out
    }
}

/// One row of the `osm_points` table (supabase/migrations). Hidden features are kept,
/// with the reason, so the database has the full picture; the read API filters them.
public struct OSMPointRow: Encodable, Equatable, Sendable {
    public let osmID: String
    public let geom: String            // EWKT, e.g. "SRID=4326;POINT(-105.0 39.7)"
    public let kind: String?
    public let hiddenReason: String?
    public let tags: [String: String]
    public let surveyDate: String?     // YYYY-MM-DD
    public let osmVersion: Int?
    public let osmEditedAt: String?    // ISO 8601, as Overpass sends it
    public let syncedAt: String        // ISO 8601
    public let removedAt: String?      // always null: a synced point is present

    enum CodingKeys: String, CodingKey {
        case osmID = "osm_id", geom, kind, hiddenReason = "hidden_reason", tags
        case surveyDate = "survey_date", osmVersion = "osm_version", osmEditedAt = "osm_edited_at"
        case syncedAt = "synced_at", removedAt = "removed_at"
    }

    // Write removed_at as an explicit null, so an upsert brings a point back.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(osmID, forKey: .osmID)
        try c.encode(geom, forKey: .geom)
        try c.encode(kind, forKey: .kind)
        try c.encode(hiddenReason, forKey: .hiddenReason)
        try c.encode(tags, forKey: .tags)
        try c.encode(surveyDate, forKey: .surveyDate)
        try c.encode(osmVersion, forKey: .osmVersion)
        try c.encode(osmEditedAt, forKey: .osmEditedAt)
        try c.encode(syncedAt, forKey: .syncedAt)
        try c.encodeNil(forKey: .removedAt)
    }
}

public enum OSMSync {
    /// The Overpass query for one tile: both layers, with edit metadata.
    public static func query(for tile: BoundingBox, timeout: Int = 180) -> String {
        OverpassQuery.query(in: .box(tile), layers: Set(SpotLayer.allCases), timeout: timeout, output: .meta)
    }

    /// Database rows for a complete Overpass response.
    /// Throws `OverpassParseError.incomplete` when the server stopped early:
    /// the caller must then keep the old data for the tile.
    public static func rows(from response: OverpassResponse, syncedAt: Date) throws -> [OSMPointRow] {
        if response.isIncomplete, let remark = response.remark {
            throw OverpassParseError.incomplete(remark: remark)
        }
        let synced = iso8601(syncedAt)
        var seen = Set<String>()
        var rows: [OSMPointRow] = []
        for el in response.elements {
            guard let c = el.coordinate else { continue }
            let id = "\(el.type)/\(el.id)"
            guard seen.insert(id).inserted else { continue }
            let tags = el.tags ?? [:]
            let kind: String?, reason: String?
            switch OSMRules.evaluate(tags) {
            case .show(let k): (kind, reason) = (k.rawValue, nil)
            case .hide(let why): (kind, reason) = (nil, hiddenReason(why))
            }
            rows.append(OSMPointRow(
                osmID: id,
                geom: "SRID=4326;POINT(\(OverpassQuery.fmt(c.longitude, digits: 7)) \(OverpassQuery.fmt(c.latitude, digits: 7)))",
                kind: kind,
                hiddenReason: reason,
                tags: tags,
                surveyDate: VerificationRules.surveyDate(in: tags, asOf: syncedAt).map(day),
                osmVersion: el.version,
                osmEditedAt: el.timestamp,
                syncedAt: synced,
                removedAt: nil))
        }
        return rows
    }

    /// Same text as the explorer's hide reasons.
    public static func hiddenReason(_ exclusion: OSMRules.Exclusion) -> String {
        switch exclusion {
        case .notDrinkable: "drinking_water=no"
        case .restrictedAccess(let value): "access=\(value)"
        case .problem(let tag): tag
        }
    }

    static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func day(_ date: Date) -> String {
        let c = VerificationRules.utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

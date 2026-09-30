import Foundation

/// The map read API of the Oasis backend: the `spots_in_bbox` Postgres function
/// (supabase/migrations), called through PostgREST with the publishable key.
/// The app builds the HTTP request; this type owns the body, the box split, and the parsing.
public enum SupabaseSpotsAPI {
    /// Path below the project URL.
    public static let rpcPath = "rest/v1/rpc/spots_in_bbox"
    /// The function returns at most this many rows. A full page may be cut off.
    public static let rowLimit = 5000
    /// Largest box side per request. The server allows 2°; smaller boxes stay far below the row limit.
    public static let maxRequestSpan = 0.5

    public struct Page: Sendable {
        public let spots: [WaterSpot]
        /// Rows in the reply, including rows the app skipped (unknown kind).
        public let rowCount: Int
        public var isTruncated: Bool { rowCount >= SupabaseSpotsAPI.rowLimit }
    }

    /// Server-side layer names. Same values as `spots_in_bbox`.
    public static func layerName(_ layer: SpotLayer) -> String {
        switch layer {
        case .freeWater: "freeWater"
        case .buyWater: "buyWater"
        }
    }

    public static func requestBody(box: BoundingBox, layers: Set<SpotLayer>) throws -> Data {
        struct Body: Encodable {
            let west, south, east, north: Double
            let layers: [String]
        }
        return try JSONEncoder().encode(Body(
            west: box.west, south: box.south, east: box.east, north: box.north,
            layers: SpotLayer.allCases.filter(layers.contains).map(layerName)))
    }

    /// Splits a box into a grid of equal pieces, each at most `maxSpan` on a side.
    /// Points on a shared edge can come back twice; callers merge by id.
    public static func chunks(of box: BoundingBox, maxSpan: Double = maxRequestSpan) -> [BoundingBox] {
        let nx = max(1, Int((box.longitudeSpan / maxSpan).rounded(.up)))
        let ny = max(1, Int((box.latitudeSpan / maxSpan).rounded(.up)))
        let dx = box.longitudeSpan / Double(nx), dy = box.latitudeSpan / Double(ny)
        var out: [BoundingBox] = []
        for i in 0..<nx {
            for j in 0..<ny {
                out.append(BoundingBox(
                    south: box.south + Double(j) * dy,
                    west: box.west + Double(i) * dx,
                    north: j == ny - 1 ? box.north : box.south + Double(j + 1) * dy,
                    east: i == nx - 1 ? box.east : box.west + Double(i + 1) * dx))
            }
        }
        return out
    }

    /// Parses the JSON rows. Skips rows with an unknown kind or source, so a newer
    /// backend cannot break an older app.
    public static func decode(_ data: Data) throws -> Page {
        let rows = try JSONDecoder().decode([Row].self, from: data)
        let spots = rows.compactMap(\.spot)
        return Page(spots: spots, rowCount: rows.count)
    }

    struct Row: Decodable {
        let source: String
        let id: String
        let lat: Double
        let lon: Double
        let kind: String
        let tags: [String: String]
        let lastReportType: String?
        let lastReportAt: String?

        enum CodingKeys: String, CodingKey {
            case source, id, lat, lon, kind, tags
            case lastReportType = "last_report_type", lastReportAt = "last_report_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = try c.decode(String.self, forKey: .source)
            id = try c.decode(String.self, forKey: .id)
            lat = try c.decode(Double.self, forKey: .lat)
            lon = try c.decode(Double.self, forKey: .lon)
            kind = try c.decode(String.self, forKey: .kind)
            // OSM tags are all strings. Anything else is dropped, not fatal.
            tags = (try? c.decodeIfPresent([String: String].self, forKey: .tags)) ?? [:]
            lastReportType = try c.decodeIfPresent(String.self, forKey: .lastReportType)
            lastReportAt = try c.decodeIfPresent(String.self, forKey: .lastReportAt)
        }

        var spot: WaterSpot? {
            guard let kind = SpotKind(rawValue: kind) else { return nil }
            let source: WaterSpot.Source
            switch self.source {
            case "osm": source = .openStreetMap
            case "community": source = .community
            default: return nil
            }
            var report: LastReport?
            if let type = lastReportType, let date = lastReportAt.flatMap(SupabaseSpotsAPI.parseTimestamp) {
                report = LastReport(type: type, date: date)
            }
            return WaterSpot(id: id, source: source, latitude: lat, longitude: lon,
                             kind: kind, tags: tags, lastReport: report)
        }
    }

    /// Parses a Postgres/PostgREST timestamptz, e.g. "2026-09-30T19:00:01.123456+00:00".
    /// Drops the fraction first: `ISO8601DateFormatter` does not read 6 fraction digits everywhere.
    public static func parseTimestamp(_ text: String) -> Date? {
        var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            s.removeSubrange(dot..<end)
        }
        return ISO8601DateFormatter().date(from: s)
    }
}

extension BoundingBox {
    /// True if the two boxes overlap (touching edges count).
    public func intersects(_ other: BoundingBox) -> Bool {
        west <= other.east && other.west <= east && south <= other.north && other.south <= north
    }
}

extension SyncRegion {
    /// True if the backend has data somewhere in the box.
    public static func coverage(includes box: BoundingBox) -> Bool {
        all.contains { $0.bounds.intersects(box) }
    }
}

extension SupabaseSpotsAPI {
    /// Reads a Supabase project URL from config text, such as a CI secret.
    /// Accepts "https://<ref>.supabase.co", the same without "https://",
    /// and a dashboard link ("https://supabase.com/dashboard/project/<ref>/…").
    /// Trims spaces, line breaks, and a trailing slash. Returns nil for other text.
    public static func projectURL(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        if !s.lowercased().hasPrefix("http:"), !s.lowercased().hasPrefix("https:") {
            s = "https://" + s
        }
        guard let url = URL(string: s), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host == "supabase.com" || host.hasSuffix(".supabase.com") {
            let parts = url.path.split(separator: "/")
            guard let i = parts.firstIndex(of: "project"), i + 1 < parts.count else { return nil }
            return URL(string: "https://\(parts[i + 1]).supabase.co")
        }
        return url
    }
}

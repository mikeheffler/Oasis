import Foundation

/// Builds Overpass QL for water points. Same query as the explorer.
///
/// Clients must not call the public Overpass server in production.
/// The app uses this only for phase 1 tests. The phase 2 backend sync uses it too.
public enum OverpassQuery {
    public enum Area: Sendable {
        /// All features in a box.
        case box(BoundingBox)
        /// All features within `radius` meters of a polyline.
        case around(radius: Double, path: [Coordinate])
    }

    /// `tags` is smaller. `meta` adds timestamp, version, and user for data-quality checks.
    public enum Output: String, Sendable {
        case tags
        case meta
    }

    /// `nwr` gets nodes, ways, and relations.
    /// `out center` gives one point for ways and relations (for example, a building).
    public static func waterPoints(in area: Area, timeout: Int = 25, output: Output = .tags) -> String {
        let filter = areaFilter(area)
        return """
        [out:json][timeout:\(timeout)];
        (
          nwr["amenity"="drinking_water"]["drinking_water"!="no"]\(filter);
          nwr["amenity"="water_point"]["drinking_water"!="no"]\(filter);
          nwr["drinking_water"="yes"]\(filter);
          nwr["drinking_water:refill"="yes"]\(filter);
        );
        out center \(output.rawValue);
        """
    }

    static func areaFilter(_ area: Area) -> String {
        switch area {
        case .box(let b):
            return "(\(fmt(b.south)),\(fmt(b.west)),\(fmt(b.north)),\(fmt(b.east)))"
        case .around(let radius, let path):
            let coords = path.map { "\(fmt($0.latitude, digits: 5)),\(fmt($0.longitude, digits: 5))" }
            return "(around:\(Int(radius.rounded())),\(coords.joined(separator: ",")))"
        }
    }

    /// Fixed-point text. Plain `\(double)` can print "1e-05", which Overpass rejects.
    static func fmt(_ value: Double, digits: Int = 6) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// The POST body for an Overpass request (`application/x-www-form-urlencoded`).
    public static func formBody(for query: String) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // `.alphanumerics` includes non-ASCII letters. Keep the unreserved set ASCII only.
        let ascii = CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed.intersection(ascii)) ?? ""
        return Data(("data=" + encoded).utf8)
    }
}

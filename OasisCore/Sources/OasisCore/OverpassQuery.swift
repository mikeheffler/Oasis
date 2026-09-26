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

    /// What to fetch.
    public enum Layer: Sendable, CaseIterable {
        /// Free drinking water: fountains, taps, and features tagged with drinking water.
        case freeWater
        /// Places that sell drinks. Many per town, so fetch this layer along a route only.
        case buyWater
    }

    /// Free drinking water only. Same query as the explorer's map view.
    public static func waterPoints(in area: Area, timeout: Int = 25, output: Output = .tags) -> String {
        query(in: area, layers: [.freeWater], timeout: timeout, output: output)
    }

    /// `nwr` gets nodes, ways, and relations.
    /// `out center` gives one point for ways and relations (for example, a building).
    /// Filter the results with `OSMRules.evaluate`: the query does not remove problem tags.
    public static func query(in area: Area, layers: Set<Layer>, timeout: Int = 25, output: Output = .tags) -> String {
        let filter = areaFilter(area)
        var lines: [String] = []
        if layers.contains(.freeWater) {
            lines += [
                #"nwr["amenity"="drinking_water"]["drinking_water"!="no"]"#,
                #"nwr["amenity"="water_point"]["drinking_water"!="no"]"#,
                #"nwr["drinking_water"="yes"]"#,
                #"nwr["drinking_water:refill"="yes"]"#,
            ]
        }
        if layers.contains(.buyWater) {
            lines += [
                #"nwr["shop"~"^(\#(alternation(OSMRules.buyShops)))$"]"#,
                #"nwr["amenity"~"^(\#(alternation(OSMRules.buyAmenities)))$"]"#,
                #"nwr["amenity"="vending_machine"]["vending"~"(^|;)(\#(alternation(OSMRules.drinkVending)))(;|$)"]"#,
            ]
        }
        return """
        [out:json][timeout:\(timeout)];
        (
        \(lines.map { "  \($0)\(filter);" }.joined(separator: "\n"))
        );
        out center \(output.rawValue);
        """
    }

    /// Sorted so the query text is stable.
    static func alternation(_ values: Set<String>) -> String {
        values.sorted().joined(separator: "|")
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

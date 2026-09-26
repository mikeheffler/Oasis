import Foundation

/// Gets water points from the public Overpass API.
/// Prototype only: the public server has usage limits. Phase 2 moves this
/// query to a scheduled backend sync, and the app reads from the backend.
struct OverpassClient: WaterSpotSource {
    var endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    var session: URLSession = .shared

    enum OverpassError: LocalizedError {
        case rateLimited, serverBusy, badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .rateLimited: "Too many requests. Wait one minute, then try again."
            case .serverBusy: "The map data server is busy. Try again soon."
            case .badStatus(let code): "The map data server gave error \(code)."
            }
        }
    }

    func spots(in box: BoundingBox) async throws -> [WaterSpot] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Oasis-iOS/0.1 (personal prototype)", forHTTPHeaderField: "User-Agent")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = Self.query(for: box).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = Data(("data=" + encoded).utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 429: throw OverpassError.rateLimited
            case 504: throw OverpassError.serverBusy
            default: throw OverpassError.badStatus(http.statusCode)
            }
        }
        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
        return decoded.elements.compactMap { el in
            guard let lat = el.lat ?? el.center?.lat,
                  let lon = el.lon ?? el.center?.lon else { return nil }
            return WaterSpot(osmType: el.type, osmID: el.id, latitude: lat, longitude: lon, tags: el.tags ?? [:])
        }
    }

    /// Overpass QL. `nwr` gets nodes, ways, and relations.
    /// `out center` gives one point for ways and relations (for example, a building).
    static func query(for b: BoundingBox) -> String {
        let bbox = "\(b.south),\(b.west),\(b.north),\(b.east)"
        return """
        [out:json][timeout:25];
        (
          nwr["amenity"="drinking_water"]["drinking_water"!="no"](\(bbox));
          nwr["amenity"="water_point"]["drinking_water"!="no"](\(bbox));
          nwr["drinking_water"="yes"](\(bbox));
          nwr["drinking_water:refill"="yes"](\(bbox));
        );
        out center tags;
        """
    }
}

private struct OverpassResponse: Decodable {
    struct Center: Decodable { let lat: Double; let lon: Double }
    struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?
    }
    let elements: [Element]
}

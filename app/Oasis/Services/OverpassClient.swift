import Foundation
import OasisCore

/// Gets water points from the public Overpass API.
/// Prototype only: the public server has usage limits. Phase 2 moves this
/// query to a scheduled backend sync, and the app reads from the backend.
struct OverpassClient: WaterSpotSource {
    var endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    var session: URLSession = .shared

    enum OverpassError: LocalizedError {
        case rateLimited, serverBusy, incomplete, badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .rateLimited: "Too many requests. Wait one minute, then try again."
            case .serverBusy, .incomplete: "The map data server is busy. Try again soon."
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
        request.httpBody = OverpassQuery.formBody(for: OverpassQuery.waterPoints(in: .box(box)))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 429: throw OverpassError.rateLimited
            case 504: throw OverpassError.serverBusy
            default: throw OverpassError.badStatus(http.statusCode)
            }
        }
        do {
            return try OverpassResponse.decode(data).waterSpots()
        } catch is OverpassParseError {
            // HTTP 200 with a timeout remark: the data is partial. Do not cache it.
            throw OverpassError.incomplete
        }
    }
}

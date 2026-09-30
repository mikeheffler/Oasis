import Foundation
import OasisCore

/// Reads water points from the Oasis backend (`spots_in_bbox`).
/// OasisCore builds the request body and parses the reply; this type only does HTTP.
struct SupabaseSource: WaterSpotSource {
    var baseURL = SupabaseConfig.url
    var key = SupabaseConfig.publishableKey
    var session: URLSession = .shared

    enum SourceError: LocalizedError {
        case badStatus(Int)
        case tooManyPoints

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): "The Oasis server gave error \(code). Try again soon."
            case .tooManyPoints: "Too many places in this area. Zoom in."
            }
        }
    }

    func spots(in box: BoundingBox, layer: SpotLayer) async throws -> [WaterSpot] {
        var merged: [String: WaterSpot] = [:]
        // Small requests stay far below the server row limit.
        for chunk in SupabaseSpotsAPI.chunks(of: box) {
            var request = URLRequest(url: baseURL.appendingPathComponent(SupabaseSpotsAPI.rpcPath))
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try SupabaseSpotsAPI.requestBody(box: chunk, layers: [layer])

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SourceError.badStatus(http.statusCode)
            }
            let page = try SupabaseSpotsAPI.decode(data)
            // A full page can be cut off. Do not cache it as complete.
            if page.isTruncated { throw SourceError.tooManyPoints }
            for spot in page.spots { merged[spot.id] = spot }
        }
        return Array(merged.values)
    }
}

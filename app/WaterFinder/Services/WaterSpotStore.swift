import Foundation
import MapKit
import Observation

/// Holds all loaded water points. Loads data for the visible map area
/// and keeps a disk cache, so areas you loaded before still show with no signal.
@MainActor
@Observable
final class WaterSpotStore {
    private(set) var spots: [String: WaterSpot] = [:]
    private(set) var isLoading = false
    private(set) var statusMessage: String?

    static let maxSpanDegrees = 1.0
    static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60

    private let source: any WaterSpotSource
    private var tileDates: [TileKey: Date] = [:]
    private var currentTask: Task<Void, Never>?

    init(source: any WaterSpotSource) {
        self.source = source
        loadCache()
    }

    /// Call when the map stops moving.
    func regionChanged(_ region: MKCoordinateRegion) {
        currentTask?.cancel()
        currentTask = Task { await load(region) }
    }

    private func load(_ region: MKCoordinateRegion) async {
        guard region.span.latitudeDelta <= Self.maxSpanDegrees,
              region.span.longitudeDelta <= Self.maxSpanDegrees else {
            isLoading = false
            statusMessage = "Zoom in to load water points"
            return
        }

        let now = Date()
        let missing = TileKey.tiles(covering: region).filter { key in
            guard let date = tileDates[key] else { return true }
            return now.timeIntervalSince(date) > Self.cacheLifetime
        }
        guard !missing.isEmpty else {
            isLoading = false
            statusMessage = nil
            return
        }

        isLoading = true
        statusMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(400)) // debounce fast pans
            let fetched = try await source.spots(in: BoundingBox(covering: missing))
            try Task.checkCancellation()

            // Replace the data in the new tiles only.
            let missingSet = Set(missing)
            spots = spots.filter { !missingSet.contains(TileKey(containing: $0.value.coordinate)) }
            for spot in fetched where missingSet.contains(TileKey(containing: spot.coordinate)) {
                spots[spot.id] = spot
            }
            for key in missing { tileDates[key] = now }
            saveCache()
            isLoading = false
        } catch {
            if Task.isCancelled { return } // a newer load replaced this one
            isLoading = false
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load water points. Check your connection."
        }
    }

    // MARK: Disk cache

    private struct CacheFile: Codable {
        var spots: [WaterSpot]
        var tiles: [TileKey: Date]
    }

    nonisolated private static let cacheURL = URL.cachesDirectory.appending(path: "water-spots-cache.json")

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else { return }
        spots = Dictionary(file.spots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        tileDates = file.tiles
    }

    private func saveCache() {
        let file = CacheFile(spots: Array(spots.values), tiles: tileDates)
        guard let data = try? JSONEncoder().encode(file) else { return }
        let url = Self.cacheURL
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

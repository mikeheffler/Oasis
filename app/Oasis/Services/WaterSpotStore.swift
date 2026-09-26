import Foundation
import MapKit
import Observation
import OasisCore

/// Holds all loaded water points. Loads data for the visible map area, one layer at a time,
/// and keeps a disk cache, so areas you loaded before still show with no signal.
@MainActor
@Observable
final class WaterSpotStore {
    private(set) var spots: [String: WaterSpot] = [:]
    private(set) var isLoading = false
    private(set) var statusMessage: String?

    static let maxSpanDegrees = 1.0
    /// Buy water is dense in towns, so it loads only when the view is this narrow or less.
    static let maxBuySpanDegrees = 0.5
    static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60

    private let source: any WaterSpotSource
    private var cache = TileCache()
    private var currentTask: Task<Void, Never>?

    init(source: any WaterSpotSource) {
        self.source = source
        loadCache()
    }

    /// Call when the map stops moving, or when the buy water filter changes.
    func regionChanged(_ region: MKCoordinateRegion, loadBuyWater: Bool) {
        currentTask?.cancel()
        currentTask = Task { await load(region, loadBuyWater: loadBuyWater) }
    }

    private func load(_ region: MKCoordinateRegion, loadBuyWater: Bool) async {
        guard region.span.latitudeDelta <= Self.maxSpanDegrees,
              region.span.longitudeDelta <= Self.maxSpanDegrees else {
            isLoading = false
            statusMessage = "Zoom in to load water points"
            return
        }

        var layers: [SpotLayer] = [.freeWater]
        var note: String?
        if loadBuyWater {
            if region.span.latitudeDelta <= Self.maxBuySpanDegrees,
               region.span.longitudeDelta <= Self.maxBuySpanDegrees {
                layers.append(.buyWater)
            } else {
                note = "Zoom in to load buy water"
            }
        }

        let now = Date()
        let view = BoundingBox(region)
        let jobs: [(layer: SpotLayer, tiles: [TileKey], box: BoundingBox)] = layers.compactMap { layer in
            let tiles = cache.missingTiles(covering: view, layer: layer, now: now, maxAge: Self.cacheLifetime)
            guard let box = BoundingBox(covering: tiles) else { return nil }
            return (layer, tiles, box)
        }
        guard !jobs.isEmpty else {
            isLoading = false
            statusMessage = note
            return
        }

        isLoading = true
        statusMessage = note
        do {
            try await Task.sleep(for: .milliseconds(400)) // debounce fast pans
            for job in jobs {
                let fetched = try await source.spots(in: job.box, layer: job.layer)
                try Task.checkCancellation()
                cache.merge(fetched, tiles: job.tiles, layer: job.layer, at: now)
                spots = cache.spots
            }
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

    // v4: buy water split into three kinds. A new name drops caches in older formats.
    nonisolated private static let cacheURL = URL.cachesDirectory.appending(path: "water-spots-cache-v4.json")

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let file = try? JSONDecoder().decode(TileCache.self, from: data) else { return }
        cache = file
        spots = file.spots
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        let url = Self.cacheURL
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

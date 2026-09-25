import Foundation

/// Any provider of water points. Phase 1 uses OverpassClient.
/// Phase 2 adds a Supabase source, so the rest of the app does not change.
protocol WaterSpotSource {
    func spots(in box: BoundingBox) async throws -> [WaterSpot]
}

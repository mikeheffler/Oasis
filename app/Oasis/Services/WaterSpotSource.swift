import Foundation
import OasisCore

/// Any provider of water points. Phase 1 uses OverpassClient.
/// Phase 2 adds a Supabase source, so the rest of the app does not change.
protocol WaterSpotSource: Sendable {
    func spots(in box: BoundingBox, layer: SpotLayer) async throws -> [WaterSpot]
}

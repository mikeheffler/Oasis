import XCTest
@testable import OasisCore

final class TileCacheTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    let week: TimeInterval = 7 * 24 * 3600
    /// Tile (-490, 153): 38.25...38.5 N, 122.5...122.25 W.
    let box = TileKey(x: -490, y: 153).box

    func spot(_ id: String, _ kind: SpotKind, _ lat: Double = 38.3, _ lon: Double = -122.3) -> WaterSpot {
        WaterSpot(id: id, source: .openStreetMap, latitude: lat, longitude: lon, kind: kind, tags: [:])
    }

    func testKindLayers() {
        XCTAssertEqual(SpotKind.buy.layer, .buyWater)
        for kind in SpotKind.allCases where kind != .buy {
            XCTAssertEqual(kind.layer, .freeWater, kind.rawValue)
        }
    }

    func testMissingTilesPerLayer() {
        var cache = TileCache()
        let tiles = cache.missingTiles(covering: box, layer: .freeWater, now: t0, maxAge: week)
        XCTAssertEqual(tiles, [TileKey(x: -490, y: 153), TileKey(x: -490, y: 154),
                               TileKey(x: -489, y: 153), TileKey(x: -489, y: 154)])
        cache.merge([], tiles: tiles, layer: .freeWater, at: t0)
        XCTAssertEqual(cache.missingTiles(covering: box, layer: .freeWater, now: t0, maxAge: week), [])
        XCTAssertEqual(cache.missingTiles(covering: box, layer: .buyWater, now: t0, maxAge: week).count, 4)
    }

    func testTilesExpire() {
        var cache = TileCache()
        let tiles = [TileKey(x: -490, y: 153)]
        cache.merge([], tiles: tiles, layer: .freeWater, at: t0)
        let inner = BoundingBox(south: 38.3, west: -122.4, north: 38.4, east: -122.3)
        XCTAssertEqual(cache.missingTiles(covering: inner, layer: .freeWater, now: t0 + week, maxAge: week), [])
        XCTAssertEqual(cache.missingTiles(covering: inner, layer: .freeWater, now: t0 + week + 1, maxAge: week), tiles)
    }

    func testMergeReplacesOnlyThatLayerAndTile() {
        var cache = TileCache()
        let here = [TileKey(x: -490, y: 153)]
        let there = [TileKey(x: -489, y: 153)]
        cache.merge([spot("f1", .fountain), spot("f2", .fountain)], tiles: here, layer: .freeWater, at: t0)
        cache.merge([spot("f3", .fountain, 38.3, -122.2)], tiles: there, layer: .freeWater, at: t0)
        cache.merge([spot("b1", .buy)], tiles: here, layer: .buyWater, at: t0)
        XCTAssertEqual(Set(cache.spots.keys), ["f1", "f2", "f3", "b1"])

        // f2 was removed from OSM. Reloading free water here must not touch b1 or f3.
        cache.merge([spot("f1", .fountain)], tiles: here, layer: .freeWater, at: t0 + 60)
        XCTAssertEqual(Set(cache.spots.keys), ["f1", "f3", "b1"])
    }

    func testMergeKeepsOnlyKindsOfTheLayer() {
        var cache = TileCache()
        let here = [TileKey(x: -490, y: 153)]
        // The buy query can return a restaurant with free water: it belongs to the free layer.
        cache.merge([spot("b1", .buy), spot("r1", .business)], tiles: here, layer: .buyWater, at: t0)
        XCTAssertEqual(Set(cache.spots.keys), ["b1"])
        cache.merge([spot("r1", .business), spot("b2", .buy)], tiles: here, layer: .freeWater, at: t0)
        XCTAssertEqual(Set(cache.spots.keys), ["b1", "r1"])
    }

    func testMergeIgnoresSpotsOutsideTheTiles() {
        var cache = TileCache()
        cache.merge([spot("far", .fountain, 40, -100)], tiles: [TileKey(x: -490, y: 153)], layer: .freeWater, at: t0)
        XCTAssertTrue(cache.spots.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var cache = TileCache()
        let tiles = [TileKey(x: -490, y: 153)]
        cache.merge([spot("f1", .fountain)], tiles: tiles, layer: .freeWater, at: t0)
        cache.merge([spot("b1", .buy)], tiles: tiles, layer: .buyWater, at: t0)
        let decoded = try JSONDecoder().decode(TileCache.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(decoded.spots, cache.spots)
        XCTAssertEqual(decoded.missingTiles(covering: tiles[0].box, layer: .buyWater, now: t0, maxAge: week).count, 3)
    }
}

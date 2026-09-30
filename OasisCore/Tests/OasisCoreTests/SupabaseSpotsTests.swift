import XCTest
@testable import OasisCore

final class SupabaseSpotsTests: XCTestCase {
    func page() throws -> SupabaseSpotsAPI.Page {
        try SupabaseSpotsAPI.decode(Fixture.data("supabase-spots"))
    }

    func testDecodeRows() throws {
        let p = try page()
        XCTAssertEqual(p.rowCount, 5)
        XCTAssertFalse(p.isTruncated)
        // The unknown kind is skipped; a non-string tag drops the tags, not the row.
        XCTAssertEqual(p.spots.map(\.id), ["node/101", "way/202", "3f0c9a52-6b7e-4d1a-9c55-0a1b2c3d4e5f", "node/404"])

        let fountain = p.spots[0]
        XCTAssertEqual(fountain.source, .openStreetMap)
        XCTAssertEqual(fountain.kind, .fountain)
        XCTAssertEqual(fountain.coordinate, Coordinate(latitude: 39.7392, longitude: -104.9903))
        XCTAssertEqual(fountain.displayName, "Civic Center fountain")
        XCTAssertEqual(fountain.lastChecked, "2026-05-02")
        XCTAssertEqual(fountain.lastReport?.type, "working")
        XCTAssertEqual(fountain.lastReport?.date, SupabaseSpotsAPI.parseTimestamp("2026-09-29T15:04:05Z"))

        XCTAssertNil(p.spots[1].lastReport)
        XCTAssertEqual(p.spots[1].kind, .convenience)

        let community = p.spots[2]
        XCTAssertEqual(community.source, .community)
        XCTAssertNil(community.osmURL)
        XCTAssertEqual(community.displayName, "Trailhead tap")
        XCTAssertEqual(community.note, "Behind the restrooms")
        XCTAssertEqual(community.lastReport?.type, "not_working")

        XCTAssertEqual(p.spots[3].tags, [:])
        XCTAssertEqual(p.spots[3].kind, .tap)
    }

    func testVerificationStillUsesTags() throws {
        let now = Date(timeIntervalSince1970: 1_790_424_000) // 2026-09-26
        XCTAssertEqual(try page().spots[0].verification(asOf: now), .verified)
    }

    func testEmptyAndBadReplies() throws {
        XCTAssertEqual(try SupabaseSpotsAPI.decode(Data("[]".utf8)).spots, [])
        XCTAssertThrowsError(try SupabaseSpotsAPI.decode(Data(#"{"message":"Invalid box."}"#.utf8)))
    }

    func testTruncationFlag() throws {
        let row = #"{"source":"osm","id":"node/1","lat":1,"lon":2,"kind":"tap","tags":{}}"#
        let json = "[" + Array(repeating: row, count: SupabaseSpotsAPI.rowLimit).joined(separator: ",") + "]"
        XCTAssertTrue(try SupabaseSpotsAPI.decode(Data(json.utf8)).isTruncated)
    }

    func testTimestamps() throws {
        let base = try XCTUnwrap(SupabaseSpotsAPI.parseTimestamp("2026-09-29T15:04:05Z"))
        XCTAssertEqual(SupabaseSpotsAPI.parseTimestamp("2026-09-29T15:04:05.123456+00:00"), base)
        XCTAssertEqual(SupabaseSpotsAPI.parseTimestamp("2026-09-29 15:04:05+00"), base) // Postgres text format
        XCTAssertEqual(SupabaseSpotsAPI.parseTimestamp("2026-09-29T09:04:05-06:00"), base)
        XCTAssertNil(SupabaseSpotsAPI.parseTimestamp("yesterday"))
    }

    func testRequestBody() throws {
        let body = try SupabaseSpotsAPI.requestBody(
            box: BoundingBox(south: 39.5, west: -105.25, north: 40, east: -104.75), layers: [.buyWater, .freeWater])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["west"] as? Double, -105.25)
        XCTAssertEqual(object["south"] as? Double, 39.5)
        XCTAssertEqual(object["east"] as? Double, -104.75)
        XCTAssertEqual(object["north"] as? Double, 40)
        XCTAssertEqual(object["layers"] as? [String], ["freeWater", "buyWater"])
        let buyOnly = try JSONSerialization.jsonObject(
            with: SupabaseSpotsAPI.requestBody(box: BoundingBox(south: 0, west: 0, north: 1, east: 1), layers: [.buyWater])) as? [String: Any]
        XCTAssertEqual(buyOnly?["layers"] as? [String], ["buyWater"])
    }

    func testChunks() {
        let small = BoundingBox(south: 39.5, west: -105, north: 39.75, east: -104.75)
        XCTAssertEqual(SupabaseSpotsAPI.chunks(of: small), [small])

        // A 1.25° x 0.75° box becomes 3 x 2 pieces that cover it exactly.
        let big = BoundingBox(south: 39.25, west: -105.5, north: 40, east: -104.25)
        let pieces = SupabaseSpotsAPI.chunks(of: big)
        XCTAssertEqual(pieces.count, 6)
        for p in pieces {
            XCTAssertLessThanOrEqual(p.longitudeSpan, 0.5 + 1e-9)
            XCTAssertLessThanOrEqual(p.latitudeSpan, 0.5 + 1e-9)
        }
        XCTAssertEqual(pieces.map(\.west).min(), big.west)
        XCTAssertEqual(pieces.map(\.east).max(), big.east)
        XCTAssertEqual(pieces.map(\.south).min(), big.south)
        XCTAssertEqual(pieces.map(\.north).max(), big.north)
        let area = pieces.map { $0.longitudeSpan * $0.latitudeSpan }.reduce(0, +)
        XCTAssertEqual(area, big.longitudeSpan * big.latitudeSpan, accuracy: 1e-9)
    }

    func testCoverage() {
        let denver = BoundingBox(center: Coordinate(latitude: 39.74, longitude: -104.99), latitudeDelta: 0.2, longitudeDelta: 0.2)
        let napa = BoundingBox(center: Coordinate(latitude: 38.3, longitude: -122.29), latitudeDelta: 0.2, longitudeDelta: 0.2)
        XCTAssertTrue(SyncRegion.coverage(includes: denver))
        XCTAssertFalse(SyncRegion.coverage(includes: napa))
        XCTAssertTrue(BoundingBox(south: 0, west: 0, north: 1, east: 1).intersects(BoundingBox(south: 1, west: 1, north: 2, east: 2)))
        XCTAssertFalse(BoundingBox(south: 0, west: 0, north: 1, east: 1).intersects(BoundingBox(south: 1.1, west: 0, north: 2, east: 1)))
    }

    func testOldCacheWithoutLastReportDecodes() throws {
        let json = #"{"id":"node/9","source":"openStreetMap","latitude":38.1,"longitude":-122.1,"kind":"tap","tags":{}}"#
        XCTAssertNil(try JSONDecoder().decode(WaterSpot.self, from: Data(json.utf8)).lastReport)
    }
}

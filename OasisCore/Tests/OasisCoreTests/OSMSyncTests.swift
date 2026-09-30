import XCTest
@testable import OasisCore

final class OSMSyncTests: XCTestCase {
    let synced = Date(timeIntervalSince1970: 1_790_424_000) // 2026-09-26 12:00 UTC

    func testColoradoTiles() {
        let r = SyncRegion.colorado
        let tiles = r.tiles()
        // 8 columns (110 W ... 103 W) x 6 rows (36 N ... 41 N).
        XCTAssertEqual(tiles.count, 48)
        for t in tiles {
            XCTAssertLessThanOrEqual(t.longitudeSpan, 1 + 1e-9)
            XCTAssertLessThanOrEqual(t.latitudeSpan, 1 + 1e-9)
            XCTAssertGreaterThan(t.longitudeSpan, 0)
            XCTAssertGreaterThan(t.latitudeSpan, 0)
            XCTAssertTrue(r.bounds.contains(Coordinate(latitude: t.south, longitude: t.west)))
            XCTAssertTrue(r.bounds.contains(Coordinate(latitude: t.north, longitude: t.east)))
        }
        // Denver and Grand Junction are each in exactly one tile interior.
        for city in [Coordinate(latitude: 39.74, longitude: -104.99), Coordinate(latitude: 39.06, longitude: -108.55)] {
            XCTAssertEqual(tiles.filter { $0.contains(city) }.count, 1)
        }
        XCTAssertEqual(tiles.first, BoundingBox(south: 36.95, west: -109.10, north: 37, east: -109))
    }

    func testColoradoSyncTiles() {
        let tiles = SyncRegion.colorado.tiles(size: OSMSync.tileSize)
        // 15 columns (109.5 W ... 102.5 W) x 10 rows (36.5 N ... 41.0 N), clipped to the region.
        XCTAssertEqual(tiles.count, 150)
        XCTAssertTrue(tiles.allSatisfy { $0.longitudeSpan <= 0.5 + 1e-9 && $0.latitudeSpan <= 0.5 + 1e-9 })
        let area = tiles.map { $0.longitudeSpan * $0.latitudeSpan }.reduce(0, +)
        let b = SyncRegion.colorado.bounds
        XCTAssertEqual(area, b.longitudeSpan * b.latitudeSpan, accuracy: 1e-9)
    }

    func testRegionLookup() {
        XCTAssertEqual(SyncRegion.named("Colorado"), .colorado)
        XCTAssertNil(SyncRegion.named("atlantis"))
    }

    func testQueryHasBothLayersAndMeta() {
        let q = OSMSync.query(for: BoundingBox(south: 39, west: -105, north: 40, east: -104))
        XCTAssertTrue(q.hasPrefix("[out:json][timeout:120];"))
        XCTAssertTrue(q.contains(#"nwr["amenity"="drinking_water"]"#))
        XCTAssertTrue(q.contains(#"nwr["shop"~"#))
        XCTAssertTrue(q.hasSuffix("out center meta;"))
    }

    func testRowsFromFixture() throws {
        let response = try OverpassResponse.decode(Fixture.data("overpass-sample"))
        let rows = try OSMSync.rows(from: response, syncedAt: synced)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.osmID, $0) })

        // Every element with a position, hidden ones included. The relation has none.
        XCTAssertEqual(rows.count, 13)
        XCTAssertNil(byID["relation/3001"])

        let fountain = try XCTUnwrap(byID["node/1001"])
        XCTAssertEqual(fountain.kind, "fountain")
        XCTAssertNil(fountain.hiddenReason)
        XCTAssertEqual(fountain.geom, "SRID=4326;POINT(-122.2869000 38.2975000)")
        XCTAssertEqual(fountain.surveyDate, "2025-05-30")
        XCTAssertEqual(fountain.osmVersion, 3)
        XCTAssertEqual(fountain.osmEditedAt, "2025-06-01T12:00:00Z")
        XCTAssertEqual(fountain.syncedAt, "2026-09-26T12:00:00Z")

        XCTAssertEqual(byID["way/2001"]?.geom, "SRID=4326;POINT(-122.4700000 38.5025000)")
        XCTAssertEqual(byID["node/1007"]?.kind, "restaurant")
        XCTAssertEqual(byID["node/1009"]?.kind, "other")

        XCTAssertEqual(byID["node/1006"]?.hiddenReason, "access=private")
        XCTAssertEqual(byID["node/1008"]?.hiddenReason, "drinking_water=no")
        XCTAssertEqual(byID["node/1011"]?.hiddenReason, "operational_status=broken")
        for row in rows {
            XCTAssertTrue((row.kind == nil) != (row.hiddenReason == nil), row.osmID)
        }
    }

    func testIncompleteResponseThrows() throws {
        let response = try OverpassResponse.decode(Fixture.data("overpass-timeout"))
        XCTAssertThrowsError(try OSMSync.rows(from: response, syncedAt: synced))
    }

    func testDuplicateElementsAppearOnce() throws {
        let json = #"{"elements":[{"type":"node","id":1,"lat":1,"lon":2,"tags":{"amenity":"drinking_water"}},{"type":"node","id":1,"lat":1,"lon":2,"tags":{"amenity":"drinking_water"}}]}"#
        let rows = try OSMSync.rows(from: OverpassResponse.decode(Data(json.utf8)), syncedAt: synced)
        XCTAssertEqual(rows.map(\.osmID), ["node/1"])
    }

    func testRowJSONMatchesTableColumns() throws {
        let json = #"{"elements":[{"type":"node","id":7,"lat":39.7,"lon":-105,"tags":{"amenity":"drinking_water"}}]}"#
        let row = try XCTUnwrap(OSMSync.rows(from: OverpassResponse.decode(Data(json.utf8)), syncedAt: synced).first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["osm_id", "geom", "kind", "hidden_reason", "tags", "survey_date",
                                          "osm_version", "osm_edited_at", "synced_at", "removed_at"])
        XCTAssertTrue(object["removed_at"] is NSNull, "removed_at must be an explicit null")
        XCTAssertEqual(object["kind"] as? String, "fountain")
        XCTAssertEqual(object["geom"] as? String, "SRID=4326;POINT(-105.0000000 39.7000000)")
    }

    func testHiddenReasonText() {
        XCTAssertEqual(OSMSync.hiddenReason(.notDrinkable), "drinking_water=no")
        XCTAssertEqual(OSMSync.hiddenReason(.restrictedAccess("no")), "access=no")
        XCTAssertEqual(OSMSync.hiddenReason(.problem("disused=yes")), "disused=yes")
    }
}

import XCTest
@testable import OasisCore

final class OverpassResponseTests: XCTestCase {
    func testParsesSampleFixture() throws {
        let response = try OverpassResponse.decode(Fixture.data("overpass-sample"))
        XCTAssertEqual(response.elements.count, 11)
        XCTAssertFalse(response.isIncomplete)

        let spots = try response.waterSpots()
        let byID = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0) })

        XCTAssertEqual(byID["node/1001"]?.kind, .fountain)
        XCTAssertEqual(byID["node/1002"]?.kind, .tap)
        XCTAssertEqual(byID["node/1003"]?.kind, .tap)
        XCTAssertEqual(byID["node/1004"]?.kind, .business)
        XCTAssertEqual(byID["way/2001"]?.kind, .business)
        XCTAssertEqual(byID["node/1005"]?.kind, .other)
        // A node with no tags is kept as "other", same as the explorer.
        XCTAssertEqual(byID["node/1009"]?.kind, .other)

        // Excluded: private, customers-only, not drinkable. Dropped: relation with no center.
        for id in ["node/1006", "node/1007", "node/1008", "relation/3001"] {
            XCTAssertNil(byID[id], id)
        }
        XCTAssertEqual(spots.count, 7)
    }

    func testWayUsesCenter() throws {
        let spots = try OverpassResponse.decode(Fixture.data("overpass-sample")).waterSpots()
        let way = try XCTUnwrap(spots.first { $0.id == "way/2001" })
        XCTAssertEqual(way.coordinate, Coordinate(latitude: 38.5025, longitude: -122.47))
    }

    func testMetaFields() throws {
        let response = try OverpassResponse.decode(Fixture.data("overpass-sample"))
        let el = try XCTUnwrap(response.elements.first { $0.id == 1001 })
        XCTAssertEqual(el.timestamp, "2025-06-01T12:00:00Z")
        XCTAssertEqual(el.version, 3)
        XCTAssertEqual(el.user, "mapper1")
        XCTAssertNil(response.elements.first { $0.id == 1002 }?.timestamp)
    }

    func testTimeoutRemarkThrows() throws {
        let response = try OverpassResponse.decode(Fixture.data("overpass-timeout"))
        XCTAssertTrue(response.isIncomplete)
        XCTAssertThrowsError(try response.waterSpots()) { error in
            guard case OverpassParseError.incomplete(let remark) = error else {
                return XCTFail("Wrong error: \(error)")
            }
            XCTAssertTrue(remark.contains("timed out"))
        }
    }

    func testEmptyResponse() throws {
        let response = try OverpassResponse.decode(Data(#"{"elements":[]}"#.utf8))
        XCTAssertEqual(try response.waterSpots(), [])
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try OverpassResponse.decode(Data("<html>busy</html>".utf8)))
    }
}

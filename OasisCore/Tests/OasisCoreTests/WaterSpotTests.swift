import XCTest
@testable import OasisCore

final class WaterSpotTests: XCTestCase {
    func testInitFromOSM() throws {
        let spot = try XCTUnwrap(WaterSpot(osmType: "node", osmID: 42, latitude: 38.3, longitude: -122.3,
                                           tags: ["amenity": "drinking_water", "name": "Park fountain"]))
        XCTAssertEqual(spot.id, "node/42")
        XCTAssertEqual(spot.source, .openStreetMap)
        XCTAssertEqual(spot.kind, .fountain)
        XCTAssertEqual(spot.coordinate, Coordinate(latitude: 38.3, longitude: -122.3))
        XCTAssertEqual(spot.displayName, "Park fountain")
        XCTAssertEqual(spot.osmURL?.absoluteString, "https://www.openstreetmap.org/node/42")
    }

    func testInitRejectsExcluded() {
        XCTAssertNil(WaterSpot(osmType: "node", osmID: 1, latitude: 0, longitude: 0,
                               tags: ["amenity": "drinking_water", "access": "private"]))
        XCTAssertNil(WaterSpot(osmType: "node", osmID: 1, latitude: 0, longitude: 0,
                               tags: ["amenity": "water_point", "drinking_water": "no"]))
    }

    func testDerivedFields() throws {
        let spot = try XCTUnwrap(WaterSpot(osmType: "node", osmID: 1, latitude: 0, longitude: 0, tags: [
            "man_made": "water_tap", "bottle": "yes", "seasonal": "summer", "fee": "no",
            "opening_hours": "24/7", "survey:date": "2024-04-01", "note": "Turn the handle hard",
        ]))
        XCTAssertEqual(spot.displayName, "Tap or spigot")
        XCTAssertTrue(spot.hasBottleFiller)
        XCTAssertEqual(spot.seasonal, "summer")
        XCTAssertEqual(spot.fee, "no")
        XCTAssertEqual(spot.openingHours, "24/7")
        XCTAssertEqual(spot.lastChecked, "2024-04-01")
        XCTAssertEqual(spot.note, "Turn the handle hard")
    }

    func testSeasonalNoMeansAllYear() throws {
        let spot = try XCTUnwrap(WaterSpot(osmType: "node", osmID: 1, latitude: 0, longitude: 0,
                                           tags: ["amenity": "drinking_water", "seasonal": "no"]))
        XCTAssertNil(spot.seasonal)
    }

    func testCheckDateWinsOverSurveyDate() throws {
        let spot = try XCTUnwrap(WaterSpot(osmType: "node", osmID: 1, latitude: 0, longitude: 0, tags: [
            "amenity": "drinking_water", "check_date": "2025-01-01", "survey:date": "2020-01-01",
        ]))
        XCTAssertEqual(spot.lastChecked, "2025-01-01")
    }

    func testCommunitySpotHasNoOSMURL() {
        let spot = WaterSpot(id: "c1", source: .community, latitude: 0, longitude: 0, kind: .tap, tags: [:])
        XCTAssertNil(spot.osmURL)
    }

    func testCodableRoundTrip() throws {
        let spot = try XCTUnwrap(WaterSpot(osmType: "way", osmID: 7, latitude: 1.5, longitude: -2.5,
                                           tags: ["shop": "bakery", "drinking_water": "yes"]))
        let decoded = try JSONDecoder().decode(WaterSpot.self, from: JSONEncoder().encode(spot))
        XCTAssertEqual(decoded, spot)
    }

    func testDecodesPhase1CacheFormat() throws {
        // The shape the phase 1 app wrote to its disk cache.
        let json = #"{"id":"node/9","source":"openStreetMap","latitude":38.1,"longitude":-122.1,"kind":"tap","tags":{"man_made":"water_tap"}}"#
        let spot = try JSONDecoder().decode(WaterSpot.self, from: Data(json.utf8))
        XCTAssertEqual(spot.id, "node/9")
        XCTAssertEqual(spot.kind, .tap)
    }
}

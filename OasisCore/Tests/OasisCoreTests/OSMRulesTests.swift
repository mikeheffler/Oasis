import XCTest
@testable import OasisCore

final class OSMRulesTests: XCTestCase {
    func testFountain() {
        XCTAssertEqual(OSMRules.classify(["amenity": "drinking_water"]), .fountain)
    }

    func testTapFromManMade() {
        XCTAssertEqual(OSMRules.classify(["man_made": "water_tap", "drinking_water": "yes"]), .tap)
    }

    func testTapFromWaterPoint() {
        XCTAssertEqual(OSMRules.classify(["amenity": "water_point"]), .tap)
    }

    func testRefillSchemeIsBusiness() {
        XCTAssertEqual(OSMRules.classify(["drinking_water:refill": "yes"]), .business)
    }

    func testShopIsBusiness() {
        XCTAssertEqual(OSMRules.classify(["shop": "convenience", "drinking_water": "yes"]), .business)
    }

    func testBusinessAmenities() {
        for amenity in OSMRules.businessAmenities {
            XCTAssertEqual(OSMRules.classify(["amenity": amenity]), .business, amenity)
        }
    }

    func testOther() {
        XCTAssertEqual(OSMRules.classify(["amenity": "toilets", "drinking_water": "yes"]), .other)
        XCTAssertEqual(OSMRules.classify([:]), .other)
    }

    func testRuleOrder() {
        // A fountain inside a cafe is still a fountain.
        XCTAssertEqual(OSMRules.classify(["amenity": "drinking_water", "shop": "yes"]), .fountain)
        // A tap at a shop is still a tap.
        XCTAssertEqual(OSMRules.classify(["man_made": "water_tap", "shop": "bicycle"]), .tap)
    }

    func testExclusions() {
        XCTAssertEqual(OSMRules.exclusion(for: ["drinking_water": "no"]), .notDrinkable)
        XCTAssertEqual(OSMRules.exclusion(for: ["access": "private"]), .restrictedAccess("private"))
        XCTAssertEqual(OSMRules.exclusion(for: ["access": "no"]), .restrictedAccess("no"))
        XCTAssertEqual(OSMRules.exclusion(for: ["access": "customers"]), .restrictedAccess("customers"))
    }

    func testAllowedAccessValues() {
        for access in ["yes", "public", "permissive", "destination"] {
            XCTAssertNil(OSMRules.exclusion(for: ["amenity": "drinking_water", "access": access]), access)
        }
        XCTAssertNil(OSMRules.exclusion(for: ["amenity": "drinking_water"]))
    }
}

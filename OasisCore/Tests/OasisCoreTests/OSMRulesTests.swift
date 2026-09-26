import XCTest
@testable import OasisCore

final class OSMRulesTests: XCTestCase {
    func kind(_ tags: [String: String]) -> SpotKind? {
        if case .show(let k) = OSMRules.evaluate(tags) { return k }
        return nil
    }

    // MARK: Free water

    func testFountain() {
        XCTAssertEqual(kind(["amenity": "drinking_water"]), .fountain)
    }

    func testTapFromManMade() {
        XCTAssertEqual(kind(["man_made": "water_tap", "drinking_water": "yes"]), .tap)
    }

    func testTapFromWaterPoint() {
        XCTAssertEqual(kind(["amenity": "water_point"]), .tap)
    }

    func testRefillSchemeIsFreeBusiness() {
        XCTAssertEqual(kind(["drinking_water:refill": "yes"]), .business)
        XCTAssertEqual(kind(["shop": "convenience", "drinking_water:refill": "yes"]), .business)
    }

    func testBusinessWithDrinkingWaterIsFree() {
        XCTAssertEqual(kind(["shop": "bicycle", "drinking_water": "yes"]), .business)
        for amenity in OSMRules.freeWaterBusinessAmenities {
            XCTAssertEqual(kind(["amenity": amenity, "drinking_water": "yes"]), .business, amenity)
        }
    }

    func testOther() {
        XCTAssertEqual(kind(["amenity": "toilets", "drinking_water": "yes"]), .other)
        XCTAssertEqual(kind([:]), .other)
    }

    func testRuleOrder() {
        // A fountain inside a cafe is still a fountain.
        XCTAssertEqual(kind(["amenity": "drinking_water", "shop": "convenience"]), .fountain)
        // A tap at a shop is still a tap.
        XCTAssertEqual(kind(["man_made": "water_tap", "shop": "bicycle"]), .tap)
    }

    // MARK: Buy water

    func testBuyCategories() {
        for shop in ["convenience", "general", "kiosk"] {
            XCTAssertEqual(kind(["shop": shop]), .convenience, shop)
        }
        XCTAssertEqual(kind(["amenity": "fuel"]), .convenience)
        XCTAssertEqual(kind(["shop": "supermarket"]), .grocery)
        for amenity in ["restaurant", "cafe", "fast_food"] {
            XCTAssertEqual(kind(["amenity": amenity]), .restaurant, amenity)
        }
    }

    func testBuyPlaceWithFreeWaterIsFreeBusiness() {
        XCTAssertEqual(kind(["shop": "supermarket", "drinking_water": "yes"]), .business)
        XCTAssertEqual(kind(["amenity": "fuel", "drinking_water:refill": "yes"]), .business)
    }

    func testBuyCategoryOrder() {
        // A gas station with a shop is convenience. A supermarket with a cafe is grocery.
        XCTAssertEqual(kind(["amenity": "fuel", "shop": "convenience"]), .convenience)
        XCTAssertEqual(kind(["shop": "supermarket", "amenity": "cafe"]), .grocery)
        XCTAssertEqual(kind(["shop": "kiosk", "amenity": "fast_food"]), .convenience)
    }

    func testQuerySetsCoverAllCategories() {
        XCTAssertEqual(OSMRules.buyShops, ["convenience", "general", "kiosk", "supermarket"])
        XCTAssertEqual(OSMRules.buyAmenities, ["fuel", "restaurant", "cafe", "fast_food"])
    }

    func testVendingMachines() {
        XCTAssertEqual(kind(["amenity": "vending_machine", "vending": "drinks"]), .convenience)
        XCTAssertEqual(kind(["amenity": "vending_machine", "vending": "food; drinks"]), .convenience)
        XCTAssertEqual(kind(["amenity": "vending_machine", "vending": "water"]), .convenience)
        XCTAssertEqual(kind(["amenity": "vending_machine", "vending": "parking_tickets"]), .other)
        XCTAssertEqual(kind(["amenity": "vending_machine"]), .other)
        // "drinks" must be a whole list item.
        XCTAssertEqual(kind(["amenity": "vending_machine", "vending": "soft_drinks_cups"]), .other)
    }

    func testNotABuyPlace() {
        XCTAssertEqual(kind(["shop": "clothes"]), .other)
        XCTAssertEqual(kind(["amenity": "pub"]), .other)
    }

    func testBuyPlaceKeepsCustomersOnlyAndNoTapWater() {
        XCTAssertEqual(kind(["amenity": "restaurant", "drinking_water": "yes", "access": "customers"]), .restaurant)
        XCTAssertEqual(kind(["shop": "convenience", "drinking_water": "no"]), .convenience)
    }

    func testIsFree() {
        XCTAssertEqual(SpotKind.allCases.filter(\.isFree), [.fountain, .tap, .business, .other])
        XCTAssertEqual(SpotKind.allCases.filter { !$0.isFree }, SpotKind.buyKinds)
    }

    // MARK: Hidden

    func testNotDrinkable() {
        XCTAssertEqual(OSMRules.evaluate(["amenity": "water_point", "drinking_water": "no"]), .hide(.notDrinkable))
    }

    func testRestrictedAccess() {
        XCTAssertEqual(OSMRules.evaluate(["amenity": "drinking_water", "access": "private"]),
                       .hide(.restrictedAccess("private")))
        XCTAssertEqual(OSMRules.evaluate(["amenity": "drinking_water", "access": "no"]),
                       .hide(.restrictedAccess("no")))
        XCTAssertEqual(OSMRules.evaluate(["amenity": "drinking_water", "access": "customers"]),
                       .hide(.restrictedAccess("customers")))
        // Private stays hidden even for a store.
        XCTAssertEqual(OSMRules.evaluate(["shop": "convenience", "access": "private"]),
                       .hide(.restrictedAccess("private")))
    }

    func testAllowedAccessValues() {
        for access in ["yes", "public", "permissive", "destination"] {
            XCTAssertEqual(kind(["amenity": "drinking_water", "access": access]), .fountain, access)
        }
    }

    func testProblemTags() {
        for status in OSMRules.problemStatuses {
            XCTAssertEqual(OSMRules.evaluate(["amenity": "drinking_water", "operational_status": status]),
                           .hide(.problem("operational_status=\(status)")), status)
        }
        XCTAssertEqual(OSMRules.evaluate(["amenity": "drinking_water", "disused": "yes"]),
                       .hide(.problem("disused=yes")))
        XCTAssertEqual(OSMRules.evaluate(["shop": "convenience", "abandoned": "yes"]),
                       .hide(.problem("abandoned=yes")))
    }

    func testProblemTagsThatStillShow() {
        XCTAssertEqual(kind(["amenity": "drinking_water", "operational_status": "operational"]), .fountain)
        XCTAssertEqual(kind(["amenity": "drinking_water", "disused": "no"]), .fountain)
    }
}

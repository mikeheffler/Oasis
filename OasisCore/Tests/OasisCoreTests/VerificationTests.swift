import XCTest
@testable import OasisCore

final class VerificationTests: XCTestCase {
    /// 2026-09-26 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_790_424_000)

    func date(_ text: String) -> Date? { VerificationRules.parseDate(text) }

    func testParseFormats() throws {
        let utc = VerificationRules.utc
        let d = try XCTUnwrap(date("2025-06-15"))
        XCTAssertEqual(utc.dateComponents([.year, .month, .day], from: d), DateComponents(year: 2025, month: 6, day: 15))
        let m = try XCTUnwrap(date("2025-06"))
        XCTAssertEqual(utc.dateComponents([.year, .month, .day], from: m), DateComponents(year: 2025, month: 6, day: 1))
        let y = try XCTUnwrap(date("2025"))
        XCTAssertEqual(utc.dateComponents([.year, .month, .day], from: y), DateComponents(year: 2025, month: 1, day: 1))
        XCTAssertEqual(date("2025-06-15T08:30:00Z"), d)
        XCTAssertEqual(date(" 2025-06-15 "), d)
    }

    func testParseRejectsBadDates() {
        for bad in ["", "yes", "2025-6-1", "25-06-01", "2025-13", "2025-02-30", "2025/06/15", "June 2025"] {
            XCTAssertNil(date(bad), bad)
        }
    }

    func testNowSanity() throws {
        XCTAssertEqual(VerificationRules.utc.dateComponents([.year, .month, .day], from: now),
                       DateComponents(year: 2026, month: 9, day: 26))
    }

    func testRecentCheckDateIsVerified() {
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2025-05-01"], asOf: now), .verified)
        XCTAssertEqual(VerificationRules.verification(for: ["survey:date": "2026-09"], asOf: now), .verified)
    }

    func testWindowEdge() {
        // The window is 24 months: 2024-09-26 is inside, 2024-09-25 is outside.
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2024-09-26"], asOf: now), .verified)
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2024-09-25"], asOf: now), .unverified)
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2025-09-25"], asOf: now, windowMonths: 12),
                       .unverified)
    }

    func testMonthAndYearUseFirstDay() {
        // "2024-09" means 2024-09-01, which is outside the window.
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2024-09"], asOf: now), .unverified)
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2025"], asOf: now), .verified)
    }

    func testNoDateOrOldDateIsUnverified() {
        XCTAssertEqual(VerificationRules.verification(for: [:], asOf: now), .unverified)
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2019-01-01"], asOf: now), .unverified)
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "unknown"], asOf: now), .unverified)
    }

    func testLatestOfBothTagsAndLists() {
        XCTAssertEqual(VerificationRules.verification(
            for: ["check_date": "2018-01-01", "survey:date": "2026-01-01"], asOf: now), .verified)
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2018-01-01;2026-03-01"], asOf: now), .verified)
    }

    func testFutureDateIsIgnored() {
        XCTAssertEqual(VerificationRules.verification(for: ["check_date": "2062-09-26"], asOf: now), .unverified)
        XCTAssertEqual(VerificationRules.verification(
            for: ["check_date": "2062-09-26", "survey:date": "2026-01-01"], asOf: now), .verified)
    }

    func testWaterSpotVerification() throws {
        let spot = try XCTUnwrap(WaterSpot(osmType: "node", osmID: 1, latitude: 0, longitude: 0,
                                           tags: ["amenity": "drinking_water", "check_date": "2026-06-01"]))
        XCTAssertEqual(spot.verification(asOf: now), .verified)
    }
}

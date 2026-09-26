import XCTest
@testable import OasisCore

final class OverpassQueryTests: XCTestCase {
    func testBoxQuery() {
        let q = OverpassQuery.waterPoints(in: .box(BoundingBox(south: 38.25, west: -122.5, north: 38.5, east: -122.25)))
        XCTAssertEqual(q, """
        [out:json][timeout:25];
        (
          nwr["amenity"="drinking_water"]["drinking_water"!="no"](38.250000,-122.500000,38.500000,-122.250000);
          nwr["amenity"="water_point"]["drinking_water"!="no"](38.250000,-122.500000,38.500000,-122.250000);
          nwr["drinking_water"="yes"](38.250000,-122.500000,38.500000,-122.250000);
          nwr["drinking_water:refill"="yes"](38.250000,-122.500000,38.500000,-122.250000);
        );
        out center tags;
        """)
    }

    func testAroundQueryWithMeta() {
        let path = [Coordinate(latitude: 38.297512, longitude: -122.286934),
                    Coordinate(latitude: 38.5, longitude: -122.47)]
        let q = OverpassQuery.waterPoints(in: .around(radius: 925.4, path: path), timeout: 120, output: .meta)
        XCTAssertTrue(q.hasPrefix("[out:json][timeout:120];"))
        XCTAssertTrue(q.contains(#"nwr["drinking_water"="yes"](around:925,38.29751,-122.28693,38.50000,-122.47000);"#))
        XCTAssertTrue(q.hasSuffix("out center meta;"))
    }

    func testNumbersNeverUseExponent() {
        XCTAssertEqual(OverpassQuery.fmt(0.00001), "0.000010")
        XCTAssertEqual(OverpassQuery.fmt(-0.0000001), "-0.000000")
    }

    func testFormBodyEncoding() throws {
        let body = OverpassQuery.formBody(for: #"a="b" [x];é&+"#)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertEqual(text, "data=a%3D%22b%22%20%5Bx%5D%3B%C3%A9%26%2B")
    }

    func testFormBodyRoundTrip() throws {
        let q = OverpassQuery.waterPoints(in: .box(BoundingBox(south: 1, west: 2, north: 3, east: 4)))
        let text = try XCTUnwrap(String(data: OverpassQuery.formBody(for: q), encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("data="))
        XCTAssertEqual(String(text.dropFirst(5)).removingPercentEncoding, q)
        XCTAssertFalse(text.dropFirst(5).contains("="))
        XCTAssertFalse(text.dropFirst(5).contains("&"))
    }
}

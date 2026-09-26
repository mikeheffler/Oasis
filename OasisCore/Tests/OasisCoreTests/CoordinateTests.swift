import XCTest
@testable import OasisCore

final class CoordinateTests: XCTestCase {
    func testZeroDistance() {
        let c = Coordinate(latitude: 38.3, longitude: -122.3)
        XCTAssertEqual(c.distance(to: c), 0)
    }

    func testOneDegreeOfLatitude() {
        // 2πR / 360 with R = 6,371,008.8 m.
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 1, longitude: 0)
        XCTAssertEqual(a.distance(to: b), 111_195.08, accuracy: 0.1)
    }

    func testSymmetric() {
        let a = Coordinate(latitude: 38.2975, longitude: -122.2869)
        let b = Coordinate(latitude: 38.5025, longitude: -122.47)
        XCTAssertEqual(a.distance(to: b), b.distance(to: a), accuracy: 1e-9)
    }

    func testKnownCityPair() {
        // Napa to St. Helena. Reference value from an independent haversine calculation.
        let napa = Coordinate(latitude: 38.2975, longitude: -122.2869)
        let stHelena = Coordinate(latitude: 38.5052, longitude: -122.4703)
        XCTAssertEqual(napa.distance(to: stHelena), 28_085.64, accuracy: 0.01)
    }
}

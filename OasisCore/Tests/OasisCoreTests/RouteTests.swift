import XCTest
@testable import OasisCore

/// Routes along the equator, so the expected numbers are easy to check.
final class RouteTests: XCTestCase {
    /// Haversine length of 0.1° of longitude on the equator.
    let tenth = 11_119.508

    func makeRoute() throws -> Route {
        try XCTUnwrap(Route(points: [
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 0.1),
            Coordinate(latitude: 0, longitude: 0.2),
        ], name: "Test"))
    }

    func testNeedsTwoPoints() {
        XCTAssertNil(Route(points: []))
        XCTAssertNil(Route(points: [Coordinate(latitude: 0, longitude: 0)]))
    }

    func testLengthAndBounds() throws {
        let r = try makeRoute()
        XCTAssertEqual(r.length, 2 * tenth, accuracy: 0.01)
        XCTAssertEqual(r.cumulative[1], tenth, accuracy: 0.01)
        XCTAssertEqual(r.bounds, BoundingBox(south: 0, west: 0, north: 0, east: 0.2))
        XCTAssertEqual(r.name, "Test")
    }

    func testProjectBesideRoute() throws {
        let p = try makeRoute().project(Coordinate(latitude: 0.001, longitude: 0.05))
        XCTAssertEqual(p.distanceFromRoute, 110.54, accuracy: 0.01)
        XCTAssertEqual(p.distanceAlong, tenth / 2, accuracy: 0.01)
    }

    func testProjectPastEndClampsToEnd() throws {
        let r = try makeRoute()
        let p = r.project(Coordinate(latitude: 0, longitude: 0.205))
        XCTAssertEqual(p.distanceAlong, r.length, accuracy: 0.01)
        XCTAssertEqual(p.distanceFromRoute, 0.005 * 111_320, accuracy: 0.01)
    }

    func testPointAtDistance() throws {
        let r = try makeRoute()
        let mid = r.point(atDistance: tenth * 1.5)
        XCTAssertEqual(mid.longitude, 0.15, accuracy: 1e-9)
        XCTAssertEqual(mid.latitude, 0, accuracy: 1e-12)
        XCTAssertEqual(r.point(atDistance: -5), r.points.first)
        XCTAssertEqual(r.point(atDistance: 1e9), r.points.last)
    }

    func testSlice() throws {
        let s = try makeRoute().slice(from: tenth / 2, to: tenth * 1.5)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].longitude, 0.05, accuracy: 1e-9)
        XCTAssertEqual(s[1], Coordinate(latitude: 0, longitude: 0.1))
        XCTAssertEqual(s[2].longitude, 0.15, accuracy: 1e-9)
    }

    func testSampledKeepsEndsAndSpacing() throws {
        // About 11.1 km with a point every 11 m.
        let points = (0...1000).map { Coordinate(latitude: 0, longitude: Double($0) * 0.0001) }
        let r = try XCTUnwrap(Route(points: points))

        let s = r.sampled(minSpacing: 400)
        XCTAssertEqual(s.first, points.first)
        XCTAssertEqual(s.last, points.last)
        for (a, b) in zip(s, s.dropFirst()).dropLast() {
            XCTAssertGreaterThanOrEqual(a.distance(to: b), 400)
        }
        // Every 36th point (400.3 m): indices 36...972 is 27 points, plus the first and last.
        XCTAssertEqual(s.count, 29)

        let few = r.sampled(minSpacing: 400, maxPoints: 10)
        XCTAssertLessThanOrEqual(few.count, 10)
        XCTAssertEqual(few.first, points.first)
        XCTAssertEqual(few.last, points.last)
    }

    func testSampledShortRoute() throws {
        let r = try makeRoute()
        XCTAssertEqual(r.sampled(minSpacing: 50_000), [r.points[0], r.points[2]])
    }
}

import XCTest
@testable import OasisCore

final class RouteAnalysisTests: XCTestCase {
    let tenth = 11_119.508
    let halfMile = 0.5 * Geo.metersPerMile

    func spot(_ id: String, _ kind: SpotKind, _ lat: Double, _ lon: Double) -> WaterSpot {
        WaterSpot(id: id, source: .openStreetMap, latitude: lat, longitude: lon, kind: kind, tags: [:])
    }

    func makeRoute() throws -> Route {
        try XCTUnwrap(Route(points: [Coordinate(latitude: 0, longitude: 0),
                                     Coordinate(latitude: 0, longitude: 0.2)]))
    }

    var spots: [WaterSpot] {
        [
            spot("A", .fountain, 0.001, 0.05),     // 111 m off, at 5.56 km
            spot("B", .tap, -0.002, 0.15),         // 221 m off, at 16.68 km
            spot("C", .business, 0.01, 0.10),      // 1,105 m off: outside the buffer
            spot("D", .business, 0.003, 0.02),     // 332 m off, at 2.22 km
            spot("E", .fountain, 5, 5),            // far away
        ]
    }

    func testStopsSortedAlongRoute() throws {
        let a = RouteAnalysis(route: try makeRoute(), spots: spots, bufferMeters: halfMile)
        XCTAssertEqual(a.stops.map(\.spot.id), ["D", "A", "B"])
        XCTAssertEqual(a.stops[1].distanceAlong, tenth / 2, accuracy: 0.01)
        XCTAssertEqual(a.stops[1].distanceFromRoute, 110.54, accuracy: 0.01)
    }

    func testGapsCoverWholeRoute() throws {
        let route = try makeRoute()
        let a = RouteAnalysis(route: route, spots: spots, bufferMeters: halfMile)
        XCTAssertEqual(a.gaps.count, 4)
        XCTAssertEqual(a.gaps.first?.start, 0)
        XCTAssertEqual(a.gaps.last?.end, route.length)
        XCTAssertEqual(a.gaps.map(\.length).reduce(0, +), route.length, accuracy: 1e-6)
    }

    func testLongestGaps() throws {
        let a = RouteAnalysis(route: try makeRoute(), spots: spots, bufferMeters: halfMile)
        let longest = a.longestGaps()
        XCTAssertEqual(longest.count, 3)
        XCTAssertEqual(longest[0].length, tenth, accuracy: 0.01)          // A to B
        XCTAssertEqual(longest[1].length, tenth / 2, accuracy: 0.01)      // B to end
        XCTAssertEqual(longest[2].length, tenth * 0.3, accuracy: 0.01)    // D to A
        XCTAssertEqual(longest[0].start, tenth / 2, accuracy: 0.01)
    }

    func testLongestGapsTiesKeepRouteOrder() throws {
        // One stop in the middle: two equal gaps.
        let a = RouteAnalysis(route: try makeRoute(), spots: [spot("M", .tap, 0, 0.1)], bufferMeters: 100)
        let longest = a.longestGaps(2)
        XCTAssertEqual(longest.map(\.start), [0, a.gaps[1].start])
    }

    func testKindFilter() throws {
        let a = RouteAnalysis(route: try makeRoute(), spots: spots, bufferMeters: halfMile,
                              kinds: [.fountain, .tap])
        XCTAssertEqual(a.stops.map(\.spot.id), ["A", "B"])
    }

    func testLargerBufferAddsStops() throws {
        let a = RouteAnalysis(route: try makeRoute(), spots: spots, bufferMeters: 1.0 * Geo.metersPerMile)
        XCTAssertEqual(a.stops.map(\.spot.id), ["D", "A", "C", "B"])
    }

    func testNoWaterIsOneGap() throws {
        let route = try makeRoute()
        let a = RouteAnalysis(route: route, spots: [WaterSpot](), bufferMeters: halfMile)
        XCTAssertEqual(a.stops.count, 0)
        XCTAssertEqual(a.gaps, [RouteGap(start: 0, end: route.length)])
    }

    func testNextStop() throws {
        let a = RouteAnalysis(route: try makeRoute(), spots: spots, bufferMeters: halfMile)
        XCTAssertEqual(a.nextStop(after: 0)?.spot.id, "D")
        XCTAssertEqual(a.nextStop(after: 3_000)?.spot.id, "A")
        XCTAssertNil(a.nextStop(after: 20_000))
    }
}

import XCTest
@testable import OasisCore

final class SpotClusteringTests: XCTestCase {
    func spot(_ id: String, _ kind: SpotKind, _ lat: Double, _ lon: Double) -> WaterSpot {
        WaterSpot(id: id, source: .openStreetMap, latitude: lat, longitude: lon, kind: kind, tags: [:])
    }

    /// 360 / 2^14, about 2 km at this latitude.
    let cell = 360.0 / 16_384

    func clustersIn(_ items: [ClusterItem]) -> [SpotCluster] {
        items.compactMap { if case .cluster(let c) = $0 { c } else { nil } }
    }

    func singlesIn(_ items: [ClusterItem]) -> [WaterSpot] {
        items.compactMap { if case .spot(let s) = $0 { s } else { nil } }
    }

    func testCellSizeIsPowerOfTwoFraction() {
        XCTAssertEqual(SpotClustering.cellSize(forLongitudeSpan: 1), 360.0 / 2048)
        // A small zoom change keeps the same grid.
        XCTAssertEqual(SpotClustering.cellSize(forLongitudeSpan: 0.9), 360.0 / 2048)
        XCTAssertEqual(SpotClustering.cellSize(forLongitudeSpan: 0.5), 360.0 / 4096)
        XCTAssertEqual(SpotClustering.cellSize(forLongitudeSpan: 400), 90)
        XCTAssertEqual(SpotClustering.cellSize(forLongitudeSpan: 1, cellsAcross: 4), 360.0 / 1024)
    }

    func testCellSizeIsAtLeastTheRawSize() {
        for span in stride(from: 0.001, through: 50, by: 0.37) {
            let size = SpotClustering.cellSize(forLongitudeSpan: span)
            XCTAssertGreaterThanOrEqual(size, span / 8)
            XCTAssertLessThan(size, span / 8 * 2 + 1e-12)
        }
    }

    func testDenseStoresBecomeOneCluster() throws {
        let stores = (0..<5).map { spot("b\($0)", .convenience, 38.3001 + Double($0) * 1e-5, -122.2901 - Double($0) * 1e-5) }
        let items = SpotClustering.cluster(stores, cellSize: cell)
        let c = try XCTUnwrap(clustersIn(items).first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(c.count, 5)
        XCTAssertEqual(c.layer, .buyWater)
        XCTAssertEqual(c.center.latitude, 38.3001 + 2e-5, accuracy: 1e-9)
        XCTAssertEqual(c.bounds, BoundingBox(south: 38.3001, west: -122.2901 - 4e-5, north: 38.3001 + 4e-5, east: -122.2901))
    }

    func testLayersClusterSeparately() {
        let mixed = (0..<3).map { spot("b\($0)", .convenience, 38.3001, -122.2901) }
            + (0..<3).map { spot("f\($0)", .fountain, 38.3001, -122.2901) }
        let found = clustersIn(SpotClustering.cluster(mixed, cellSize: cell))
        XCTAssertEqual(Set(found.map(\.layer)), [.buyWater, .freeWater])
        XCTAssertEqual(found.map(\.count), [3, 3])
    }

    func testFreeKindsShareOneLayer() {
        let free = [spot("f", .fountain, 38.3001, -122.2901), spot("t", .tap, 38.3001, -122.2901),
                    spot("o", .other, 38.3001, -122.2901)]
        XCTAssertEqual(clustersIn(SpotClustering.cluster(free, cellSize: cell)).first?.count, 3)
    }

    func testBuyCategoriesShareOneLayer() {
        let shops = [spot("c", .convenience, 38.3001, -122.2901), spot("g", .grocery, 38.3001, -122.2901),
                     spot("r", .restaurant, 38.3001, -122.2901)]
        let found = clustersIn(SpotClustering.cluster(shops, cellSize: cell))
        XCTAssertEqual(found.map(\.count), [3])
        XCTAssertEqual(found.first?.layer, .buyWater)
    }

    func testSmallGroupsStaySingle() {
        let two = [spot("a", .fountain, 38.3001, -122.2901), spot("b", .fountain, 38.3001, -122.2901)]
        XCTAssertEqual(singlesIn(SpotClustering.cluster(two, cellSize: cell)).count, 2)
        XCTAssertEqual(clustersIn(SpotClustering.cluster(two, cellSize: cell, minClusterSize: 2)).count, 1)
    }

    func testFarPointsDoNotCluster() {
        let far = [spot("a", .convenience, 38.30, -122.29), spot("b", .convenience, 38.40, -122.29), spot("c", .convenience, 38.30, -122.19)]
        XCTAssertEqual(singlesIn(SpotClustering.cluster(far, cellSize: cell)).count, 3)
    }

    func testEverySpotIsCountedOnce() {
        var spots: [WaterSpot] = []
        for i in 0..<20 {
            for j in 0..<10 {
                spots.append(spot("s\(i)-\(j)", j % 3 == 0 ? .grocery : .fountain,
                                  38.2 + Double(i) * 0.003, -122.4 + Double(j) * 0.004))
            }
        }
        let items = SpotClustering.cluster(spots, cellSize: 360.0 / 4096)
        let total = clustersIn(items).map(\.count).reduce(0, +) + singlesIn(items).count
        XCTAssertEqual(total, spots.count)
        XCTAssertLessThan(items.count, spots.count)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "ids must be unique")
    }

    func testOutputIsDeterministic() {
        let spots = (0..<30).map { spot("s\($0)", .convenience, 38.3 + Double($0 % 6) * 0.01, -122.3 + Double($0 / 6) * 0.01) }
        let a = SpotClustering.cluster(spots, cellSize: 360.0 / 8192)
        let b = SpotClustering.cluster(spots.reversed(), cellSize: 360.0 / 8192)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    func testMercator() {
        let eq = SpotClustering.mercator(Coordinate(latitude: 0, longitude: 0))
        XCTAssertEqual(eq.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(eq.y, 0.5, accuracy: 1e-12)
        XCTAssertLessThan(SpotClustering.mercator(Coordinate(latitude: 45, longitude: 0)).y, 0.5)
        XCTAssertEqual(SpotClustering.mercator(Coordinate(latitude: 90, longitude: 180)).y, 0, accuracy: 1e-6)
    }
}

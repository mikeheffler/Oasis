import XCTest
@testable import OasisCore

final class TileTests: XCTestCase {
    func testTileContainingPositiveAndNegative() {
        XCTAssertEqual(TileKey(containing: Coordinate(latitude: 38.30, longitude: -122.29)), TileKey(x: -490, y: 153))
        XCTAssertEqual(TileKey(containing: Coordinate(latitude: 0.1, longitude: 0.1)), TileKey(x: 0, y: 0))
        XCTAssertEqual(TileKey(containing: Coordinate(latitude: -0.1, longitude: -0.1)), TileKey(x: -1, y: -1))
    }

    func testTileEdgeBelongsToNextTile() {
        XCTAssertEqual(TileKey(containing: Coordinate(latitude: 0.25, longitude: 0.5)), TileKey(x: 2, y: 1))
    }

    func testTileBox() {
        XCTAssertEqual(TileKey(x: -490, y: 153).box,
                       BoundingBox(south: 38.25, west: -122.5, north: 38.5, east: -122.25))
    }

    func testTilesCoveringBox() {
        let box = BoundingBox(south: 38.2, west: -122.4, north: 38.3, east: -122.2)
        let tiles = TileKey.tiles(covering: box)
        XCTAssertEqual(Set(tiles), [
            TileKey(x: -490, y: 152), TileKey(x: -490, y: 153),
            TileKey(x: -489, y: 152), TileKey(x: -489, y: 153),
        ])
    }

    func testTilesCoveringInvertedBoxIsEmpty() {
        XCTAssertEqual(TileKey.tiles(covering: BoundingBox(south: 1, west: 1, north: 0, east: 0)), [])
    }

    func testBoxCoveringTiles() {
        let tiles = [TileKey(x: -490, y: 152), TileKey(x: -489, y: 153)]
        XCTAssertEqual(BoundingBox(covering: tiles),
                       BoundingBox(south: 38.0, west: -122.5, north: 38.5, east: -122.0))
        XCTAssertNil(BoundingBox(covering: [TileKey]()))
    }

    func testEveryPointInBoxHasItsTileInCover() {
        let box = BoundingBox(center: Coordinate(latitude: 38.4, longitude: -122.36),
                              latitudeDelta: 0.6, longitudeDelta: 0.8)
        let cover = Set(TileKey.tiles(covering: box))
        for i in 0...20 {
            for j in 0...20 {
                let c = Coordinate(latitude: box.south + box.latitudeSpan * Double(i) / 20,
                                   longitude: box.west + box.longitudeSpan * Double(j) / 20)
                XCTAssertTrue(cover.contains(TileKey(containing: c)), "\(c)")
            }
        }
    }

    func testBoxFromCenter() {
        let box = BoundingBox(center: Coordinate(latitude: 10, longitude: 20), latitudeDelta: 2, longitudeDelta: 4)
        XCTAssertEqual(box, BoundingBox(south: 9, west: 18, north: 11, east: 22))
        XCTAssertTrue(box.contains(Coordinate(latitude: 10, longitude: 20)))
        XCTAssertTrue(box.contains(Coordinate(latitude: 11, longitude: 22)))
        XCTAssertFalse(box.contains(Coordinate(latitude: 11.01, longitude: 20)))
    }

    func testExpandedByMeters() {
        let box = BoundingBox(south: 0, west: 0, north: 0, east: 0).expanded(byMeters: 110_540)
        XCTAssertEqual(box.north, 1, accuracy: 1e-9)
        XCTAssertEqual(box.south, -1, accuracy: 1e-9)
        XCTAssertEqual(box.east, 110_540 / 111_320, accuracy: 1e-9)
    }
}

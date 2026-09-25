import XCTest
@testable import WaterFinderCore

final class WaterFinderCoreTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertEqual(WaterFinderCore.version, "0.1.0")
    }

    func testFixturesAreBundled() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "empty", withExtension: "json", subdirectory: "Fixtures"))
        XCTAssertNoThrow(try Data(contentsOf: url))
    }
}

import XCTest
@testable import OasisCore

final class OasisCoreTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertEqual(OasisCore.version, "0.1.0")
    }

    func testFixturesAreBundled() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "empty", withExtension: "json", subdirectory: "Fixtures"))
        XCTAssertNoThrow(try Data(contentsOf: url))
    }
}

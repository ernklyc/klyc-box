import XCTest
@testable import KLYCKit

final class SteamBlackWindowTests: XCTestCase {
    func testWine11CrossOverEngineIsKnownToShowASteamBlackWindow() {
        XCTAssertTrue(WineRunner.steamShowsBlackWindow(engineID: "x64-crossover26.3-r17"))
        XCTAssertTrue(WineRunner.steamShowsBlackWindow(engineID: "X64-CrossOver26.3-r18"))
    }

    func testWine10EngineIsFine() {
        XCTAssertFalse(WineRunner.steamShowsBlackWindow(engineID: "x64-sikarugir10.0_6-r19"))
    }
}

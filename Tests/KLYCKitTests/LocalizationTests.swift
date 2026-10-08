import XCTest
@testable import KLYCKit

/// A Swift dictionary literal with a repeated key traps the first time it is read. `L()` answers in English under XCTest and never
/// reads the dictionaries, so without this the app could ship a duplicate and crash at launch (it did, once).
final class LocalizationTests: XCTestCase {
    func testEveryTranslationTableLoads() {
        XCTAssertGreaterThan(L10n.tr.count, 100)
        XCTAssertGreaterThan(L10n.trKit.count, 100)
    }
}

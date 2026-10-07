import XCTest
@testable import KLYCKit

final class CreditsTests: XCTestCase {
    func testTheProjectWeAreBuiltOnIsCreditedFirstWithItsLicense() {
        let first = Credits.entries.first
        XCTAssertEqual(first?.name, "Highball")
        XCTAssertEqual(first?.license, "GPL-3.0")
        XCTAssertEqual(first?.url.absoluteString, "https://github.com/gauthierpiarrette/highball")
    }

    func testEveryEntryHasAnHTTPSLinkAndALicense() {
        for e in Credits.entries {
            XCTAssertEqual(e.url.scheme, "https", e.name)
            XCTAssertFalse(e.license.isEmpty, e.name)
            XCTAssertFalse(e.role.isEmpty, e.name)
        }
        XCTAssertEqual(Set(Credits.entries.map(\.name)).count, Credits.entries.count, "no name twice")
    }

    /// A component in the engine manifest without a credit would be a project used and not thanked.
    func testEveryComponentOfTheEngineManifestHasACredit() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "spike/engine-manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("engine manifest not in this checkout") }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let components = try XCTUnwrap(root["components"] as? [String: Any])
        let covered = Set(Credits.entries.flatMap(\.manifestNames))
        for name in components.keys {
            XCTAssertTrue(covered.contains(name), "engine component '\(name)' has no entry in Credits")
        }
    }

    func testTheStatementsSayWhatTheProjectIs() {
        XCTAssertTrue(Credits.ownership.contains("GPL-3.0"))
        XCTAssertTrue(Credits.ownership.localizedCaseInsensitiveContains("not for sale"))
        XCTAssertTrue(Credits.affiliation.contains("Valve") && Credits.affiliation.contains("Apple"))
    }
}

/// The About window shows the credits in Turkish: every role and statement must have a translation,
/// since they are looked up by variable and the l10n check cannot see them.
final class CreditsTranslationTests: XCTestCase {
    func testEveryRoleAndStatementIsTranslated() {
        let strings = Credits.entries.map(\.role) + [Credits.ownership, Credits.affiliation]
        let missing = strings.filter { L10n.tr[$0] == nil && L10n.trKit[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "no Turkish for: \(missing)")
    }
}

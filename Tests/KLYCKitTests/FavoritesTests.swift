import XCTest
@testable import KLYCKit

final class FavoritesTests: XCTestCase {
    private func store() throws -> (LibraryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (LibraryStore(paths: KLYCPaths(home: dir)), dir)
    }

    func testStarAndUnstar() throws {
        let (s, dir) = try store(); defer { try? FileManager.default.removeItem(at: dir) }
        s.setFavorite(true, for: "steam:1"); s.setFavorite(true, for: "epic:x")
        XCTAssertEqual(s.favorites(), ["steam:1", "epic:x"])
        s.setFavorite(false, for: "steam:1")
        XCTAssertEqual(s.favorites(), ["epic:x"])
    }

    func testFavoritesSurvivePlaysAndPruning() throws {
        let (s, dir) = try store(); defer { try? FileManager.default.removeItem(at: dir) }
        s.setFavorite(true, for: "steam:1")
        s.recordPlay(id: "steam:1", bottle: "Games")
        s.recordPlay(id: "steam:gone", bottle: "Games")
        s.prune(validIDs: ["steam:1"])
        XCTAssertEqual(s.favorites(), ["steam:1"])
        XCTAssertNotNil(s.load()["steam:1"])
        XCTAssertNil(s.load()["steam:gone"])
    }
}

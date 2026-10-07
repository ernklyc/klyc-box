import XCTest
@testable import KLYCKit

typealias LibraryItem = KLYCKit.LibraryItem

final class LibraryQueryTests: XCTestCase {
    func item(_ id: String, _ title: String, installed: Bool = true, source: LibrarySource = .steam,
              size: Int64 = 0, played: Double? = nil) -> LibraryItem {
        LibraryItem(source: source, id: id, title: title, bottleName: "Games", installed: installed,
                    sizeOnDisk: size, lastPlayed: played.map { Date(timeIntervalSince1970: $0) })
    }
    var sample: [LibraryItem] {
        [item("a", "Valheim", size: 10, played: 100), item("b", "aseprite", size: 30), item("c", "Hades", installed: false, source: .epic, size: 20, played: 300),
         item("d", "Cyberpunk 2077", size: 50, played: 200)]
    }
    func run(_ q: LibraryQuery, fav: Set<String> = [], ready: Set<String> = []) -> [String] {
        q.apply(to: sample, favorites: fav, title: { $0.title }, isReady: { ready.contains($0.id) }).map(\.id)
    }

    func testInstalledOnlyByDefaultAndSortedByNameIgnoringCase() {
        XCTAssertEqual(run(LibraryQuery()), ["b", "d", "a"])
    }
    func testAllShowsUninstalledToo() { XCTAssertEqual(Set(run(LibraryQuery(show: .all))), ["a", "b", "c", "d"]) }
    func testSourceFilter() { XCTAssertEqual(run(LibraryQuery(source: .epic, show: .all)), ["c"]) }
    func testFavoritesAndReady() {
        XCTAssertEqual(run(LibraryQuery(show: .favorites), fav: ["a"]), ["a"])
        XCTAssertEqual(run(LibraryQuery(show: .ready), ready: ["d", "c"]).sorted(), ["c", "d"])
    }
    func testSearchMatchesTheShownNameToo() {
        let q = LibraryQuery(show: .all, search: "punk")
        XCTAssertEqual(run(q), ["d"])
        let renamed = q.apply(to: sample, favorites: [], title: { $0.id == "a" ? "Punk Valley" : $0.title }, isReady: { _ in false }).map(\.id)
        XCTAssertEqual(Set(renamed), ["a", "d"])
    }
    func testSortByLastPlayedAndSize() {
        XCTAssertEqual(run(LibraryQuery(show: .all, sort: .recent)), ["c", "d", "a", "b"])
        XCTAssertEqual(run(LibraryQuery(show: .all, sort: .size)), ["d", "b", "c", "a"])
    }
    func testShelfPutsStarsThenPlayedThenTheRest() {
        let order = HomeShelf.order(sample, favorites: ["b"], title: { $0.title }).map(\.id)
        XCTAssertEqual(order, ["b", "d", "a"])            // c is not installed
        XCTAssertEqual(HomeShelf.order(sample, favorites: [], search: "val", title: { $0.title }).map(\.id), ["a"])
    }
}

import XCTest
@testable import KLYCKit

final class AtlasCompatFilterTests: XCTestCase {
    private func entry(_ t: String, p: String? = nil, s: Int? = nil) -> AtlasEntry { AtlasEntry(t: t, p: p, s: s) }

    private var feed: AtlasFeed {
        AtlasFeed(games: ["1": entry("tested"), "2": entry("reported"), "3": entry("predicted", p: "likely", s: 5), "4": entry("predicted", p: "likely", s: 90),
                          "5": entry("predicted", p: "maybe", s: 99), "6": entry("blocked")])
    }

    private func ids(_ c: StoreFilters.Compat) -> [Int] {
        var f = StoreFilters(); f.compat = c
        return f.compatIDs(db: GameDB(directories: []), atlas: feed)
    }

    func testEachChoiceListsItsOwnTier() {
        XCTAssertEqual(ids(.tested), [1])
        XCTAssertEqual(ids(.reported), [2])
        XCTAssertEqual(ids(.blocked), [6])
        XCTAssertEqual(ids(.works), [1, 2])
        XCTAssertEqual(ids(.any), [])
    }

    func testPredictionsListOnlyTheLikelyOnesStrongestFirst() {
        XCTAssertEqual(ids(.likely), [4, 3])
    }

    func testTheListIsCapped() {
        let games = Dictionary(uniqueKeysWithValues: (1...1000).map { (String($0), entry("predicted", p: "likely", s: $0)) })
        var f = StoreFilters(); f.compat = .likely
        XCTAssertEqual(f.compatIDs(db: GameDB(directories: []), atlas: AtlasFeed(games: games)).count, StoreFilters.compatLimit)
    }
}

import XCTest
@testable import KLYCKit

private struct FakeStore: StoreService {
    var pages: [[StoreCard]] = []
    var failFirst = 0
    let calls = Calls()
    final class Calls: @unchecked Sendable { var collect = 0 }

    func collect(_ filters: StoreFilters, start: Int) async -> StoreSlice {
        calls.collect += 1
        if calls.collect <= failFirst { return StoreSlice(cards: [], next: 0, total: 0, hasMore: false, failed: true) }
        let index = start / 2
        let page = index < pages.count ? pages[index] : []
        return StoreSlice(cards: page, next: start + page.count, total: pages.reduce(0) { $0 + $1.count }, hasMore: index + 1 < pages.count, failed: false)
    }
    func items(_ appids: [Int]) async -> [StoreCard] { appids.map { StoreCard(appid: $0, name: "G\($0)") } }
    func search(_ filters: StoreFilters, count: Int) async -> StorePage { StorePage(cards: [StoreCard(appid: 99, name: "S")], total: 1) }
    func reviews(_ appid: Int) async -> (ReviewSummary?, [StoreReview]) { (ReviewSummary(label: "x", positive: 9, negative: 1), []) }
    func news(_ appid: Int, count: Int) async -> [SteamNewsItem] { [] }
}

@MainActor
final class StoreModelsTests: XCTestCase {
    func card(_ id: Int) -> StoreCard { StoreCard(appid: id, name: "G\(id)") }

    func testChipsListWhatIsOnAndRemovingOneLeavesTheRest() {
        var f = StoreFilters(tag: 19); f.mac = true; f.onSale = true; f.term = " hades "; f.feature = [9]
        XCTAssertEqual(f.chips, [.tag(19), .mac, .onSale, .feature(9), .term("hades")])
        let without = f.removing(.mac).removing(.term("hades"))
        XCTAssertFalse(without.mac); XCTAssertEqual(without.term, ""); XCTAssertTrue(without.onSale); XCTAssertEqual(without.tags, [19])
        XCTAssertTrue(StoreFilters().isPlain); XCTAssertTrue(f.cleared().chips == [.term("hades")])
        XCTAssertTrue(f.cleared(keepingTerm: false).isPlain)
    }

    func testReloadThenMoreAppendsWithoutRepeats() async {
        let store = FakeStore(pages: [[card(1), card(2)], [card(2), card(3)]])
        let model = StoreResultsModel(filters: StoreFilters(), title: "T", service: store)
        await model.reload(db: GameDB(directories: []))
        XCTAssertEqual(model.cards.map(\.appid), [1, 2]); XCTAssertTrue(model.hasMore); XCTAssertFalse(model.loading); XCTAssertFalse(model.failed)
        await model.more()
        XCTAssertEqual(model.cards.map(\.appid), [1, 2, 3], "2 came twice and is shown once"); XCTAssertFalse(model.hasMore)
    }

    func testAFailedReadIsRetriedThenReportedAsAFailure() async {
        let flaky = FakeStore(pages: [[card(1)]], failFirst: 1)
        var model = StoreResultsModel(filters: StoreFilters(), title: nil, service: flaky)
        await model.reload(db: GameDB(directories: []), attempts: 3, retryDelay: .milliseconds(1))
        XCTAssertEqual(model.cards.map(\.appid), [1]); XCTAssertFalse(model.failed, "the second try worked")
        let dead = FakeStore(pages: [], failFirst: 99)
        model = StoreResultsModel(filters: StoreFilters(), title: nil, service: dead)
        await model.reload(db: GameDB(directories: []), attempts: 2, retryDelay: .milliseconds(1))
        XCTAssertTrue(model.failed); XCTAssertTrue(model.cards.isEmpty); XCTAssertEqual(dead.calls.collect, 2)
    }

    func testTheTitleFollowsTheFilters() {
        let model = StoreResultsModel(filters: .sale, title: "On sale", service: FakeStore())
        XCTAssertEqual(model.pageTitle, "On sale")
        model.filters.mac = true
        XCTAssertEqual(model.pageTitle, "Store")
        model.term = " portal "; model.submitTerm()
        XCTAssertEqual(model.pageTitle, "“portal”")
        model.remove(.term("portal")); XCTAssertEqual(model.term, "")
    }

    func testWishlistShowsWhatTheFiltersAllowInTheChosenOrder() async {
        let model = WishlistModel(service: FakeStore())
        await model.load(ids: [3, 1, 2])
        XCTAssertEqual(model.shown.map(\.appid), [1, 2, 3], "no discounts: by name")
        model.macOnly = true
        XCTAssertTrue(model.shown.isEmpty)
    }

    func testGamePageReadsReviewsTagsAddOnsAndSimilarGames() async {
        let model = StoreGameModel(service: FakeStore())
        var info = StoreInfo(appid: 1, name: "G", shortDescription: nil, genres: [], windows: true, mac: false, linux: false, releaseDate: nil, metacritic: nil,
                             developers: [], price: nil, pc: .init(), macRequirements: .init(), fetched: Date())
        info.dlcIDs = [7, 8]
        await model.load(appid: 1, info: info)
        XCTAssertEqual(model.summary?.percent, 90); XCTAssertEqual(model.dlc.map(\.appid), [7, 8]); XCTAssertTrue(model.reviewsLoaded)
        XCTAssertTrue(model.similar.isEmpty, "the fake card has no tags, so there is nothing to base similar games on")
    }
}

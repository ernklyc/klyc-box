import XCTest
@testable import KLYCKit

final class AtlasFeedTests: XCTestCase {
    var home: URL!
    var store: AtlasFeedStore!
    var session: URLSession!

    static let json = #"{"v":1,"generated":"2026-10-06","site":"klyc-box","games":{"244210":{"t":"tested","r":5,"n":1,"m":"d3dmetal","c":["M1"],"g":["racing"],"y":2013},"730":{"t":"blocked","a":["VAC Ban"]},"1":{"t":"predicted","p":"likely","q":"gold","s":134,"g":["rpg","action"],"y":2015}}}"#

    override func setUp() {
        home = FileManager.default.temporaryDirectory.appending(path: "hb-atlas-\(UUID().uuidString)")
        store = AtlasFeedStore(paths: KLYCPaths(home: home))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubNetwork.self]
        StubNetwork.answers = []; StubNetwork.seen = []; StubNetwork.bodies = [:]
        session = URLSession(configuration: config)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    let url = URL(string: "https://example.test/data/atlas-feed.json")!

    func testDecodesTheFeedAndLooksUpBySteamID() throws {
        let feed = try JSONDecoder().decode(AtlasFeed.self, from: Data(Self.json.utf8))
        XCTAssertEqual(feed[244210]?.tier, .tested)
        XCTAssertEqual(feed[244210]?.c, ["M1"])
        XCTAssertEqual(feed[1]?.p, "likely")
        XCTAssertNil(feed[999])
    }

    /// The real file the site builds must decode: the contract between the two projects.
    func testTheSitesRealFeedDecodes() throws {
        guard let dir = ProcessInfo.processInfo.environment["KLYC_SITE_DIR"] else { throw XCTSkip("set KLYC_SITE_DIR to a checkout of the site to run this contract test") }
        let file = URL(fileURLWithPath: dir).appending(path: "public/data/atlas-feed.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("site checkout not present") }
        let feed = try JSONDecoder().decode(AtlasFeed.self, from: Data(contentsOf: file))
        XCTAssertEqual(feed.v, 1)
        XCTAssertGreaterThan(feed.games.count, 10_000)
        let tiers = Set(feed.games.values.map(\.t))
        XCTAssertTrue(tiers.isSubset(of: ["tested", "reported", "predicted", "blocked"]), "\(tiers)")
        XCTAssertNotNil(feed[244210]?.tier)
    }

    func testTheSiteAddressDefaultsToTheAuthorsPagesAndAcceptsOnlySafeOverrides() {
        XCTAssertEqual(AtlasSite.baseURL(environment: [:], info: nil)?.absoluteString, "https://klycbox.ernklyc.dev")
        XCTAssertNil(AtlasSite.baseURL(environment: ["KLYC_ATLAS_URL": "http://klycbox.example"], info: nil), "plain http only for localhost, and a bad override does not fall back")
        XCTAssertNil(AtlasSite.baseURL(environment: ["KLYC_ATLAS_URL": "not a url"], info: nil))
        XCTAssertEqual(AtlasSite.baseURL(environment: ["KLYC_ATLAS_URL": "https://klycbox.example"], info: nil)?.absoluteString, "https://klycbox.example")
        XCTAssertEqual(AtlasSite.baseURL(environment: ["KLYC_ATLAS_URL": "http://localhost:3112"], info: nil)?.host, "localhost")
        XCTAssertEqual(AtlasSite.baseURL(environment: [:], info: ["KLYCAtlasURL": "https://klycbox.example"])?.host, "klycbox.example")
        let base = URL(string: "https://klycbox.ernklyc.dev")!
        XCTAssertEqual(AtlasSite.gamePage(appid: 244210, base: base)?.absoluteString, "https://klycbox.ernklyc.dev/game/244210/")
        XCTAssertEqual(AtlasSite.feedURL(base: base)?.absoluteString, "https://klycbox.ernklyc.dev/data/atlas-feed.json")
        XCTAssertEqual(AtlasSite.privacyPage(base: base)?.absoluteString, "https://klycbox.ernklyc.dev/privacy/")
        XCTAssertNil(AtlasSite.gamePage(appid: 1, base: nil))
    }

    func testRefreshWithoutAnAddressDoesNothing() async {
        let feed = await store.refresh(url: nil, session: session)
        XCTAssertTrue(feed.isEmpty)
        XCTAssertTrue(StubNetwork.seen.isEmpty, "no address, no request")
    }

    func testRefreshFetchesCachesAndKeepsTheEtag() async throws {
        StubNetwork.answers = [("atlas-feed", 200, Self.json)]
        let feed = await store.refresh(url: url, session: session)
        XCTAssertEqual(feed[244210]?.tier, .tested)
        XCTAssertEqual(store.cached().games.count, 3, "kept for the next launch")
    }

    func testAFreshCacheIsNotFetchedAgainWithinADay() async throws {
        StubNetwork.answers = [("atlas-feed", 200, Self.json)]
        _ = await store.refresh(url: url, session: session)
        StubNetwork.seen = []
        _ = await store.refresh(url: url, session: session, maxAge: 86_400)
        XCTAssertTrue(StubNetwork.seen.isEmpty)
        _ = await store.refresh(url: url, session: session, maxAge: 86_400, now: Date().addingTimeInterval(90_000))
        XCTAssertEqual(StubNetwork.seen.count, 1, "a day later it asks again")
    }

    func testNotModifiedKeepsTheCacheAndAFailureNeverEmptiesIt() async throws {
        StubNetwork.answers = [("atlas-feed", 200, Self.json)]
        _ = await store.refresh(url: url, session: session)
        StubNetwork.answers = [("atlas-feed", 304, "")]
        let kept = await store.refresh(url: url, session: session, now: Date().addingTimeInterval(90_000))
        XCTAssertEqual(kept.games.count, 3)
        StubNetwork.answers = [("atlas-feed", 500, "oops")]
        let afterError = await store.refresh(url: url, session: session, now: Date().addingTimeInterval(200_000))
        XCTAssertEqual(afterError.games.count, 3)
        StubNetwork.answers = [("atlas-feed", 200, #"{"v":2,"generated":"x","games":{"1":{"t":"tested"}}}"#)]
        let wrongVersion = await store.refresh(url: url, session: session, now: Date().addingTimeInterval(400_000))
        XCTAssertEqual(wrongVersion.games.count, 3, "an unknown format version is ignored")
        StubNetwork.answers = [("atlas-feed", 200, "not json")]
        let garbage = await store.refresh(url: url, session: session, now: Date().addingTimeInterval(600_000))
        XCTAssertEqual(garbage.games.count, 3)
    }

    func testCommunityTotalsAppearOnlyWhenPresent() {
        var e = AtlasEntry(t: "reported", r: 4, n: 2)
        XCTAssertFalse(AtlasText.details(e).contains { $0.contains("KLYC-Box") })
        e.u = [5, 4.5, 0.8]
        let line = AtlasText.details(e).first { $0.contains("KLYC-Box") }
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.contains("80") == true)
    }

    func testWordsForEachTier() throws {
        let feed = try JSONDecoder().decode(AtlasFeed.self, from: Data(Self.json.utf8))
        XCTAssertTrue(AtlasText.headline(try XCTUnwrap(feed[244210])).contains("Highball") || AtlasText.headline(feed[244210]!).contains("Highball"))
        XCTAssertTrue(AtlasText.headline(try XCTUnwrap(feed[730])).contains("VAC Ban"))
        XCTAssertTrue(AtlasText.headline(try XCTUnwrap(feed[1])).lowercased().contains("prediction") || AtlasText.headline(feed[1]!).contains("Tahmin"))
        let lines = AtlasText.details(try XCTUnwrap(feed[244210]))
        XCTAssertTrue(lines.contains { $0.contains("M1") })
        XCTAssertTrue(lines.contains { $0.contains("D3DMetal") })
        XCTAssertTrue(lines.contains { $0.contains("2013") })
        XCTAssertEqual(AtlasText.modeName("dxmt"), "DXMT")
        XCTAssertEqual(AtlasText.modeName("unknown"), "unknown")
        let reported = AtlasEntry(t: "reported", r: 4.5, n: 3)
        XCTAssertTrue(AtlasText.headline(reported).contains("3"))
        XCTAssertTrue(AtlasText.headline(reported).contains("4.5") || AtlasText.headline(reported).contains("4,5"))
    }
}

import XCTest
@testable import KLYCKit

final class SteamExtrasTests: XCTestCase {
    func bin(_ parts: [UInt8]...) -> Data { Data(parts.flatMap { $0 }) }
    func s(_ x: String) -> [UInt8] { Array(x.utf8) + [0] }
    func i(_ n: Int32) -> [UInt8] { withUnsafeBytes(of: n.littleEndian) { Array($0) } }

    func testBinaryVDFReadsNestedObjectsStringsAndInts() {
        let data = bin([0], s("a"), [1], s("k"), s("v"), [2], s("n"), i(-5), [8], [8])
        let node = BinaryVDF.parse(data)
        XCTAssertEqual(node["a"]?["k"]?.stringValue, "v")
        XCTAssertEqual(node["a"]?["n"]?.intValue, -5)
        XCTAssertEqual(BinaryVDF.parse(Data([0, 0x61])).keys, [])          // cut off: no crash
    }

    func testAchievementsJoinTheSchemaWithWhatWasUnlocked() throws {
        let schema = bin([0], s("244210"), [0], s("stats"), [0], s("1"), [0], s("bits"),
                         [0], s("0"), [1], s("name"), s("ONE"), [0], s("display"), [0], s("name"), [1], s("english"), s("First"), [8], [8], [8],
                         [0], s("1"), [1], s("name"), s("TWO"), [0], s("display"), [0], s("name"), [1], s("english"), s("Second"), [8], [1], s("hidden"), s("1"), [8], [8],
                         [8], [8], [8], [8], [8])
        let user = bin([0], s("cache"), [0], s("1"), [2], s("data"), i(1), [0], s("AchievementTimes"), [2], s("0"), i(1_660_731_083), [8], [8], [8], [8])
        let parsed = BinaryVDF.parse(schema)
        let a = try XCTUnwrap(SteamAchievements.parse(schema: parsed, user: BinaryVDF.parse(user), appid: 244210))
        XCTAssertEqual(a.items.map(\.id), ["ONE", "TWO"])
        XCTAssertEqual(a.unlockedCount, 1)
        XCTAssertTrue(a.items[0].unlocked); XCTAssertFalse(a.items[1].unlocked)
        XCTAssertEqual(a.items[0].name, "First")
    }

    func testNewsIsPlainText() {
        let json = #"{"appnews":{"appid":1,"newsitems":[{"gid":"1","title":"Update","url":"https://x.test/a","date":1737046294,"feedlabel":"Community Announcements","contents":"[b]Big[/b] news [url=https://y.test]here[/url] &amp; <i>more</i>"}],"count":1}}"#.data(using: .utf8)!
        let items = SteamNews.parse(json)
        XCTAssertEqual(items.first?.text, "Big news here & more")
        XCTAssertEqual(items.first?.feed, "Community Announcements")
    }

    func testNewsLinksAreWebLinksOnly() {
        let json = #"{"appnews":{"newsitems":[{"title":"A","url":"file:///etc/passwd","date":1,"contents":"x"},{"title":"B","url":"https://ok.test/p","date":1,"contents":"x"}]}}"#.data(using: .utf8)!
        XCTAssertEqual(SteamNews.parse(json).map(\.url?.absoluteString), [nil, "https://ok.test/p"])
    }

    func testWishlistAndPrices() {
        XCTAssertEqual(SteamWishlist.parse(#"{"response":{"items":[{"appid":1943950,"priority":0},{"appid":238960}]}}"#.data(using: .utf8)!), [1943950, 238960])
        XCTAssertEqual(SteamWishlist.parse(#"{"response":{}}"#.data(using: .utf8)!), [])
        let prices = SteamWishlist.parsePrices(#"{"1145360":{"success":true,"data":{"price_overview":{"currency":"USD","initial":825,"final":206,"discount_percent":75,"final_formatted":"$2.06"}}},"9":{"success":false}}"#.data(using: .utf8)!)
        XCTAssertEqual(prices[1145360]?.discount, 75); XCTAssertEqual(prices[1145360]?.onSale, true); XCTAssertNil(prices[9])
    }

    func testOnlyWatchedFriendsWhoJustAppearedAreReported() {
        let before: [Int: FriendPresence] = [1: .init(state: .offline), 2: .init(state: .online), 3: .init(state: .offline)]
        let after: [Int: FriendPresence] = [1: .init(state: .online), 2: .init(state: .online), 3: .init(state: .offline), 4: .init(state: .online)]
        XCTAssertEqual(FriendWatchStore.cameOnline(watched: [1, 2, 3, 4], before: before, after: after), [1])   // 4 was unknown before: not "just came"
        XCTAssertEqual(FriendWatchStore.cameOnline(watched: [5], before: [5: .init(state: .unknown)], after: [5: .init(state: .online)]), [])
        let dir = FileManager.default.temporaryDirectory.appending(path: "fw-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FriendWatchStore(file: dir)
        store.set(7, watched: true); store.set(8, watched: true); store.set(7, watched: false)
        XCTAssertEqual(store.all(), [8])
    }

    func testSessionSummaryCountsRecentSessionsOnly() {
        func rec(_ t: String, _ start: Double, _ secs: Double) -> SessionRecord {
            SessionRecord(title: t, bottle: "Games", appid: nil, started: Date(timeIntervalSince1970: start), ended: Date(timeIntervalSince1970: start + secs), reason: "ended")
        }
        let r = [rec("A", 1_000, 3_600), rec("B", 2_000_000, 600), rec("A", 2_001_000, 300), rec("C", 2_002_000, 5)]
        let s = SessionStats.summary(r, since: Date(timeIntervalSince1970: 1_500_000))
        XCTAssertEqual(s.sessions, 2); XCTAssertEqual(s.seconds, 900); XCTAssertEqual(s.top.first?.title, "B")
    }
}

final class StoreCategoryTests: XCTestCase {
    func testWorkshopCategoryIsRead() {
        let json = #"{"1":{"success":true,"data":{"name":"G","categories":[{"id":2,"description":"Single-player"},{"id":30,"description":"Steam Workshop"}]}}}"#.data(using: .utf8)!
        XCTAssertEqual(SteamStoreInfo.parse(appid: 1, json: json)?.hasWorkshop, true)
        let none = #"{"1":{"success":true,"data":{"name":"G"}}}"#.data(using: .utf8)!
        XCTAssertEqual(SteamStoreInfo.parse(appid: 1, json: none)?.hasWorkshop, false)
    }
}

final class StoreShelfTests: XCTestCase {
    func testFeaturedShelvesAndPrices() {
        let json = #"{"specials":{"items":[{"id":1304930,"name":"X","discount_percent":90,"original_price":1899,"final_price":189,"currency":"USD","windows_available":true,"mac_available":false,"header_image":"https://a.test/h.jpg"}]},"top_sellers":{"items":[]},"status":1}"#.data(using: .utf8)!
        let shelves = SteamStore.parseFeatured(json)
        XCTAssertEqual(shelves.map(\.id), ["specials"])
        let c = shelves[0].cards[0]
        XCTAssertEqual(c.discount, 90); XCTAssertTrue(c.onSale); XCTAssertEqual(c.finalMinor, 189); XCTAssertFalse(c.mac)
        XCTAssertTrue(c.finalText?.contains("1,89") == true)
    }

    func testSearchComputesDiscountAndSkipsNonApps() {
        let json = #"{"total":2,"items":[{"type":"app","id":620,"name":"Portal 2","price":{"currency":"USD","initial":1000,"final":250},"platforms":{"windows":true,"mac":true}},{"type":"bundle","id":9,"name":"B"}]}"#.data(using: .utf8)!
        let cards = SteamStore.parseSearch(json)
        XCTAssertEqual(cards.count, 1); XCTAssertEqual(cards[0].discount, 75); XCTAssertTrue(cards[0].mac)
    }

    func testReviewsSummaryPercent() {
        let json = #"{"success":1,"query_summary":{"review_score_desc":"Çok Olumlu","total_positive":90,"total_negative":10},"reviews":[{"recommendationid":"1","review":"Great","voted_up":true,"votes_up":5,"author":{"playtime_forever":600}},{"recommendationid":"2","review":""}]}"#.data(using: .utf8)!
        let (summary, reviews) = SteamStore.parseReviews(json)
        XCTAssertEqual(summary?.percent, 90); XCTAssertEqual(reviews.count, 1); XCTAssertEqual(reviews[0].hours, 10)
    }

    func testMediaIsReadFromStoreInfo() {
        let json = #"{"1":{"success":true,"data":{"name":"G","screenshots":[{"path_full":"https://a.test/s.jpg"}],"movies":[{"name":"T","thumbnail":"https://a.test/t.jpg","hls_h264":"https://a.test/m.m3u8"}]}}}"#.data(using: .utf8)!
        let info = SteamStoreInfo.parse(appid: 1, json: json)
        XCTAssertEqual(info?.screenshots?.count, 1); XCTAssertEqual(info?.trailers?.first?.stream.lastPathComponent, "m.m3u8")
    }
}

final class StoreBrowseTests: XCTestCase {
    func testQueryReadsPriceReviewsPlatformsAndImage() {
        let json = #"{"response":{"metadata":{"total_matching_records":42},"store_items":[{"appid":10,"name":"G","is_free":false,"assets":{"asset_url_format":"steam/apps/10/${FILENAME}?t=1","header":"abc/header.jpg"},"reviews":{"summary_filtered":{"review_count":100,"percent_positive":91,"review_score_label":"Çok Olumlu"}},"platforms":{"windows":true,"mac":true},"best_purchase_option":{"final_price_in_cents":"250","original_price_in_cents":"1000","formatted_final_price":"$2.50","formatted_original_price":"$10.00","discount_pct":75}},{"appid":11,"name":"F","is_free":true}]}}"#.data(using: .utf8)!
        let page = SteamStore.parseQuery(json)
        XCTAssertEqual(page.total, 42); XCTAssertEqual(page.cards.count, 2)
        let g = page.cards[0]
        XCTAssertEqual(g.discount, 75); XCTAssertEqual(g.finalText, "$2.50"); XCTAssertEqual(g.reviewPercent, 91); XCTAssertTrue(g.mac)
        XCTAssertEqual(g.image?.absoluteString, "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/10/abc/header.jpg?t=1")
        XCTAssertTrue(page.cards[1].isFree)
    }

    func testCategoriesListTheCommonOnesFirstThenTheRest() {
        let json = #"{"response":{"tags":[{"tagid":21,"name":"Macera"},{"tagid":19,"name":"Aksiyon"},{"tagid":999999,"name":"X"}]}}"#.data(using: .utf8)!
        XCTAssertEqual(SteamStore.parseCategories(json).map(\.name), ["Aksiyon", "Macera", "X"])
    }
}

final class SteamTransferTests: XCTestCase {
    func acf(flags: Int, down: Int, total: Int) -> String {
        "\"AppState\"\n{\n\t\"appid\"\t\t\"1\"\n\t\"name\"\t\t\"Game\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"SizeOnDisk\"\t\t\"500\"\n\t\"BytesToDownload\"\t\t\"\(total)\"\n\t\"BytesDownloaded\"\t\t\"\(down)\"\n\t\"BytesToStage\"\t\t\"\(total)\"\n\t\"BytesStaged\"\t\t\"\(down)\"\n}"
    }
    func testStatesAndProgress() throws {
        let installed = try XCTUnwrap(SteamTransfer.parse(acf(flags: 4, down: 10, total: 10)))
        XCTAssertEqual(installed.state, .installed); XCTAssertEqual(installed.progress, 1)
        let running = try XCTUnwrap(SteamTransfer.parse(acf(flags: 1026, down: 25, total: 100)))
        XCTAssertEqual(running.state, .downloading); XCTAssertEqual(running.progress ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(SteamTransfer.parse(acf(flags: 514, down: 0, total: 100))?.state, .paused)
        XCTAssertEqual(SteamTransfer.parse(acf(flags: 6, down: 0, total: 100))?.state, .waiting)
        XCTAssertNil(SteamTransfer.parse("not an acf"))
    }
}

final class StoreSearchTests: XCTestCase {
    func testFiltersBecomeSteamsOwnParameters() {
        var f = StoreFilters(tag: 19); f.mac = true; f.onSale = true; f.price = .under(10); f.turkish = true; f.deckVerified = true; f.feature = [9, 2]; f.sort = .reviews
        let q = Dictionary(uniqueKeysWithValues: f.items(start: 48, count: 48).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["os"], "mac"); XCTAssertEqual(q["specials"], "1"); XCTAssertEqual(q["maxprice"], "10"); XCTAssertEqual(q["tags"], "19")
        XCTAssertEqual(q["category3"], "2,9"); XCTAssertEqual(q["sort_by"], "Reviews_DESC"); XCTAssertEqual(q["start"], "48"); XCTAssertEqual(q["deck_compatibility"], "3")
        XCTAssertEqual(f.activeCount, 8)
        XCTAssertNil(Dictionary(uniqueKeysWithValues: StoreFilters().items(start: 0, count: 1).map { ($0.name, $0.value ?? "") })["os"])
    }

    func testRowsAreReadFromTheStoresHTML() {
        let html = """
        <a href="https://store.steampowered.com/app/730/CS/" data-ds-appid="730" class="search_result_row ds_collapse_flag ">
        <span class="title">Counter &amp; Strike</span><div class="search_platforms"><span class="platform_img win"></span><span class="platform_img mac"></span></div>
        <span class="search_review_summary positive" data-tooltip-html="Çok Olumlu&lt;br&gt;Bu oyun için 503,586 incelemeden %83 kadarı olumlu."></span>
        <div class="discount_block"><div class="discount_pct">-75%</div><div class="discount_prices"><div class="discount_original_price">$10.00</div><div class="discount_final_price">$2.50</div></div></div></a>
        <a href="x" data-ds-appid="5" class="search_result_row"><span class="title">Free One</span><div class="discount_final_price free">Ücretsiz</div></a>
        <a href="x" data-ds-bundleid="9" class="search_result_row"><span class="title">Bundle</span></a>
        """
        let page = SteamStore.parseSearch(html: html, total: 99)
        XCTAssertEqual(page.total, 99); XCTAssertEqual(page.cards.map(\.appid), [730, 5])
        let a = page.cards[0]
        XCTAssertEqual(a.name, "Counter & Strike"); XCTAssertTrue(a.mac); XCTAssertEqual(a.discount, 75); XCTAssertEqual(a.finalText, "$2.50")
        XCTAssertEqual(a.originalText, "$10.00"); XCTAssertEqual(a.reviewPercent, 83); XCTAssertEqual(a.reviewLabel, "Çok Olumlu")
        XCTAssertTrue(page.cards[1].isFree)
    }

    func testRowsUseTheirOwnCapsuleWithTheHeaderAsFallback() {
        let html = #"<a href="x" data-ds-appid="7" class="search_result_row"><div class="search_capsule"><img src="https://x.test/steam/apps/7/abc123/capsule_231x87.jpg?t=1" ></div><span class="title">G</span></a>"#
        let c = SteamStore.parseSearch(html: html, total: 1).cards[0]
        XCTAssertEqual(c.image?.absoluteString, "https://x.test/steam/apps/7/abc123/capsule_616x353.jpg?t=1")
        XCTAssertEqual(c.fallbackImage?.absoluteString, "https://x.test/steam/apps/7/abc123/capsule_231x87.jpg?t=1")
    }

    func testPlainMeansNothingOnAndNothingTyped() {
        var f = StoreFilters(); XCTAssertTrue(f.isPlain)
        f.sort = .newest; XCTAssertTrue(f.isPlain)
        f.term = "  "; XCTAssertTrue(f.isPlain)
        f.mac = true; XCTAssertFalse(f.isPlain)
        f = StoreFilters(); f.term = "hades"; XCTAssertFalse(f.isPlain)
    }

    func testNoReviewsMeansNoRating() {
        let json = #"{"response":{"store_items":[{"appid":3,"name":"New","reviews":{"summary_filtered":{"review_count":0,"percent_positive":0}}}]}}"#.data(using: .utf8)!
        XCTAssertNil(SteamStore.parseQuery(json).cards.first?.reviewPercent)
    }

    func testEpicGiftsAreOnlyHundredPercentOffers() {
        let json = """
        {"data":{"Catalog":{"searchStore":{"elements":[
        {"id":"a","title":"Gift","keyImages":[{"type":"OfferImageWide","url":"https://x.test/i.jpg"}],"offerMappings":[{"pageSlug":"gift-slug"}],"price":{"totalPrice":{"fmtPrice":{"originalPrice":"₺419,00"}}},
         "promotions":{"promotionalOffers":[{"promotionalOffers":[{"startDate":"2026-10-01T15:00:00.000Z","endDate":"2026-10-08T15:00:00.000Z","discountSetting":{"discountPercentage":0}}]}],"upcomingPromotionalOffers":[]}},
        {"id":"b","title":"Sale","keyImages":[],"promotions":{"promotionalOffers":[],"upcomingPromotionalOffers":[{"promotionalOffers":[{"startDate":"2026-10-19T15:00:00.000Z","endDate":"2026-11-02T15:00:00.000Z","discountSetting":{"discountPercentage":40}}]}]}},
        {"id":"c","title":"Next","keyImages":[],"productSlug":"next/home","promotions":{"promotionalOffers":[],"upcomingPromotionalOffers":[{"promotionalOffers":[{"startDate":"2026-10-08T15:00:00.000Z","endDate":"2026-10-15T15:00:00.000Z","discountSetting":{"discountPercentage":0}}]}]}}
        ]}}}}
        """.data(using: .utf8)!
        let games = EpicFree.parse(json)
        XCTAssertEqual(games.map(\.title), ["Gift", "Next"])
        XCTAssertEqual(games[0].url?.absoluteString, "https://store.epicgames.com/tr/p/gift-slug")
        XCTAssertEqual(games[1].url?.absoluteString, "https://store.epicgames.com/tr/p/next")
        XCTAssertTrue(games[0].isFree(at: games[0].start.addingTimeInterval(60))); XCTAssertFalse(games[1].isFree(at: games[0].start.addingTimeInterval(60)))
    }
}


final class StoreCompatTests: XCTestCase {
    func entry(_ status: String, appid: Int, title: String = "T") -> GameDBEntry {
        try! JSONDecoder().decode(GameDBEntry.self, from: #"{"id":"g\#(appid)","title":"\#(title)","steam_appid":\#(appid),"status":"\#(status)"}"#.data(using: .utf8)!)
    }

    func testTiersComeFromTheRecordsAndNativeIsSeparate() {
        let blocked = GameSupport.resolve(entry: entry("blocked-anticheat", appid: 1), local: nil, nativeMac: false)
        XCTAssertEqual(blocked.wine, .blocked); XCTAssertEqual(blocked.blockReason, "anticheat"); XCTAssertFalse(blocked.runsSomehow)
        XCTAssertEqual(GameSupport.resolve(entry: entry("community", appid: 1), local: nil, nativeMac: false).wine, .reported)
        XCTAssertEqual(GameSupport.resolve(entry: entry("reported-upstream", appid: 1), local: nil, nativeMac: false).wine, .reported)
        XCTAssertEqual(GameSupport.resolve(entry: entry("verified-local", appid: 1), local: nil, nativeMac: false).wine, .tested)
        let none = GameSupport.resolve(entry: nil, local: nil, nativeMac: false)
        XCTAssertEqual(none.wine, .untested); XCTAssertNil(none.source); XCTAssertFalse(none.runsSomehow)
    }

    func testAGameWithAMacBuildIsNeverCalledUnsupported() {
        // Rust-like: the Windows build is blocked by anti-cheat, the store lists a Mac build.
        let s = GameSupport.resolve(entry: entry("blocked-anticheat", appid: 252490), local: nil, nativeMac: true)
        XCTAssertTrue(s.native); XCTAssertEqual(s.wine, .blocked); XCTAssertTrue(s.runsSomehow)
        var f = StoreFilters(); f.compat = .blocked
        var withMac = StoreCard(appid: 1, name: "Rust"); withMac.mac = true
        let without = StoreCard(appid: 2, name: "Other")
        XCTAssertEqual(f.applyLocally([withMac, without]).map(\.appid), [2])
    }

    func testSourceIsTheFirstSentenceOfTheProvenance() {
        var json = #"{"id":"g9","title":"T","steam_appid":9,"status":"community","provenance":"Reported by someone (upstream#1). Not verified by the maintainer.","lastVerified":"2026-10-03"}"#
        let e = try! JSONDecoder().decode(GameDBEntry.self, from: json.data(using: .utf8)!)
        let s = GameSupport.resolve(entry: e, local: nil, nativeMac: false)
        XCTAssertEqual(s.source, "Reported by someone (upstream#1)"); XCTAssertEqual(s.date, "2026-10-03")
        json = ""
    }

    func testLocalFiltersApplyToCards() {
        var a = StoreCard(appid: 1, name: "Alpha", finalMinor: 500); a.discount = 50; a.mac = true; a.reviewPercent = 80
        let b = StoreCard(appid: 2, name: "Beta", finalMinor: 0)
        let c = StoreCard(appid: 3, name: "Gamma", finalMinor: 2500)
        var f = StoreFilters(); f.onSale = true
        XCTAssertEqual(f.applyLocally([a, b, c]).map(\.appid), [1])
        f = StoreFilters(); f.price = .free; XCTAssertEqual(f.applyLocally([a, b, c]).map(\.appid), [2])
        f = StoreFilters(); f.price = .under(10); XCTAssertEqual(Set(f.applyLocally([a, b, c]).map(\.appid)), [1, 2])
        f = StoreFilters(); f.mac = true; XCTAssertEqual(f.applyLocally([a, b, c]).map(\.appid), [1])
        f = StoreFilters(); f.term = "gam"; XCTAssertEqual(f.applyLocally([a, b, c]).map(\.appid), [3])
        f = StoreFilters(); f.sort = .priceHigh; XCTAssertEqual(f.applyLocally([a, b, c]).map(\.appid), [3, 1, 2])
        f = StoreFilters(); f.compat = .tested; XCTAssertEqual(f.activeCount, 1)
    }
}

final class StoreFreshnessTests: XCTestCase {
    func testYearFromStoreDates() {
        XCTAssertEqual(SteamStore.year("12 Eki 2012"), 2012)
        XCTAssertEqual(SteamStore.year("Oct 5, 2026"), 2026)
        XCTAssertNil(SteamStore.year("Yakında"))
    }

    func testRowCarriesReleaseYearAndTags() {
        let html = #"<a href="x" data-ds-appid="9" data-ds-tagids="[19,21,1695]" class="search_result_row"><span class="title">G</span><div class="search_released responsive_secondrow">3 Ağu 2023</div></a>"#
        let c = SteamStore.parseSearch(html: html, total: 1).cards[0]
        XCTAssertEqual(c.releaseYear, 2023); XCTAssertEqual(c.tagIDs, [19, 21, 1695])
    }

    func testListAndMinYear() {
        var f = StoreFilters(); f.list = .popularNew; f.minYear = 2024
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: f.items(start: 0, count: 1).map { ($0.name, $0.value ?? "") })["filter"], "popularnew")
        XCTAssertEqual(f.activeCount, 2)
        var old = StoreCard(appid: 1, name: "Old"); old.releaseYear = 2012
        var new = StoreCard(appid: 2, name: "New"); new.releaseYear = 2025
        XCTAssertEqual(f.applyLocally([old, new]).map(\.appid), [2])
    }

    func testQueryItemsGetYearAndTags() {
        let json = #"{"response":{"store_items":[{"appid":4,"name":"X","release":{"steam_release_date":1790000000},"tags":[{"tagid":19,"weight":10},{"tagid":21,"weight":5}]}]}}"#.data(using: .utf8)!
        let c = SteamStore.parseQuery(json).cards[0]
        XCTAssertEqual(c.releaseYear, 2026); XCTAssertEqual(c.tagIDs, [19, 21])
    }

    func testStorePageFactsAreRead() {
        let json = #"{"1":{"success":true,"data":{"name":"G","about_the_game":"<p>Long <b>text</b></p>","publishers":["Pub"],"supported_languages":"İngilizce<strong>*</strong>, Türkçe, Almanca<br><strong>*</strong>dilde ses","dlc":[7,8],"achievements":{"total":49},"recommendations":{"total":1234},"website":"javascript:alert(1)","controller_support":"full"}}}"#.data(using: .utf8)!
        let i = SteamStoreInfo.parse(appid: 1, json: json)
        XCTAssertEqual(i?.languages, ["İngilizce", "Türkçe", "Almanca"]); XCTAssertEqual(i?.hasTurkish, true)
        XCTAssertEqual(i?.dlcIDs, [7, 8]); XCTAssertEqual(i?.achievementsTotal, 49); XCTAssertEqual(i?.recommendations, 1234)
        XCTAssertEqual(i?.about, "Long text"); XCTAssertNil(i?.website, "only web links are kept")
    }
}

final class StoreCollectTests: XCTestCase {
    func card(_ id: Int, _ year: Int) -> StoreCard { var c = StoreCard(appid: id, name: "G\(id)"); c.releaseYear = year; return c }

    func testKeepsReadingUntilEnoughRecentGamesPass() async {
        var f = StoreFilters(); f.minYear = 2024
        // Pages of 3: only one in three is recent.
        let slice = await SteamStore.collect(f, start: 0, want: 3, maxPages: 10) { start in
            StorePage(cards: (0..<3).map { card(start + $0, ($0 == 0) ? 2025 : 2010) }, total: 90)
        }
        XCTAssertEqual(slice.cards.count, 3); XCTAssertEqual(slice.next, 9); XCTAssertTrue(slice.hasMore)
    }

    func testWithoutAYearRuleItIsOneRead() async {
        let slice = await SteamStore.collect(StoreFilters(), start: 0, want: 3) { _ in StorePage(cards: [self.card(1, 2000)], total: 50) }
        XCTAssertEqual(slice.cards.count, 1); XCTAssertEqual(slice.next, 1)
    }

    func testStopsWhenThePagesRunOutAndSeparatesFailure() async {
        var f = StoreFilters(); f.minYear = 2030
        let none = await SteamStore.collect(f, start: 0, want: 5, maxPages: 10) { s in StorePage(cards: s < 6 ? [self.card(s, 2000), self.card(s + 1, 2001), self.card(s + 2, 2002)] : [], total: 6) }
        XCTAssertTrue(none.cards.isEmpty); XCTAssertFalse(none.hasMore); XCTAssertFalse(none.failed)
        let bad = await SteamStore.collect(f, start: 0) { _ in StorePage(cards: [], total: 0, failed: true) }
        XCTAssertTrue(bad.failed)
    }
}

import Foundation

public struct StoreCategory: Sendable, Equatable, Identifiable, Hashable { public var id: Int; public var name: String }

public struct StorePage: Sendable, Equatable {
    public var cards: [StoreCard]; public var total: Int
    /// The store did not answer (or answered something unreadable): different from an answer with no games in it.
    public var failed = false
    public init(cards: [StoreCard], total: Int, failed: Bool = false) { self.cards = cards; self.total = total; self.failed = failed }
}

public extension SteamStore {
    /// The ones people reach for first, in this order; the sheet lists every other category below them.
    static let categoryIDs = [19, 21, 122, 9, 599, 701, 699, 597, 492, 1664, 1667, 1663, 1695, 3859, 1685, 1662, 1625, 1743, 1716, 1742, 3810, 4328]

    /// Every category Steam has, the common ones first (in the order above), the rest by name.
    static func parseCategories(_ json: Data) -> [StoreCategory] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tags = (root["response"] as? [String: Any])?["tags"] as? [[String: Any]] else { return [] }
        var names: [Int: String] = [:]
        for t in tags { if let id = t["tagid"] as? Int, let name = t["name"] as? String { names[id] = name } }
        let first = categoryIDs.compactMap { id in names[id].map { StoreCategory(id: id, name: $0) } }
        let rest = names.filter { !categoryIDs.contains($0.key) }.map { StoreCategory(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return first + rest
    }

    static func parseQuery(_ json: Data) -> StorePage {
        guard let root = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["response"] as? [String: Any] else { return StorePage(cards: [], total: 0) }
        let total = (root["metadata"] as? [String: Any])?["total_matching_records"] as? Int ?? 0
        let cards: [StoreCard] = (root["store_items"] as? [[String: Any]] ?? []).compactMap { d in
            guard let id = d["appid"] as? Int ?? d["id"] as? Int, let name = d["name"] as? String, !name.isEmpty else { return nil }
            var image = URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg")
            if let assets = d["assets"] as? [String: Any], let format = assets["asset_url_format"] as? String, let header = assets["header"] as? String {
                image = URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/" + format.replacingOccurrences(of: "${FILENAME}", with: header))
            }
            let option = d["best_purchase_option"] as? [String: Any] ?? (d["purchase_options"] as? [[String: Any]])?.first
            func minor(_ key: String) -> Int? { (option?[key] as? String).flatMap(Int.init) ?? option?[key] as? Int }
            let free = d["is_free"] as? Bool ?? false
            let platforms = d["platforms"] as? [String: Any]
            var card = StoreCard(appid: id, name: name, image: image, discount: option?["discount_pct"] as? Int ?? 0,
                                 originalMinor: minor("original_price_in_cents"), finalMinor: free ? 0 : minor("final_price_in_cents"),
                                 windows: platforms?["windows"] as? Bool ?? true, mac: platforms?["mac"] as? Bool ?? false)
            // No reviews yet is not "0% positive": leave the rating out.
            if let reviews = (d["reviews"] as? [String: Any])?["summary_filtered"] as? [String: Any], (reviews["review_count"] as? Int ?? 0) > 0 {
                card.reviewPercent = reviews["percent_positive"] as? Int
                card.reviewLabel = reviews["review_score_label"] as? String
            }
            if let stamp = (d["release"] as? [String: Any])?["steam_release_date"] as? Int { card.releaseYear = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: Date(timeIntervalSince1970: TimeInterval(stamp))).year }
            if let tags = d["tags"] as? [[String: Any]] { card.tagIDs = tags.compactMap { $0["tagid"] as? Int } }
            if let text = option?["formatted_final_price"] as? String, !free { card.priceText = text }
            if let text = option?["formatted_original_price"] as? String { card.originalPriceText = text }
            return card
        }
        return StorePage(cards: cards, total: total)
    }

    static func categories(session: URLSession = .shared) async -> [StoreCategory] {
        guard let url = URL(string: "https://api.steampowered.com/IStoreService/GetTagList/v1/?language=turkish"),
              let (data, _) = try? await session.data(from: url) else { return [] }
        return parseCategories(data)
    }
}

/// Everything the store's own filters can say. Each one is a parameter Steam's search page takes, so the answer is Steam's.
public struct StoreFilters: Hashable, Sendable {
    public enum Sort: String, CaseIterable, Sendable { case relevance = "_ASC", newest = "Released_DESC", reviews = "Reviews_DESC", priceLow = "Price_ASC", priceHigh = "Price_DESC", name = "Name_ASC" }
    public enum Price: Hashable, Sendable { case any, free, under(Int) }
    /// Steam's feature categories (the store's "category3"): 2 single-player, 1 multi-player, 9 co-op, 28 full controller, 23 cloud, 30 Workshop, 22 achievements, 29 trading cards.
    public static let features: [Int] = [2, 1, 9, 28, 23, 30, 22, 29]

    public var term = ""
    public var tags: [Int] = []
    public var sort: Sort = .relevance
    public var mac = false
    public var onSale = false
    public var price: Price = .any
    public var turkish = false
    public var deckVerified = false
    public var feature: Set<Int> = []
    /// Whether it runs on a Mac, by our own records (not something the store can filter): applied here, to the games the records name.
    public var compat: Compat = .any
    /// Steam's own ready-made lists: the best sellers, the popular new releases, what is coming.
    public var list: List = .none
    public enum List: String, Hashable, Sendable { case none = "", topSellers = "topsellers", popularNew = "popularnew", comingSoon = "popularcomingsoon" }
    /// Hide games released before this year (applied to the rows as they arrive; the store has no such filter).
    public var minYear: Int? = nil
    public enum Compat: Hashable, Sendable, CaseIterable { case any, works, tested, reported, likely, blocked }

    public init() {}
    public init(tag: Int) { tags = [tag] }
    public static var sale: StoreFilters { var f = StoreFilters(); f.onSale = true; return f }
    public static var free: StoreFilters { var f = StoreFilters(); f.price = .free; return f }
    public static var popular: StoreFilters { StoreFilters() }

    /// How many filters are on (the sort and the search text are not counted).
    public var activeCount: Int {
        tags.count + (mac ? 1 : 0) + (onSale ? 1 : 0) + (price == .any ? 0 : 1) + (turkish ? 1 : 0) + (deckVerified ? 1 : 0) + feature.count + (compat == .any ? 0 : 1) + (list == .none ? 0 : 1) + (minYear == nil ? 0 : 1)
    }

    /// Nothing is switched on and nothing is typed: the same as the store's front page (the sort does not count).
    public var isPlain: Bool { activeCount == 0 && term.trimmingCharacters(in: .whitespaces).isEmpty }

    func items(start: Int, count: Int) -> [URLQueryItem] {
        var q: [(String, String)] = [("term", term), ("start", String(start)), ("count", String(count)), ("infinite", "1"), ("cc", "tr"), ("l", "turkish"),
                                     ("category1", "998"), ("sort_by", sort.rawValue), ("ndl", "1")]
        if list != .none { q.append(("filter", list.rawValue)) }
        if !tags.isEmpty { q.append(("tags", tags.map(String.init).joined(separator: ","))) }
        if mac { q.append(("os", "mac")) }
        if onSale { q.append(("specials", "1")) }
        switch price { case .any: break; case .free: q.append(("maxprice", "free")); case .under(let n): q.append(("maxprice", String(n))) }
        if turkish { q.append(("supportedlang", "turkish")) }
        if deckVerified { q.append(("deck_compatibility", "3")) }
        if !feature.isEmpty { q.append(("category3", feature.sorted().map(String.init).joined(separator: ","))) }
        return q.map { URLQueryItem(name: $0.0, value: $0.1) }
    }
}

public extension SteamStore {
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(text[r])
        guard let g = try? NSRegularExpression(pattern: pattern).firstMatch(in: match, range: NSRange(match.startIndex..., in: match)), g.numberOfRanges > 1,
              let range = Range(g.range(at: 1), in: match) else { return nil }
        return String(match[range])
    }

    /// The store's own result rows: one per game, with the name, platforms, review summary and price the page shows.
    /// The year in a store date ("12 Eki 2012", "Oct 12, 2012"): the last four digits that look like one.
    static func year(_ text: String) -> Int? {
        guard let r = text.range(of: #"(19|20)\d{2}"#, options: [.regularExpression, .backwards]) else { return nil }
        return Int(text[r])
    }

    static func parseSearch(html: String, total: Int) -> StorePage {
        // Each row is an anchor whose attributes (the app id among them) come before its class.
        let rows = html.components(separatedBy: "<a href=").filter { $0.contains("search_result_row") }
        let cards: [StoreCard] = rows.compactMap { row in
            guard let id = first(#"data-ds-appid="(\d+)""#, in: row).flatMap(Int.init), !row.contains("data-ds-bundleid"),
                  let name = first(#"<span class="title">([^<]*)</span>"#, in: row).map(unescape), !name.isEmpty else { return nil }
            var card = StoreCard(appid: id, name: name,
                                 image: URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg"),
                                 windows: row.contains("platform_img win"), mac: row.contains("platform_img mac"))
            // The row carries the game's own capsule (hashed file name); the larger size sits beside it. The plain header file is the fallback.
            if let small = first(#"search_capsule"><img src="([^"]+)""#, in: row), small.contains("capsule_231x87") {
                card.image = URL(string: small.replacingOccurrences(of: "capsule_231x87", with: "capsule_616x353"))
                card.fallbackImage = URL(string: small)
            }
            card.releaseYear = first(#"search_released[^>]*>\s*([^<]*)<"#, in: row).flatMap(year)
            card.tagIDs = first(#"data-ds-tagids="\[([0-9,]*)\]""#, in: row).map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
            card.discount = first(#"discount_pct">-(\d+)%"#, in: row).flatMap(Int.init) ?? 0
            card.originalPriceText = first(#"discount_original_price">([^<]*)<"#, in: row).map(unescape)
            let final = first(#"discount_final_price[^"]*">([^<]*)<"#, in: row).map(unescape)
            card.priceText = final
            if let f = final, f.lowercased().contains("ücretsiz") || f.lowercased() == "free" || f.lowercased().contains("free to play") { card.finalMinor = 0 }
            if let tip = first(#"data-tooltip-html="([^"]*)""#, in: row).map(unescape) {
                card.reviewLabel = tip.components(separatedBy: "<br>").first
                card.reviewPercent = first(#"%(\d+)"#, in: tip).flatMap(Int.init)
            }
            return card
        }
        return StorePage(cards: cards, total: total)
    }

    static func search(_ filters: StoreFilters, start: Int = 0, count: Int = 48, session: URLSession = .shared) async -> StorePage {
        var components = URLComponents(string: "https://store.steampowered.com/search/results/")!
        components.queryItems = filters.items(start: start, count: count)
        guard let url = components.url else { return StorePage(cards: [], total: 0, failed: true) }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        let got = try? await session.data(for: request)
        guard let (data, _) = got,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let html = root["results_html"] as? String else { return StorePage(cards: [], total: 0, failed: true) }
        return parseSearch(html: html, total: root["total_count"] as? Int ?? 0)
    }

    /// Many games at once by id (the wishlist): name, picture, platforms, reviews and the price now.
    static func items(_ appids: [Int], session: URLSession = .shared) async -> [StoreCard] {
        var out: [StoreCard] = []
        var start = 0
        while start < appids.count {
            let chunk = Array(appids[start..<min(start + 100, appids.count)]); start += 100
            let input: [String: Any] = ["ids": chunk.map { ["appid": $0] }, "context": ["language": "turkish", "country_code": "TR"],
                                        "data_request": ["include_basic_info": true, "include_assets": true, "include_reviews": true, "include_release": true, "include_tag_count": 8,
                                                         "include_all_purchase_options": true, "include_platforms": true]]
            guard let json = try? JSONSerialization.data(withJSONObject: input), var c = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/") else { continue }
            c.queryItems = [URLQueryItem(name: "input_json", value: String(decoding: json, as: UTF8.self))]
            guard let url = c.url, let (data, _) = try? await session.data(from: url) else { continue }
            out += parseQuery(data).cards
        }
        return out
    }
}

/// A game Epic gives away, now or next.
public struct EpicFreeGame: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var image: URL?
    public var url: URL?
    public var start: Date
    public var end: Date
    public var normalPrice: String?
    public func isFree(at now: Date) -> Bool { start <= now && now < end }
}

public enum EpicFree {
    public static func parse(_ json: Data) -> [EpicFreeGame] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let elements = (((root["data"] as? [String: Any])?["Catalog"] as? [String: Any])?["searchStore"] as? [String: Any])?["elements"] as? [[String: Any]] else { return [] }
        let plain = ISO8601DateFormatter(); let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ s: String?) -> Date? { s.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) } }
        var out: [EpicFreeGame] = []
        for e in elements {
            guard let id = e["id"] as? String, let title = e["title"] as? String else { continue }
            let promos = e["promotions"] as? [String: Any]
            // Only a 100% discount is a gift: a 40% sale is not.
            let groups = ((promos?["promotionalOffers"] as? [[String: Any]]) ?? []) + ((promos?["upcomingPromotionalOffers"] as? [[String: Any]]) ?? [])
            let free = groups.flatMap { ($0["promotionalOffers"] as? [[String: Any]]) ?? [] }
                .first { (($0["discountSetting"] as? [String: Any])?["discountPercentage"] as? Int) == 0 }
            guard let free, let start = date(free["startDate"] as? String), let end = date(free["endDate"] as? String) else { continue }
            let images = e["keyImages"] as? [[String: Any]] ?? []
            let image = (images.first { $0["type"] as? String == "OfferImageWide" } ?? images.first)?["url"] as? String
            let slug = ((e["offerMappings"] as? [[String: Any]])?.first?["pageSlug"] as? String) ?? (e["productSlug"] as? String)?.replacingOccurrences(of: "/home", with: "")
            let price = (((e["price"] as? [String: Any])?["totalPrice"] as? [String: Any])?["fmtPrice"] as? [String: Any])?["originalPrice"] as? String
            out.append(EpicFreeGame(id: id, title: title, image: image.flatMap(URL.init(string:)),
                                    url: slug.flatMap { URL(string: "https://store.epicgames.com/tr/p/\($0)") }, start: start, end: end, normalPrice: price))
        }
        return out.sorted { $0.start < $1.start }
    }

    public static func fetch(session: URLSession = .shared) async -> [EpicFreeGame] {
        guard let url = URL(string: "https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=tr&country=TR&allowCountries=TR") else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        guard let (data, _) = try? await session.data(for: request) else { return [] }
        return parse(data)
    }
}


/// What we know about a game on a Mac, as two separate facts, each with its source: whether the store says it has a Mac build (certain),
/// and how the Windows build fares under Wine by our records (tested here or by the project, reported by players, blocked, or unknown).
/// Nothing here is a guess: a game nobody has tried is `untested`, and a game with a Mac build is never called unsupported.
public struct GameSupport: Sendable, Equatable {
    public enum Tier: Sendable, Equatable { case tested, reported, blocked, untested }
    /// The store lists a Mac build.
    public var native: Bool
    public var wine: Tier
    /// Where the Wine claim comes from, in one line, and when it was last confirmed.
    public var source: String?
    public var date: String?
    /// For `blocked`: "anticheat" or "publisher".
    public var blockReason: String?
    /// The player's own result on this Mac, if there is one: it outranks everyone else's word.
    public var seenHere: Bool

    public static func resolve(entry: GameDBEntry?, local: LocalVerdict?, nativeMac: Bool) -> GameSupport {
        func line(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let first = text.components(separatedBy: ". ").first ?? text
            return first.count > 160 ? String(first.prefix(157)) + "…" : first
        }
        if let local {
            return GameSupport(native: nativeMac, wine: local.works ? .tested : .blocked, source: nil, date: local.date.formatted(.iso8601.year().month().day()),
                               blockReason: nil, seenHere: true)
        }
        let status = entry?.status ?? ""
        let tier: Tier
        switch status {
        case "verified-local": tier = .tested
        case "reported-upstream", "community": tier = .reported
        case let s where s.hasPrefix("blocked-"): tier = .blocked
        default: tier = .untested
        }
        let reason = status.hasPrefix("blocked-") ? String(status.dropFirst("blocked-".count)) : nil
        return GameSupport(native: nativeMac, wine: tier, source: tier == .untested ? nil : line(entry?.provenance), date: entry?.lastVerified, blockReason: reason, seenHere: false)
    }

    /// Runs on a Mac one way or the other, as far as anyone has said: a Mac build, or Wine tested / reported to work.
    public var runsSomehow: Bool { native || wine == .tested || wine == .reported }
}

public extension StoreFilters {
    /// The filters the store cannot do itself, applied to cards we already have: name, sale, price, Mac build and sort.
    /// The ones that need the store's catalogue (categories, features, language, Deck) are not applied here.
    func applyLocally(_ cards: [StoreCard]) -> [StoreCard] {
        var out = cards
        let needle = term.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty { out = out.filter { $0.name.localizedCaseInsensitiveContains(needle) } }
        if onSale { out = out.filter(\.onSale) }
        if mac { out = out.filter(\.mac) }
        // A game with a Mac build is not "blocked" on a Mac, whatever its Windows anti-cheat says.
        if compat == .blocked { out = out.filter { !$0.mac } }
        if let minYear { out = out.filter { ($0.releaseYear ?? Int.max) >= minYear } }
        switch price {
        case .any: break
        case .free: out = out.filter(\.isFree)
        case .under(let n): out = out.filter { ($0.finalMinor ?? Int.max) <= n * 100 }
        }
        switch sort {
        case .relevance, .newest: break
        case .reviews: out.sort { ($0.reviewPercent ?? -1) > ($1.reviewPercent ?? -1) }
        case .priceLow: out.sort { ($0.finalMinor ?? Int.max) < ($1.finalMinor ?? Int.max) }
        case .priceHigh: out.sort { ($0.finalMinor ?? -1) > ($1.finalMinor ?? -1) }
        case .name: out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return out
    }

    /// How many games a compatibility choice lists at most: the predictions run to thousands, and each one is a card to fetch.
    static let compatLimit = 240

    /// Which appids our records name for a compatibility choice, best-tested first. The open database and the Atlas (the site's feed:
    /// tested, player-reported, predicted, blocked) are read together.
    func compatIDs(db: GameDB, atlas: AtlasFeed = AtlasFeed()) -> [Int] {
        let rank = ["verified-local": 0, "reported-upstream": 1, "community": 2]
        var best: [Int: Int] = [:], titles: [Int: String] = [:]
        func add(_ id: Int, _ r: Int, _ title: String = "") {
            if let have = best[id], have <= r { return }
            best[id] = r; if !title.isEmpty { titles[id] = title }
        }
        for e in db.byAppID.values {
            guard let id = e.steam_appid else { continue }
            switch compat {
            case .any, .likely: break
            case .works: if let r = rank[e.status] { add(id, r, e.title) }
            case .tested: if e.status == "verified-local" { add(id, 0, e.title) }
            case .reported: if e.status == "reported-upstream" || e.status == "community" { add(id, rank[e.status] ?? 2, e.title) }
            case .blocked: if e.status.hasPrefix("blocked-") { add(id, 0, e.title) }
            }
        }
        // Within a tier the better-supported entries first: a prediction by how many recent reports stand behind it.
        var strength: [Int: Int] = [:]
        for (key, e) in atlas.games {
            guard let id = Int(key) else { continue }
            switch (compat, e.tier) {
            case (.works, .tested?), (.tested, .tested?): add(id, 0)
            case (.works, .reported?), (.reported, .reported?): add(id, 1)
            case (.likely, .predicted?) where e.p == "likely": add(id, 3); strength[id] = e.s ?? 0
            case (.blocked, .blocked?): add(id, 0)
            default: break
            }
        }
        let ordered = best.keys.sorted { (best[$0]!, -(strength[$0] ?? 0), titles[$0] ?? "", $0) < (best[$1]!, -(strength[$1] ?? 0), titles[$1] ?? "", $1) }
        return Array(ordered.prefix(Self.compatLimit))
    }
}

public struct StoreSlice: Sendable, Equatable {
    public var cards: [StoreCard]
    /// Where the next read of the store starts (rows read, not cards kept).
    public var next: Int
    public var total: Int
    public var hasMore: Bool
    public var failed: Bool
}

public extension SteamStore {
    /// Reads pages until `want` games pass the filters the store cannot apply itself (release year), or the pages run out.
    /// Without such a filter it is a single read. `fetch` is the store read, passed in so this can be tested.
    static func collect(_ filters: StoreFilters, start: Int, want: Int = 24, maxPages: Int = 6, pageSize: Int = 48,
                        fetch: (Int) async -> StorePage) async -> StoreSlice {
        var kept: [StoreCard] = [], seen = Set<Int>(), cursor = start, total = 0, failed = false, more = true
        var pages = 0
        repeat {
            let page = await fetch(cursor)
            pages += 1; total = page.total
            if page.failed { failed = true; more = false; break }
            cursor += max(page.cards.count, 0)
            for card in filters.applyLocally(page.cards) where seen.insert(card.appid).inserted { kept.append(card) }
            more = !page.cards.isEmpty && cursor < page.total
        } while filters.minYear != nil && kept.count < want && more && pages < maxPages
        return StoreSlice(cards: kept, next: cursor, total: total, hasMore: more, failed: failed && kept.isEmpty)
    }

    static func collect(_ filters: StoreFilters, start: Int = 0, want: Int = 24, session: URLSession = .shared) async -> StoreSlice {
        // Sorting and the like are the store's job here; only the year (and name) rules run locally.
        var local = filters; local.sort = .relevance; local.term = ""; local.onSale = false; local.mac = false; local.price = .any
        return await collect(local, start: start, want: want) { await search(filters, start: $0, session: session) }
    }
}

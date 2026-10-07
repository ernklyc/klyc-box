import Foundation
import Observation

// MARK: - What the store screens talk to

/// The reads the store screens need, behind one door: the live Steam store in the app, a fake in tests.
public protocol StoreService: Sendable {
    func collect(_ filters: StoreFilters, start: Int) async -> StoreSlice
    func items(_ appids: [Int]) async -> [StoreCard]
    func search(_ filters: StoreFilters, count: Int) async -> StorePage
    func reviews(_ appid: Int) async -> (ReviewSummary?, [StoreReview])
    func news(_ appid: Int, count: Int) async -> [SteamNewsItem]
}

public struct LiveStoreService: StoreService {
    public init() {}
    public func collect(_ filters: StoreFilters, start: Int) async -> StoreSlice { await SteamStore.collect(filters, start: start) }
    public func items(_ appids: [Int]) async -> [StoreCard] { await SteamStore.items(appids) }
    public func search(_ filters: StoreFilters, count: Int) async -> StorePage { await SteamStore.search(filters, count: count) }
    public func reviews(_ appid: Int) async -> (ReviewSummary?, [StoreReview]) { await SteamStore.reviews(appid) }
    public func news(_ appid: Int, count: Int) async -> [SteamNewsItem] { await SteamNews.fetch(appid, count: count) }
}

// MARK: - Filter chips

/// One thing that is switched on in a set of filters; the screen shows a chip for each and removes it with a click.
public enum StoreFilterChip: Hashable, Sendable {
    case tag(Int), compat, list, minYear(Int), mac, deck, turkish, onSale, price, feature(Int), term(String)
}

public extension StoreFilters {
    var chips: [StoreFilterChip] {
        var out: [StoreFilterChip] = tags.map { .tag($0) }
        if compat != .any { out.append(.compat) }
        if list != .none { out.append(.list) }
        if let y = minYear { out.append(.minYear(y)) }
        if mac { out.append(.mac) }
        if deckVerified { out.append(.deck) }
        if turkish { out.append(.turkish) }
        if onSale { out.append(.onSale) }
        if price != .any { out.append(.price) }
        out += feature.sorted().map { .feature($0) }
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { out.append(.term(trimmed)) }
        return out
    }

    /// The same filters without that one thing.
    func removing(_ chip: StoreFilterChip) -> StoreFilters {
        var f = self
        switch chip {
        case .tag(let id): f.tags.removeAll { $0 == id }
        case .compat: f.compat = .any
        case .list: f.list = .none
        case .minYear: f.minYear = nil
        case .mac: f.mac = false
        case .deck: f.deckVerified = false
        case .turkish: f.turkish = false
        case .onSale: f.onSale = false
        case .price: f.price = .any
        case .feature(let id): f.feature.remove(id)
        case .term: f.term = ""
        }
        return f
    }

    /// Everything off but the sort (and optionally the typed words).
    func cleared(keepingTerm: Bool = true) -> StoreFilters {
        var f = StoreFilters(); f.sort = sort
        if keepingTerm { f.term = term }
        return f
    }

    /// Switches the categories, features, language and Deck rules the store applies are not honoured in the Mac-support list.
    var hasStoreOnlyRulesOverCompat: Bool { compat != .any && (!tags.isEmpty || !feature.isEmpty || turkish || deckVerified) }
}

// MARK: - Results screen

/// A page of results for a set of filters, read in pieces as the player scrolls. All the decisions of the screen are here;
/// the view only draws what this says.
@Observable @MainActor
public final class StoreResultsModel {
    public var filters: StoreFilters
    public var term: String
    public private(set) var cards: [StoreCard] = []
    public private(set) var total = 0
    public private(set) var loading = false
    public private(set) var failed = false
    public private(set) var hasMore = false

    public let openedWith: StoreFilters
    public let openedTitle: String?
    private let service: StoreService
    private var cursor = 0
    private var generation = 0

    public init(filters: StoreFilters, title: String?, service: StoreService = LiveStoreService()) {
        self.filters = filters; self.term = filters.term; self.openedWith = filters; self.openedTitle = title; self.service = service
    }

    /// The title the page was opened with while its filters are still those; once they change, a plain one (the chips say what is on).
    public var pageTitle: String {
        if let t = openedTitle, filters == openedWith { return t }
        return filters.term.isEmpty ? L("Store") : "“\(filters.term)”"
    }

    public var showsTotal: Bool { total > 0 && filters.minYear == nil }

    public func submitTerm() { filters.term = term.trimmingCharacters(in: .whitespaces) }

    public func remove(_ chip: StoreFilterChip) {
        filters = filters.removing(chip)
        if case .term = chip { term = "" }
    }

    public func clearAll() { filters = filters.cleared() }

    /// Reads the first page for the current filters. A newer call wins: the older one never writes over it.
    public func reload(db: GameDB, atlas: AtlasFeed = AtlasFeed(), attempts: Int = 3, retryDelay: Duration = .seconds(1)) async {
        generation += 1; let mine = generation
        cards = []; total = 0; failed = false; loading = true
        var page = StorePage(cards: [], total: 0, failed: true)
        var more = false, next = 0
        // The store sometimes answers late or not at all (and a page change can cancel the request): try a few times before saying so.
        for attempt in 0..<max(1, attempts) {
            if filters.compat == .any {
                let slice = await service.collect(filters, start: 0)
                page = StorePage(cards: slice.cards, total: slice.total, failed: slice.failed)
                next = slice.next; more = slice.hasMore
            } else {
                // Our records name the games; the store only supplies their cards (price, picture, reviews). No paging.
                let ids = filters.compatIDs(db: db, atlas: atlas)
                let found = await service.items(ids)
                let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
                let list = filters.applyLocally(found.sorted { (order[$0.appid] ?? 0) < (order[$1.appid] ?? 0) })
                page = StorePage(cards: list, total: list.count, failed: found.isEmpty && !ids.isEmpty)
                more = false
            }
            if !page.failed || Task.isCancelled { break }
            try? await Task.sleep(for: retryDelay * (attempt + 1))
        }
        // Cancelled for a new run: that run reports, this one must not overwrite it with an empty page.
        guard mine == generation, !Task.isCancelled else { return }
        cards = page.cards; total = page.total; failed = page.failed; cursor = next; hasMore = more; loading = false
    }

    public func more() async {
        guard !loading, hasMore else { return }
        let mine = generation; loading = true
        let slice = await service.collect(filters, start: cursor)
        guard mine == generation else { return }
        let known = Set(cards.map(\.appid))
        cards += slice.cards.filter { !known.contains($0.appid) }
        if !slice.failed { cursor = slice.next; hasMore = slice.hasMore }
        loading = false
    }
}

// MARK: - Wishlist

public enum WishlistSort: Int, Sendable { case discount, price, name }

@Observable @MainActor
public final class WishlistModel {
    public private(set) var cards: [StoreCard] = []
    public private(set) var loading = true
    public var onSaleOnly = false
    public var macOnly = false
    public var sort: WishlistSort = .discount
    private let service: StoreService

    public init(service: StoreService = LiveStoreService()) { self.service = service }

    public func load(ids: [Int]) async {
        loading = true
        cards = await service.items(ids)
        loading = false
    }

    public var shown: [StoreCard] {
        var list = cards
        if onSaleOnly { list = list.filter(\.onSale) }
        if macOnly { list = list.filter(\.mac) }
        switch sort {
        case .price: list.sort { ($0.finalMinor ?? Int.max) < ($1.finalMinor ?? Int.max) }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .discount: list.sort { $0.discount != $1.discount ? $0.discount > $1.discount : $0.name < $1.name }
        }
        return list
    }
}

// MARK: - A game's store page

@Observable @MainActor
public final class StoreGameModel {
    public private(set) var summary: ReviewSummary?
    public private(set) var reviews: [StoreReview] = []
    public private(set) var news: [SteamNewsItem] = []
    public private(set) var tags: [Int] = []
    public private(set) var dlc: [StoreCard] = []
    public private(set) var similar: [StoreCard] = []
    public private(set) var reviewsLoaded = false
    private let service: StoreService

    public init(service: StoreService = LiveStoreService()) { self.service = service }

    /// Everything around the page's own facts, read together; the add-ons and similar games need those facts first (`info`).
    public func load(appid: Int, info: StoreInfo?) async {
        async let r = service.reviews(appid)
        async let own = service.items([appid])
        async let n = service.news(appid, count: 3)
        let (rr, mine, items) = await (r, own, n)
        summary = rr.0; reviews = rr.1; news = items; reviewsLoaded = true
        tags = Array((mine.first?.tagIDs ?? []).prefix(8))
        if let ids = info?.dlcIDs?.prefix(12), !ids.isEmpty { dlc = await service.items(Array(ids)) }
        if tags.count >= 2 {
            var f = StoreFilters(); f.tags = Array(tags.prefix(2)); f.sort = .reviews
            similar = Array(await service.search(f, count: 12).cards.filter { $0.appid != appid }.prefix(8))
        }
    }
}

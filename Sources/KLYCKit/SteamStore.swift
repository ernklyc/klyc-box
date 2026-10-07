import Foundation

/// One game as the store lists it: enough for a tile.
public struct StoreCard: Sendable, Equatable, Identifiable {
    public var appid: Int
    public var name: String
    public var image: URL?
    public var discount: Int
    public var originalMinor: Int?
    public var finalMinor: Int?
    public var currency: String
    public var windows: Bool
    public var mac: Bool
    /// What the store itself printed, when it printed one (it knows its own currency format).
    public var priceText: String? = nil
    public var originalPriceText: String? = nil
    public var reviewPercent: Int? = nil
    public var reviewLabel: String? = nil
    public var heroImage: URL? = nil
    /// Tried when `image` does not load (not every game has the plain header file).
    public var fallbackImage: URL? = nil
    public var releaseYear: Int? = nil
    /// The category ids the store gives the game, strongest first.
    public var tagIDs: [Int] = []
    public var id: Int { appid }
    public init(appid: Int, name: String, image: URL? = nil, discount: Int = 0, originalMinor: Int? = nil, finalMinor: Int? = nil,
                currency: String = "USD", windows: Bool = true, mac: Bool = false) {
        self.appid = appid; self.name = name; self.image = image; self.discount = discount; self.originalMinor = originalMinor
        self.finalMinor = finalMinor; self.currency = currency; self.windows = windows; self.mac = mac
    }
    public var onSale: Bool { discount > 0 }
    public var isFree: Bool { finalMinor == 0 }
    public var finalText: String? { priceText ?? finalMinor.map { StoreMoney.format($0, currency: currency) } }
    public var originalText: String? { originalPriceText ?? originalMinor.map { StoreMoney.format($0, currency: currency) } }
}

public enum StoreMoney {
    /// Minor units (cents) in the currency the store answered with. The Turkish store answers in US dollars, so that is what shows.
    public static func format(_ minor: Int, currency: String) -> String {
        if minor == 0 { return "Ücretsiz" }
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency.isEmpty ? "USD" : currency; f.locale = Locale(identifier: "tr_TR")
        return f.string(from: NSNumber(value: Double(minor) / 100)) ?? "\(Double(minor) / 100) \(currency)"
    }
}

public struct StoreShelf: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var cards: [StoreCard]
}

public struct ReviewSummary: Sendable, Equatable {
    public var label: String
    public var positive: Int
    public var negative: Int
    public var total: Int { positive + negative }
    public var percent: Int { total == 0 ? 0 : Int((Double(positive) / Double(total) * 100).rounded()) }
}

public struct StoreReview: Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var positive: Bool
    public var helpful: Int
    public var hours: Int
}

public enum SteamStore {
    // MARK: parsing (separate from the network so it can be tested)

    public static func parseFeatured(_ json: Data) -> [StoreShelf] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        let wanted: [(String, String)] = [("specials", "Özel fırsatlar"), ("top_sellers", "Çok satanlar"),
                                           ("new_releases", "Yeni çıkanlar"), ("coming_soon", "Pek yakında")]
        return wanted.compactMap { key, title in
            guard let items = (root[key] as? [String: Any])?["items"] as? [[String: Any]] else { return nil }
            let cards = items.compactMap(card)
            return cards.isEmpty ? nil : StoreShelf(id: key, title: title, cards: cards)
        }
    }

    static func card(_ d: [String: Any]) -> StoreCard? {
        guard let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
        let image = (d["header_image"] as? String) ?? (d["large_capsule_image"] as? String)
        var card = StoreCard(appid: id, name: name, image: image.flatMap(URL.init(string:)), discount: d["discount_percent"] as? Int ?? 0,
                         originalMinor: d["original_price"] as? Int, finalMinor: d["final_price"] as? Int, currency: d["currency"] as? String ?? "USD",
                         windows: d["windows_available"] as? Bool ?? false, mac: d["mac_available"] as? Bool ?? false)
        card.heroImage = (d["large_capsule_image"] as? String).flatMap(URL.init(string:))
        return card
    }

    public static func parseSearch(_ json: Data) -> [StoreCard] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { d in
            guard (d["type"] as? String) == "app", let id = d["id"] as? Int, let name = d["name"] as? String else { return nil }
            let price = d["price"] as? [String: Any]
            let final = price?["final"] as? Int, initial = price?["initial"] as? Int
            let platforms = d["platforms"] as? [String: Any]
            return StoreCard(appid: id, name: name,
                             image: URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg"),
                             discount: (initial ?? 0) > 0 && (final ?? 0) < (initial ?? 0) ? 100 - Int((Double(final ?? 0) / Double(initial ?? 1) * 100).rounded()) : 0,
                             originalMinor: initial, finalMinor: final ?? (price == nil ? 0 : nil), currency: price?["currency"] as? String ?? "USD",
                             windows: platforms?["windows"] as? Bool ?? false, mac: platforms?["mac"] as? Bool ?? false)
        }
    }

    public static func parseReviews(_ json: Data) -> (ReviewSummary?, [StoreReview]) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any], (root["success"] as? Int) == 1 else { return (nil, []) }
        var summary: ReviewSummary?
        if let q = root["query_summary"] as? [String: Any], let pos = q["total_positive"] as? Int, let neg = q["total_negative"] as? Int {
            summary = ReviewSummary(label: q["review_score_desc"] as? String ?? "", positive: pos, negative: neg)
        }
        let reviews: [StoreReview] = (root["reviews"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["recommendationid"] as? String, let text = r["review"] as? String, !text.isEmpty else { return nil }
            let minutes = (r["author"] as? [String: Any])?["playtime_forever"] as? Int ?? 0
            return StoreReview(id: id, text: text, positive: r["voted_up"] as? Bool ?? true, helpful: r["votes_up"] as? Int ?? 0, hours: minutes / 60)
        }
        return (summary, reviews)
    }

    // MARK: network

    private static func get(_ urlString: String, session: URLSession) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        return try? await session.data(for: request).0
    }

    public static func featured(session: URLSession = .shared) async -> [StoreShelf] {
        await get("https://store.steampowered.com/api/featuredcategories?cc=tr&l=turkish", session: session).map(parseFeatured) ?? []
    }

    public static func search(_ term: String, session: URLSession = .shared) async -> [StoreCard] {
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), !term.isEmpty else { return [] }
        return await get("https://store.steampowered.com/api/storesearch/?term=\(q)&cc=tr&l=turkish", session: session).map(parseSearch) ?? []
    }

    /// The most helpful reviews and the overall verdict. Turkish first when there are any, else every language.
    public static func reviews(_ appid: Int, session: URLSession = .shared) async -> (ReviewSummary?, [StoreReview]) {
        for language in ["turkish", "all"] {
            guard let data = await get("https://store.steampowered.com/appreviews/\(appid)?json=1&language=\(language)&purchase_type=all&num_per_page=5&filter=all&l=turkish", session: session) else { continue }
            let result = parseReviews(data)
            if !result.1.isEmpty || language == "all" { return result }
        }
        return (nil, [])
    }
}

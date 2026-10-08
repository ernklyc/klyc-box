import Foundation

/// Public Steam data that needs no key: a game's news, a wishlist, current prices.
public struct SteamNewsItem: Codable, Sendable, Equatable, Identifiable {
    public var title: String
    public var url: URL?
    public var date: Date
    public var feed: String?
    public var text: String
    public var id: String { url?.absoluteString ?? title }
}

public enum SteamNews {
    /// News text carries BBCode ([b], [url=…], [img]…) and HTML: plain text only.
    public static func plain(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"\[/?[A-Za-z0-9*]+(=[^\]]*)?\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
        return s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func parse(_ json: Data) -> [SteamNewsItem] {
        struct Raw: Decodable {
            struct Wrapper: Decodable { struct Item: Decodable { let title: String; let url: String?; let date: Double; let feedlabel: String?; let contents: String? }; let newsitems: [Item] }
            let appnews: Wrapper
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: json) else { return [] }
        return raw.appnews.newsitems.map {
            SteamNewsItem(title: $0.title, url: $0.url.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }, date: Date(timeIntervalSince1970: $0.date), feed: $0.feedlabel, text: plain($0.contents ?? ""))
        }
    }

    public static func fetch(_ appid: Int, count: Int = 4, session: URLSession = .shared) async -> [SteamNewsItem] {
        guard let url = URL(string: "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=\(appid)&count=\(count)&maxlength=320&format=json") else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        guard let (data, _) = try? await session.data(for: request) else { return [] }
        return parse(data)
    }
}

public struct SteamPrice: Sendable, Equatable {
    public var appid: Int
    public var final: Int          // minor units (cents)
    public var initial: Int
    public var currency: String
    public var discount: Int       // percent
    public var formatted: String?
    public var onSale: Bool { discount > 0 }
}

public enum SteamWishlist {
    /// The wishlist ids of a public profile: `IWishlistService/GetWishlist`, no key.
    public static func parse(_ json: Data) -> [Int] {
        struct Raw: Decodable { struct R: Decodable { struct I: Decodable { let appid: Int }; let items: [I]? }; let response: R }
        return (try? JSONDecoder().decode(Raw.self, from: json))?.response.items?.map(\.appid) ?? []
    }

    public static func fetch(steamID64: Int64, session: URLSession = .shared) async -> [Int] {
        guard let url = URL(string: "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=\(steamID64)") else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        guard let (data, _) = try? await session.data(for: request) else { return [] }
        return parse(data)
    }

    /// Prices for many games in one question (the store allows that only when asked for prices alone).
    public static func parsePrices(_ json: Data) -> [Int: SteamPrice] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [:] }
        var out: [Int: SteamPrice] = [:]
        for (key, value) in root {
            guard let appid = Int(key), let entry = value as? [String: Any], entry["success"] as? Bool == true,
                  let data = entry["data"] as? [String: Any], let p = data["price_overview"] as? [String: Any],
                  let final = p["final"] as? Int, let initial = p["initial"] as? Int else { continue }
            out[appid] = SteamPrice(appid: appid, final: final, initial: initial, currency: p["currency"] as? String ?? "",
                                    discount: p["discount_percent"] as? Int ?? 0, formatted: p["final_formatted"] as? String)
        }
        return out
    }

    public static func prices(_ appids: [Int], session: URLSession = .shared) async -> [Int: SteamPrice] {
        var out: [Int: SteamPrice] = [:]
        var start = 0
        while start < appids.count {
            let chunk = appids[start..<min(start + 40, appids.count)].map(String.init).joined(separator: ",")
            start += 40
            guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(chunk)&filters=price_overview&cc=tr&l=\(StoreLanguage.steam)") else { continue }
            var request = URLRequest(url: url); request.timeoutInterval = 15
            if let (data, _) = try? await session.data(for: request) { out.merge(parsePrices(data)) { a, _ in a } }
        }
        return out
    }
}

/// Friends the player wants to hear about when they come online (account ids), kept on this Mac.
public struct FriendWatchStore: Sendable {
    public let file: URL
    public init(paths: KLYCPaths = KLYCPaths()) { file = paths.home.appending(path: "friend-watch.json") }
    public init(file: URL) { self.file = file }

    public func all() -> Set<Int> {
        guard let data = try? Data(contentsOf: file), let ids = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
        return Set(ids)
    }

    public func set(_ id: Int, watched: Bool) {
        var ids = all()
        if watched { ids.insert(id) } else { ids.remove(id) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ids.sorted()) { try? data.write(to: file, options: .atomic) }
    }

    /// Who just came online: watched friends read as offline before and online (or playing) now.
    public static func cameOnline(watched: Set<Int>, before: [Int: FriendPresence], after: [Int: FriendPresence]) -> [Int] {
        watched.filter { id in
            let now = after[id]?.state, was = before[id]?.state
            // From a read that said offline: an unreadable page (unknown) turning into online is not news.
            return (now == .online || now == .inGame) && was == .offline
        }.sorted()
    }
}

/// What KLYC-Box itself saw: sessions it watched, summed for a recent stretch.
public enum SessionStats {
    public struct Summary: Sendable, Equatable { public var sessions: Int; public var seconds: Int; public var top: [(title: String, seconds: Int)]
        public static func == (l: Summary, r: Summary) -> Bool { l.sessions == r.sessions && l.seconds == r.seconds && l.top.map(\.title) == r.top.map(\.title) } }

    public static func read(from logs: URL) -> [SessionRecord] {
        guard let text = try? String(contentsOf: logs.appending(path: "sessions.jsonl"), encoding: .utf8) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(SessionRecord.self, from: Data($0.utf8)) }
    }

    public static func summary(_ records: [SessionRecord], since: Date) -> Summary {
        let recent = records.filter { $0.ended >= since && $0.seconds >= 10 }
        var perGame: [String: Int] = [:]
        for r in recent { perGame[r.title, default: 0] += r.seconds }
        return Summary(sessions: recent.count, seconds: recent.reduce(0) { $0 + $1.seconds },
                       top: perGame.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) })
    }
}

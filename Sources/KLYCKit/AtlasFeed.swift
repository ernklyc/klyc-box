import Foundation

/// What the KLYC-Box site (the Atlas) knows about one Steam game, in the short keys of its public feed.
/// Compatibility information only: never recipes, installer addresses or launch arguments.
public struct AtlasEntry: Codable, Equatable, Sendable {
    public enum Tier: String, Sendable { case tested, reported, predicted, blocked }

    /// tested | reported | predicted | blocked
    public var t: String
    /// Average player rating, 1 to 5.
    public var r: Double?
    /// Number of player reports.
    public var n: Int?
    /// Graphics mode on record (dxmt, d3dmetal, dxvk, vkd3d, wined3d).
    public var m: String?
    /// Chip generations reported to work ("M1" ... "M5").
    public var c: [String]?
    /// A native Mac version exists.
    public var v: Bool?
    /// Anti-cheat names that trouble a Mac.
    public var a: [String]?
    /// Genre ids, and the release year.
    public var g: [String]?
    public var y: Int?
    /// Predictions only: strength (likely | maybe | unlikely), ProtonDB class, recent ProtonDB reports.
    public var p: String?
    public var q: String?
    public var s: Int?
    /// KLYC-Box players (from the app's anonymous reports): [reports, average rating, share that say it works]. Only with 3 or more reports.
    public var u: [Double]?

    public var tier: Tier? { Tier(rawValue: t) }
}

public struct AtlasFeed: Codable, Equatable, Sendable {
    public var v: Int
    public var generated: String
    public var games: [String: AtlasEntry]

    public init(v: Int = 1, generated: String = "", games: [String: AtlasEntry] = [:]) {
        self.v = v; self.generated = generated; self.games = games
    }

    public subscript(appid: Int) -> AtlasEntry? { games[String(appid)] }
    public var isEmpty: Bool { games.isEmpty }
}

/// Where the Atlas lives: the project's own site, a subdomain of the author's domain (nobody else can publish there). It can be overridden with `KLYCAtlasURL` in the app's Info.plist or the `KLYC_ATLAS_URL` environment
/// variable (development); an invalid override disables the feature instead of falling back.
public enum AtlasSite {
    public static let defaultAddress = "https://klycbox.ernklyc.dev"

    public static func baseURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                               info: [String: Any]? = Bundle.main.infoDictionary) -> URL? {
        let raw = environment["KLYC_ATLAS_URL"] ?? (info?["KLYCAtlasURL"] as? String) ?? defaultAddress
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")),
              url.host != nil else { return nil }
        return url
    }

    public static func feedURL(base: URL? = baseURL()) -> URL? { base?.appending(path: "data/atlas-feed.json") }
    /// The game's page. Games the site renders in the browser (the prediction layer) are reached by /game/<id> too: the host's
    /// 404 page sends them to the right place.
    public static func gamePage(appid: Int, base: URL? = baseURL()) -> URL? { base?.appending(path: "game/\(appid)/") }
    public static func privacyPage(base: URL? = baseURL()) -> URL? { base?.appending(path: "privacy/") }
}

/// The feed, kept in a cache file: read at launch, refreshed in the background at most once a day, with
/// If-None-Match so an unchanged feed costs a few hundred bytes. Any failure leaves what was there.
public struct AtlasFeedStore: Sendable {
    public let paths: KLYCPaths
    public init(paths: KLYCPaths = KLYCPaths()) { self.paths = paths }

    var file: URL { paths.home.appending(path: "atlas-feed.json", directoryHint: .notDirectory) }
    var etagFile: URL { paths.home.appending(path: "atlas-feed.etag", directoryHint: .notDirectory) }

    public func cached() -> AtlasFeed {
        guard let data = try? Data(contentsOf: file), let feed = try? JSONDecoder().decode(AtlasFeed.self, from: data), feed.v == 1 else { return AtlasFeed() }
        return feed
    }

    /// Fetches a newer feed when the cache is older than `maxAge`. Returns the feed now in effect.
    public func refresh(url: URL?, session: URLSession = .shared, maxAge: TimeInterval = 86_400, now: Date = Date()) async -> AtlasFeed {
        guard let url else { return cached() }
        if let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date, now.timeIntervalSince(modified) < maxAge {
            return cached()
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let etag = try? String(contentsOf: etagFile, encoding: .utf8), !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return cached() }
        if http.statusCode == 304 {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
            return cached()
        }
        guard (200..<300).contains(http.statusCode), let feed = try? JSONDecoder().decode(AtlasFeed.self, from: data), feed.v == 1, !feed.isEmpty else { return cached() }
        try? paths.ensure()
        try? data.write(to: file, options: .atomic)
        if let etag = http.value(forHTTPHeaderField: "ETag") { try? etag.write(to: etagFile, atomically: true, encoding: .utf8) }
        return feed
    }
}

/// The Atlas's words, in the app's languages.
public enum AtlasText {
    public static func modeName(_ id: String) -> String {
        ["dxmt": "DXMT", "d3dmetal": "D3DMetal", "dxvk": "DXVK", "vkd3d": "vkd3d-proton", "wined3d": "Wine D3D"][id] ?? id
    }

    public static func genreName(_ id: String) -> String {
        switch id {
        case "action": return L("Action")
        case "shooter": return L("Shooter")
        case "rpg": return L("Role-playing")
        case "strategy": return L("Strategy")
        case "simulation": return L("Simulation")
        case "racing": return L("Racing")
        case "adventure": return L("Adventure")
        case "puzzle": return L("Puzzle")
        case "platformer": return L("Platformer")
        case "sports": return L("Sports")
        case "horror": return L("Horror")
        case "survival": return L("Survival")
        case "roguelike": return L("Roguelike")
        case "fighting": return L("Fighting")
        case "card": return L("Card and board")
        case "online": return L("Online")
        case "casual": return L("Casual and idle")
        case "music": return L("Rhythm and music")
        default: return id
        }
    }

    /// One sentence on how solid the Atlas's knowledge is.
    public static func headline(_ e: AtlasEntry) -> String {
        switch e.tier {
        case .tested:
            return L("The Highball project tried it on a Mac.")
        case .reported:
            let count = e.n ?? 0
            let base = count == 1 ? L("1 player reported it.") : String(format: L("%d players reported it."), count)
            return e.r.map { base + " " + String(format: L("Average rating %.1f of 5."), $0) } ?? base
        case .predicted:
            switch e.p {
            case "likely": return L("A prediction, not a test: it will probably run.")
            case "unlikely": return L("A prediction, not a test: a slim chance it runs.")
            default: return L("A prediction, not a test: unclear whether it runs.")
            }
        case .blocked:
            let names = (e.a ?? []).joined(separator: ", ")
            return names.isEmpty ? L("Blocked on a Mac.") : String(format: L("Blocked on a Mac by %@."), names)
        case nil:
            return L("Nothing is known about it yet.")
        }
    }

    /// Extra facts, each a short line.
    public static func details(_ e: AtlasEntry) -> [String] {
        var lines: [String] = []
        if let c = e.c, !c.isEmpty { lines.append(String(format: L("Reported working on %@."), c.joined(separator: ", "))) }
        if let m = e.m { lines.append(String(format: L("Graphics mode on record: %@."), modeName(m))) }
        if e.v == true { lines.append(L("A native Mac version exists.")) }
        if let u = e.u, u.count == 3 {
            lines.append(String(format: L("KLYC-Box players: %d reports, average %.1f of 5, %d%% say it works."), Int(u[0]), u[1], Int((u[2] * 100).rounded())))
        }
        let facts = [e.y.map(String.init), (e.g ?? []).prefix(3).map(genreName).joined(separator: ", ")].compactMap { $0 }.filter { !$0.isEmpty }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }
        return lines
    }
}

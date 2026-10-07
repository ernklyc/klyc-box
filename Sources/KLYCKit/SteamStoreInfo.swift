import Foundation

/// What Steam's store says about a game: the description, platforms, requirements. No key needed; cached on disk.
public struct StoreInfo: Codable, Sendable, Equatable {
    public struct Requirements: Codable, Sendable, Equatable {
        public var minimum: String?
        public var recommended: String?
        public init(minimum: String? = nil, recommended: String? = nil) { self.minimum = minimum; self.recommended = recommended }
        public var isEmpty: Bool { minimum == nil && recommended == nil }
    }
    public var appid: Int
    public var name: String
    public var shortDescription: String?
    public var genres: [String]
    public var windows: Bool
    public var mac: Bool
    public var linux: Bool
    public var releaseDate: String?
    public var metacritic: Int?
    public var developers: [String]
    public var price: String?
    public var pc: Requirements
    public var macRequirements: Requirements
    public var fetched: Date
    /// Store category ids (30 = Steam Workshop). Absent in copies cached before this field existed.
    public var categoryIDs: [Int]? = nil
    /// Pictures and trailers from the store page; absent in copies cached before they were kept.
    public var screenshots: [URL]? = nil
    public var trailers: [Trailer]? = nil
    public struct Trailer: Codable, Sendable, Equatable { public var name: String; public var thumbnail: URL?; public var stream: URL }
    /// The long text of the page, who made and published it, the languages, add-ons, and how much there is to do.
    public var about: String? = nil
    public var publishers: [String]? = nil
    public var languages: [String]? = nil
    public var dlcIDs: [Int]? = nil
    public var achievementsTotal: Int? = nil
    public var recommendations: Int? = nil
    public var website: URL? = nil
    public var controllerSupport: String? = nil
    /// Set when the fields above were read (a copy cached before them has to be fetched again).
    public var extended: Bool? = nil
    public var hasTurkish: Bool { languages?.contains { $0.localizedCaseInsensitiveContains("Türkçe") || $0.localizedCaseInsensitiveContains("Turkish") } ?? false }
    public var hasWorkshop: Bool { categoryIDs?.contains(30) ?? false }
}

public enum SteamStoreInfo {
    /// Steam answers `"pc_requirements": []` for none and an object for some: both decode.
    private struct RawRequirements: Decodable {
        var minimum: String?; var recommended: String?
        init(from decoder: Decoder) throws {
            if let c = try? decoder.container(keyedBy: Keys.self) {
                minimum = try? c.decodeIfPresent(String.self, forKey: .minimum)
                recommended = try? c.decodeIfPresent(String.self, forKey: .recommended)
            }
        }
        enum Keys: String, CodingKey { case minimum, recommended }
    }
    private struct Raw: Decodable {
        struct Data: Decodable {
            struct Genre: Decodable { let description: String }
            struct Platforms: Decodable { let windows: Bool?; let mac: Bool?; let linux: Bool? }
            struct Release: Decodable { let date: String? }
            struct Meta: Decodable { let score: Int? }
            struct Category: Decodable { let id: Int }
            struct Shot: Decodable { let path_full: String? }
            struct Count: Decodable { let total: Int? }
            struct Movie: Decodable { let name: String?; let thumbnail: String?; let hls_h264: String? }
            struct Price: Decodable { let final_formatted: String? }
            let name: String
            let categories: [Category]?
            let screenshots: [Shot]?
            let about_the_game: String?
            let publishers: [String]?
            let supported_languages: String?
            let dlc: [Int]?
            let achievements: Count?
            let recommendations: Count?
            let website: String?
            let controller_support: String?
            let movies: [Movie]?
            let short_description: String?
            let genres: [Genre]?
            let platforms: Platforms?
            let release_date: Release?
            let metacritic: Meta?
            let developers: [String]?
            let price_overview: Price?
            let pc_requirements: RawRequirements?
            let mac_requirements: RawRequirements?
        }
        let success: Bool
        let data: Data?
    }

    public static func parse(appid: Int, json: Data, now: Date = Date()) -> StoreInfo? {
        guard let map = try? JSONDecoder().decode([String: Raw].self, from: json),
              let raw = map[String(appid)], raw.success, let d = raw.data else { return nil }
        func clean(_ r: RawRequirements?) -> StoreInfo.Requirements {
            StoreInfo.Requirements(minimum: r?.minimum.map(plainText), recommended: r?.recommended.map(plainText))
        }
        var info = StoreInfo(appid: appid, name: d.name, shortDescription: d.short_description.map(plainText),
                             genres: d.genres?.map(\.description) ?? [], windows: d.platforms?.windows ?? false,
                             mac: d.platforms?.mac ?? false, linux: d.platforms?.linux ?? false, releaseDate: d.release_date?.date,
                             metacritic: d.metacritic?.score, developers: d.developers ?? [], price: d.price_overview?.final_formatted,
                             pc: clean(d.pc_requirements), macRequirements: clean(d.mac_requirements), fetched: now)
        info.categoryIDs = d.categories?.map(\.id) ?? []
        info.screenshots = (d.screenshots ?? []).compactMap { $0.path_full.flatMap(URL.init(string:)) }
        info.trailers = (d.movies ?? []).compactMap { m in
            m.hls_h264.flatMap(URL.init(string:)).map { StoreInfo.Trailer(name: m.name ?? "", thumbnail: m.thumbnail.flatMap(URL.init(string:)), stream: $0) }
        }
        info.about = d.about_the_game.map(plainText)
        info.publishers = d.publishers
        info.languages = d.supported_languages.map(languageList)
        info.dlcIDs = d.dlc
        info.achievementsTotal = d.achievements?.total
        info.recommendations = d.recommendations?.total
        if let site = d.website.flatMap(URL.init(string:)), ["http", "https"].contains(site.scheme?.lowercased() ?? "") { info.website = site }
        info.controllerSupport = d.controller_support
        info.extended = true
        return info
    }

    /// "English<strong>*</strong>, French, ..." as a list; the asterisk marks full audio, which is dropped here.
    static func languageList(_ html: String) -> [String] {
        let first = html.components(separatedBy: "<br>").first ?? html
        return first.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "*", with: "")
            .components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Store text is HTML: lines for breaks and list items, tags gone, entities decoded.
    public static func plainText(_ html: String) -> String {
        var s = html
        for (a, b) in [("<br>", "\n"), ("<br/>", "\n"), ("<br />", "\n"), ("</li>", "\n"), ("<li>", "• "), ("</ul>", "\n"), ("</p>", "\n")] {
            s = s.replacingOccurrences(of: a, with: b, options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&reg;", "®"), ("&trade;", "™")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    // MARK: fetch and cache

    public static let maxAge: TimeInterval = 7 * 24 * 3600

    static func cacheFile(_ appid: Int, paths: KLYCPaths) -> URL { paths.home.appending(path: "store-info/\(appid).json") }

    public static func cached(_ appid: Int, paths: KLYCPaths = KLYCPaths(), now: Date = Date()) -> StoreInfo? {
        guard let data = try? Data(contentsOf: cacheFile(appid, paths: paths)),
              let info = try? JSONDecoder.klycbox.decode(StoreInfo.self, from: data),
              now.timeIntervalSince(info.fetched) < maxAge, info.categoryIDs != nil, info.screenshots != nil, info.extended == true else { return nil }
        return info
    }

    public static func load(_ appid: Int, paths: KLYCPaths = KLYCPaths(), session: URLSession = .shared) async -> StoreInfo? {
        if let hit = cached(appid, paths: paths) { return hit }
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appid)&l=turkish&cc=tr") else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        guard let (data, _) = try? await session.data(for: request), let info = parse(appid: appid, json: data) else { return nil }
        let file = cacheFile(appid, paths: paths)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder.klycbox.encode(info) { try? encoded.write(to: file, options: .atomic) }
        return info
    }
}

/// Comparing a requirement text with this Mac: memory and free disk space, which are the numbers a store page states plainly.
/// The graphics card is not compared: a Windows card name says nothing about an Apple chip.
public enum SpecCheck {
    public struct Check: Equatable, Sendable { public var label: String; public var need: String; public var have: String; public var ok: Bool }

    static func gigabytes(_ line: String) -> Double? {
        guard let m = line.range(of: #"(\d+(?:[.,]\d+)?)\s*(GB|MB|TB)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let token = String(line[m]).uppercased().replacingOccurrences(of: ",", with: ".")
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard let n = Double(digits) else { return nil }
        if token.hasSuffix("TB") { return n * 1024 }
        return token.hasSuffix("MB") ? n / 1024 : n
    }

    /// Memory and storage the requirement text asks for, in GB.
    public static func needs(_ text: String) -> (ram: Double?, disk: Double?) {
        var ram: Double?, disk: Double?
        for raw in text.split(separator: "\n") {
            let line = String(raw), lower = line.lowercased()
            if ram == nil, lower.contains("memory") || lower.contains("bellek") || lower.hasPrefix("• ram") || lower.contains(" ram:") { ram = gigabytes(line) }
            if disk == nil, lower.contains("storage") || lower.contains("depolama") || lower.contains("hard drive") || lower.contains("disk") || lower.contains("sabit") { disk = gigabytes(line) }
        }
        return (ram, disk)
    }

    public static func compare(_ text: String, ramBytes: UInt64, freeDiskBytes: Int64, labels: (ram: String, disk: String)) -> [Check] {
        let need = needs(text), ramGB = Double(ramBytes) / 1_073_741_824, diskGB = Double(freeDiskBytes) / 1_073_741_824
        var out: [Check] = []
        if let r = need.ram { out.append(Check(label: labels.ram, need: String(format: "%.0f GB", r), have: String(format: "%.0f GB", ramGB), ok: ramGB + 0.5 >= r)) }
        if let d = need.disk { out.append(Check(label: labels.disk, need: String(format: "%.0f GB", d), have: String(format: "%.0f GB", diskGB), ok: diskGB >= d)) }
        return out
    }
}

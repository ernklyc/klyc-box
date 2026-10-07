import Foundation

/// A game's achievements as the Steam client keeps them on disk: the list the game defines, and which this account has unlocked.
public struct SteamAchievements: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var detail: String?
        public var hidden: Bool
        public var unlockedAt: Date?
        public var unlocked: Bool { unlockedAt != nil }
    }
    public var items: [Item]
    public var unlockedCount: Int { items.filter(\.unlocked).count }

    /// Reads `appcache/stats/UserGameStatsSchema_<app>.bin` and `UserGameStats_<account>_<app>.bin`. Nil when the game never ran here
    /// or defines none.
    public static func load(steamRoot: URL, account: Int, appid: Int, language: String = "turkish") -> SteamAchievements? {
        let stats = steamRoot.appending(path: "appcache/stats")
        guard let schemaData = try? Data(contentsOf: stats.appending(path: "UserGameStatsSchema_\(appid).bin")),
              let userData = try? Data(contentsOf: stats.appending(path: "UserGameStats_\(account)_\(appid).bin")) else { return nil }
        return parse(schema: BinaryVDF.parse(schemaData), user: BinaryVDF.parse(userData), appid: appid, language: language)
    }

    public static func parse(schema: BinaryVDF, user: BinaryVDF, appid: Int, language: String = "turkish") -> SteamAchievements? {
        guard let statsNode = (schema[String(appid)] ?? schema)["stats"], let cache = user["cache"] else { return nil }
        func text(_ node: BinaryVDF?) -> String? { node?[language]?.stringValue ?? node?["english"]?.stringValue }
        var items: [Item] = []
        for statID in statsNode.keys.sorted(by: { (Int($0) ?? 0) < (Int($1) ?? 0) }) {
            guard let bits = statsNode[statID]?["bits"] else { continue }
            let mask = cache[statID]?["data"]?.intValue ?? 0
            let times = cache[statID]?["AchievementTimes"]
            for bit in bits.keys.sorted(by: { (Int($0) ?? 0) < (Int($1) ?? 0) }) {
                guard let node = bits[bit], let name = node["name"]?.stringValue, let n = Int(bit) else { continue }
                let display = node["display"]
                let at = times?[bit]?.intValue.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
                // The bit in the stat's mask is the unlock flag; a time without it still counts as unlocked.
                let unlocked = (mask >> n) & 1 == 1 || at != nil
                items.append(Item(id: name, name: text(display?["name"]) ?? name, detail: text(display?["desc"]),
                                  hidden: (display?["hidden"]?.intValue ?? 0) == 1,
                                  unlockedAt: unlocked ? (at ?? Date(timeIntervalSince1970: 1)) : nil))
            }
        }
        return items.isEmpty ? nil : SteamAchievements(items: items)
    }
}

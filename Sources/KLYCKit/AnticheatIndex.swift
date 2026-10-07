import Foundation

/// Which Steam games ship an anti-cheat, from klyc-db's `anticheat.json` (a copy of Are We
/// Anti-Cheat Yet?, MIT). The file's own verdicts are a Linux reading; KLYC-Box adds the Mac one
/// only where a game has a row of its own. Here the question is narrower and answerable: does
/// this game carry an anti-cheat that is known to refuse to start under Wine? Where it does and
/// nobody has tested the game here, the app says so before the player buys or installs.
public struct AnticheatIndex: Sendable {
    public struct Entry: Sendable, Equatable {
        public var names: [String]
        public var linuxStatus: String?
    }

    public let byAppID: [Int: Entry]

    public init(byAppID: [Int: Entry] = [:]) { self.byAppID = byAppID }

    public init(file: URL?) {
        guard let file, let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let games = root["games"] as? [String: [String: Any]] else { self.init(); return }
        var out: [Int: Entry] = [:]
        for (_, g) in games {
            guard let appid = g["steam_appid"] as? Int, let names = g["anticheats"] as? [String], !names.isEmpty else { continue }
            out[appid] = Entry(names: names, linuxStatus: g["linuxStatus"] as? String)
        }
        self.init(byAppID: out)
    }

    /// The anti-cheats that are known to stop a game under Wine, or are kernel-level and so
    /// out of reach there. VAC and PunkBuster are user-mode and run fine under Wine, so a game
    /// that only has those gets no notice: a warning that is usually wrong teaches people to
    /// ignore the one that is right.
    public static let risky: Set<String> = [
        "easy anti-cheat", "battleye", "xigncode3", "nprotect gameguard", "nexon game security", "anti-cheat expert",
        "netease anti-cheat expert", "ea anticheat", "ricochet", "hyperion", "denuvo anti-cheat", "faceit",
    ]

    /// The risky anti-cheats of a game, empty when it has none or is unknown.
    public func riskyNames(appid: Int) -> [String] {
        (byAppID[appid]?.names ?? []).filter { Self.risky.contains($0.lowercased()) }
    }
}

public extension GameDB {
    /// A heads-up for a Steam game with a risky anti-cheat and no row of its own saying more:
    /// a row that is blocked already says it, and a row with an `anticheat` field carries its
    /// own note. Empty for everything else.
    func anticheatNotice(appid: Int) -> [String] {
        if let entry = byAppID[appid], entry.isBlocked || entry.anticheat != nil || entry.status == "verified-local" { return [] }
        return anticheat.riskyNames(appid: appid)
    }
}

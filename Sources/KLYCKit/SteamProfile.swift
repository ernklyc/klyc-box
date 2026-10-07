import Foundation

/// How long the signed-in account has played one game, as Steam's own client keeps it on disk (minutes).
public struct SteamPlay: Sendable, Equatable {
    public var minutes: Int
    public var lastPlayed: Date?
    public var lastTwoWeeksMinutes: Int
}

/// The state the account chose for itself, as Steam stores it (`ePersonaState`).
public enum SteamPersona: Int, Sendable {
    case offline = 0, online = 1, busy = 2, away = 3, snooze = 4, lookingToTrade = 5, lookingToPlay = 6, invisible = 7
}

public struct SteamFriend: Sendable, Equatable, Identifiable {
    public var accountID: Int
    public var name: String
    public var avatarHash: String?
    public var id: Int { accountID }
    public init(accountID: Int, name: String, avatarHash: String? = nil) { self.accountID = accountID; self.name = name; self.avatarHash = avatarHash }
    /// The 64-bit id the community pages use.
    public var steamID64: Int64 { SteamProfile.base + Int64(accountID) }
}

/// What the Steam client already knows about the account in its environment: name, avatar, hours per game and the friend
/// list. Read from files, no network and no key; the friends' online state is separate (`SteamPresence`).
public struct SteamProfile: Sendable {
    public static let base: Int64 = 76_561_197_960_265_728

    public var accountID: Int
    public var steamID64: Int64
    public var personaName: String
    public var avatar: URL?
    public var plays: [Int: SteamPlay]
    public var friends: [SteamFriend]
    /// The chosen state, from the client's own file; written when the client saves, so it can trail a change by a moment.
    public var persona: SteamPersona?

    public var totalMinutes: Int { plays.values.reduce(0) { $0 + $1.minutes } }
    public var lastTwoWeeksMinutes: Int { plays.values.reduce(0) { $0 + $1.lastTwoWeeksMinutes } }
    public var gamesPlayed: Int { plays.values.filter { $0.minutes > 0 }.count }

    /// The most played games, longest first.
    public func top(_ n: Int) -> [(appid: Int, play: SteamPlay)] {
        plays.filter { $0.value.minutes > 0 }.sorted { $0.value.minutes > $1.value.minutes }.prefix(n).map { ($0.key, $0.value) }
    }

    /// A signed-in account exists: the cheap check (no parsing of the big config files) for code that runs often.
    public static func hasAccount(driveC: URL) -> Bool {
        let file = driveC.appending(path: "Program Files (x86)/Steam/config/loginusers.vdf")
        return ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }

    public static func load(driveC: URL) -> SteamProfile? {
        let steam = driveC.appending(path: "Program Files (x86)/Steam")
        guard let login = try? String(contentsOf: steam.appending(path: "config/loginusers.vdf"), encoding: .utf8) else { return nil }
        let users = TextVDF.parse(login)["users"]?.children ?? []
        // The account last signed in.
        guard let user = users.max(by: { ($0.int("Timestamp") ?? 0) < ($1.int("Timestamp") ?? 0) }), let id64 = Int64(user.key) else { return nil }
        let account = Int(id64 - base)
        let configFile = steam.appending(path: "userdata/\(account)/config/localconfig.vdf")
        let parsed = (try? String(contentsOf: configFile, encoding: .utf8)).map { TextVDF.parse($0) }
        let config = parsed?["UserLocalConfigStore"] ?? parsed
        let store = config?["Software"]?["Valve"]?["Steam"]

        var plays: [Int: SteamPlay] = [:]
        for app in store?["apps"]?.children ?? [] {
            guard let appid = Int(app.key), let minutes = app.int("Playtime") else { continue }
            plays[appid] = SteamPlay(minutes: minutes, lastPlayed: app.int("LastPlayed").flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                                     lastTwoWeeksMinutes: app.int("Playtime2wks") ?? 0)
        }
        var friends: [SteamFriend] = []
        for node in config?["friends"]?.children ?? [] {
            guard let fid = Int(node.key), fid != account, let name = node.string("name") else { continue }
            friends.append(SteamFriend(accountID: fid, name: name, avatarHash: node.string("avatar")))
        }
        // "FriendStoreLocalPrefs_<account>" holds a small JSON with the chosen state.
        var persona: SteamPersona?
        if let prefs = config?["WebStorage"]?.string("FriendStoreLocalPrefs_\(account)"),
           let obj = try? JSONSerialization.jsonObject(with: Data(prefs.utf8)) as? [String: Any], let n = obj["ePersonaState"] as? Int {
            persona = SteamPersona(rawValue: n)
        }
        let avatar = steam.appending(path: "config/avatarcache/\(id64).png")
        return SteamProfile(accountID: account, steamID64: id64, personaName: user.string("PersonaName") ?? user.string("AccountName") ?? "Steam",
                            avatar: FileManager.default.fileExists(atPath: avatar.path) ? avatar : nil, plays: plays,
                            friends: friends.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, persona: persona)
    }
}

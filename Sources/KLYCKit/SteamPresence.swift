import Foundation

/// A friend's online state as Steam's public community page states it. Only public profiles tell; a private one is "unknown".
public struct FriendPresence: Sendable, Equatable {
    public enum State: String, Sendable { case online, offline, inGame, unknown }
    public var state: State
    public var message: String?
    public var gameName: String?
    public var appid: Int?
    public var isPlaying: Bool { state == .inGame }

    public init(state: State, message: String? = nil, gameName: String? = nil, appid: Int? = nil) {
        self.state = state; self.message = message; self.gameName = gameName; self.appid = appid
    }
}

public enum SteamPresence {
    static func tag(_ name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"), let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        var text = String(xml[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<![CDATA["), text.hasSuffix("]]>") { text = String(text.dropFirst(9).dropLast(3)) }
        return text.isEmpty ? nil : text
    }

    /// Parses `https://steamcommunity.com/profiles/<id>/?xml=1`.
    public static func parse(xml: String) -> FriendPresence {
        guard let online = tag("onlineState", in: xml) else { return FriendPresence(state: .unknown) }
        // A profile that is not public answers "offline" to anyone who is not signed in: that says nothing about the person.
        if let privacy = tag("privacyState", in: xml), privacy != "public" { return FriendPresence(state: .unknown, message: privacy) }
        let message = tag("stateMessage", in: xml)
        if online == "in-game" {
            let link = tag("gameLink", in: xml)
            let appid = link.flatMap { $0.split(separator: "/").last }.flatMap { Int($0) }
            return FriendPresence(state: .inGame, message: message, gameName: tag("gameName", in: xml), appid: appid)
        }
        return FriendPresence(state: online == "online" ? .online : .offline, message: message)
    }

    /// Asks the community page of each friend, a few at a time. A refusal (too many requests) stops the run and
    /// returns what was read; the caller shows the rest as unknown and tries again later.
    public static func fetch(_ friends: [SteamFriend], session: URLSession = .shared, concurrency: Int = 6) async -> [Int: FriendPresence] {
        var result: [Int: FriendPresence] = [:]
        var index = 0
        var refused = false
        while index < friends.count, !refused {
            let batch = Array(friends[index..<min(index + concurrency, friends.count)])
            index += concurrency
            await withTaskGroup(of: (Int, FriendPresence?, Bool).self) { group in
                for friend in batch {
                    group.addTask {
                        guard let url = URL(string: "https://steamcommunity.com/profiles/\(friend.steamID64)/?xml=1") else { return (friend.accountID, nil, false) }
                        var request = URLRequest(url: url); request.timeoutInterval = 8
                        guard let (data, response) = try? await session.data(for: request) else { return (friend.accountID, nil, false) }
                        if (response as? HTTPURLResponse)?.statusCode == 429 { return (friend.accountID, nil, true) }
                        return (friend.accountID, parse(xml: String(decoding: data, as: UTF8.self)), false)
                    }
                }
                for await (id, presence, wasRefused) in group {
                    if let presence { result[id] = presence }
                    if wasRefused { refused = true }
                }
            }
        }
        return result
    }
}

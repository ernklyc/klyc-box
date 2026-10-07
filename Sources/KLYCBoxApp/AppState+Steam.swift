import Foundation
import KLYCKit

/// Steam inside KLYC-Box: hours per game and the friend list from Steam's own files, friends' state from public
/// community pages, store details and requirements, and the status switch (online, away, invisible…).
extension AppState {
    /// The environment that has a signed-in Steam: the default one, else the first with an account.
    var steamBottle: Bottle? {
        if let d = defaultBottle, SteamProfile.hasAccount(driveC: d.driveC) { return d }
        return bottles.first { SteamProfile.hasAccount(driveC: $0.driveC) }
    }

    func loadSteamProfile() {
        steamProfile = steamBottle.flatMap { SteamProfile.load(driveC: $0.driveC) }
    }

    /// Minutes Steam itself counts for the game (what its library shows), nil when it has none.
    func steamMinutes(for item: LibraryItem) -> Int? {
        guard let appid = item.steamAppID, let m = steamProfile?.plays[appid]?.minutes, m > 0 else { return nil }
        return m
    }

    /// The game's name for a Steam id the library may not list (a game played once, since removed).
    func steamGameName(_ appid: Int) -> String {
        libraryItems.first { $0.steamAppID == appid }.map { displayTitle($0) } ?? storeInfo[appid]?.name ?? "Steam \(appid)"
    }

    // MARK: friends

    /// Reads the public pages of the account and its friends. Throttled: not more than once a minute.
    func refreshPresence(force: Bool = false) {
        guard let profile = steamProfile, !presenceLoading else { return }
        if !force, let last = presenceUpdated, Date().timeIntervalSince(last) < 60 { return }
        presenceLoading = true
        let friends = profile.friends
        let me = SteamFriend(accountID: profile.accountID, name: profile.personaName, avatarHash: nil)
        Task {
            let result = await SteamPresence.fetch([me] + friends)
            let before = friendPresence
            friendPresence = result.filter { $0.key != profile.accountID }
            // Only a real change between two reads counts: the first read has nothing to compare with.
            if !before.isEmpty {
                let came = FriendWatchStore.cameOnline(watched: watchedFriends, before: before, after: friendPresence)
                Notifier.friendsOnline(came.compactMap { id in profile.friends.first { $0.accountID == id }?.name })
            }
            selfPresence = result[profile.accountID]
            presenceUpdated = Date()
            presenceLoading = false
        }
    }

    /// The friends known to be playing this game right now.
    func friendsPlaying(appid: Int) -> [SteamFriend] {
        (steamProfile?.friends ?? []).filter { friendPresence[$0.accountID]?.appid == appid && friendPresence[$0.accountID]?.state == .inGame }
    }

    // MARK: store details

    func loadStoreInfo(_ appid: Int) {
        guard storeInfo[appid] == nil else { return }
        if let hit = SteamStoreInfo.cached(appid, paths: paths) { storeInfo[appid] = hit; return }
        Task { if let info = await SteamStoreInfo.load(appid, paths: paths) { storeInfo[appid] = info } }
    }

    // MARK: status

    typealias SteamStatus = SteamStatusChoice

    /// Tells the running Steam client to change the account's state. Steam answers its own `steam://` links; the call has
    /// to use the environment Steam runs in, so it goes through the Steam program's own settings.
    func setSteamStatus(_ status: SteamStatus) {
        guard let bottle = steamBottle, steamClients.contains(bottle.name) else {
            steamStatusNote = L("Steam is not running. Open Steam first, then change the status.")
            return
        }
        let steam = bottle.driveC.appending(path: "Program Files (x86)/Steam/steam.exe")
        var pin = bottle.settings.pins.first { $0.path.lowercased().hasSuffix("steam/steam.exe") }
            ?? Pin(name: "Steam", path: Pin.storagePath(for: steam, driveC: bottle.driveC), environment: ["WINEMSYNC": "0", "WINEESYNC": "0"])
        pin.arguments = ["steam://friends/status/\(status.rawValue)"]
        guard let engine = engine(for: bottle) else { return }
        steamStatusNote = String(format: L("Status sent: %@"), Self.statusTitle(status))
        lastSentStatus = status
        let runner = WineRunner(paths: paths, engine: engine, bottle: bottle)
        Task.detached {
            _ = try? await runner.start(pin: pin)
            await MainActor.run { self.presenceUpdated = nil; self.refreshPresence(force: true) }
        }
    }

    /// Hands a `steam://` link to the Steam client that runs in the bottle (its friends window, a chat with someone). Steam must be running.
    func sendToSteam(_ link: String) {
        guard let bottle = steamBottle else { steamStatusNote = L("No signed-in Steam account found."); return }
        let steam = bottle.driveC.appending(path: "Program Files (x86)/Steam/steam.exe")
        var pin = bottle.settings.pins.first { $0.path.lowercased().hasSuffix("steam/steam.exe") }
            ?? Pin(name: "Steam", path: Pin.storagePath(for: steam, driveC: bottle.driveC), environment: ["WINEMSYNC": "0", "WINEESYNC": "0"])
        pin.arguments = [link]
        guard let engine = engine(for: bottle) else { steamStatusNote = L("The Windows engine is not ready."); return }
        // Running: Steam takes the link. Not running: it is started with the link, which takes a while.
        steamStatusNote = steamClients.contains(bottle.name) ? L("Sent to Steam.") : L("Steam is starting; its window opens when it is ready.")
        let runner = WineRunner(paths: paths, engine: engine, bottle: bottle)
        Task.detached { _ = try? await runner.start(pin: pin) }
    }

    /// The account's own state: the last choice made here, else what the client's file says.
    var chosenStatus: SteamStatusChoice? {
        if let sent = lastSentStatus { return sent }
        switch steamProfile?.persona {
        case .online?, .lookingToPlay?, .lookingToTrade?: return .online
        case .away?, .snooze?: return .away
        case .busy?: return .busy
        case .invisible?: return .invisible
        case .offline?: return .offline
        case nil: return nil
        }
    }

    static func statusTitle(_ s: SteamStatus) -> String {
        switch s {
        case .online: return L("Online"); case .away: return L("Away"); case .busy: return L("Busy")
        case .invisible: return L("Invisible"); case .offline: return L("Offline")
        }
    }
}

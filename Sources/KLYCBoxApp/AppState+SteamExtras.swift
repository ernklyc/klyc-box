import Foundation
import KLYCKit

/// More from Steam, all of it public or already on this Mac: a game's news, its achievements, the wishlist with prices,
/// friends to be told about, and a summary of the time played.
extension AppState {
    // MARK: news and achievements

    func loadNews(_ appid: Int) {
        guard steamNews[appid] == nil else { return }
        Task { steamNews[appid] = await SteamNews.fetch(appid) }
    }

    func loadAchievements(_ appid: Int) {
        if steamProfile == nil { loadSteamProfile() }
        guard achievementsByApp[appid] == nil, let bottle = steamBottle, let profile = steamProfile else { return }
        let root = bottle.driveC.appending(path: "Program Files (x86)/Steam")
        let account = profile.accountID
        Task.detached {
            let found = SteamAchievements.load(steamRoot: root, account: account, appid: appid)
            await MainActor.run { if let found { self.achievementsByApp[appid] = found } }
        }
    }

    // MARK: wishlist

    /// The wishlist of a public profile and what each game costs now. Not more than once every ten minutes.
    func loadWishlist(force: Bool = false) {
        guard let profile = steamProfile else { return }
        if !force, let t = wishlistUpdated, Date().timeIntervalSince(t) < 600 { return }
        wishlistUpdated = Date()
        Task {
            let ids = await SteamWishlist.fetch(steamID64: profile.steamID64)
            wishlist = ids
            wishPrices = await SteamWishlist.prices(ids)
            for appid in wishPrices.values.filter(\.onSale).prefix(12).map(\.appid) { loadStoreInfo(appid) }
        }
    }

    /// The wishlist ids, fetched now (the wishlist page waits for exactly this instead of polling).
    func fetchWishlistIDs() async -> [Int] {
        if steamProfile == nil { loadSteamProfile() }
        guard let profile = steamProfile else { return [] }
        let ids = await SteamWishlist.fetch(steamID64: profile.steamID64)
        wishlist = ids
        return ids
    }

    var wishlistOnSale: [SteamPrice] { wishPrices.values.filter(\.onSale).sorted { $0.discount > $1.discount } }

    // MARK: friends to be told about

    func setWatched(_ id: Int, _ on: Bool) {
        FriendWatchStore().set(id, watched: on)
        watchedFriends = FriendWatchStore().all()
        if on { startFriendWatch() }
        notify(on ? L("You will be told when they come online.") : L("No longer watching them."), style: on ? .success : .info)
    }

    /// While the app runs and someone is watched, the friends' state is read every five minutes, not only when the profile is open.
    func startFriendWatch() {
        guard !friendWatchRunning else { return }
        friendWatchRunning = true
        Task {
            while !watchedFriends.isEmpty {
                if steamProfile == nil { loadSteamProfile() }
                refreshPresence(force: true)
                try? await Task.sleep(for: .seconds(300))
            }
            friendWatchRunning = false
        }
    }

    // MARK: summary

    /// What the record on this Mac can honestly say. Steam keeps one total per game and the last two weeks, not a history by year.
    func sessionSummary(days: Int) -> SessionStats.Summary {
        SessionStats.summary(SessionStats.read(from: paths.logs), since: Date().addingTimeInterval(-Double(days) * 86400))
    }

    // MARK: menu bar

    /// The game played last that is still installed: what the menu bar offers to start.
    var lastPlayedItem: LibraryItem? {
        libraryItems.filter { $0.installed }
            .compactMap { item in libraryPlays[item.id].map { (item, $0.lastPlayedAt) } }
            .max { $0.1 < $1.1 }?.0
    }
}

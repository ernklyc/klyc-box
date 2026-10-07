import SwiftUI
import KLYCKit

/// Steam without opening Steam: who you are, how long you have played, your friends and what they are doing,
/// and the switch for your own status.
struct ProfileView: View {
    @Environment(AppState.self) private var state
    @State private var showWishlist = false

    var body: some View {
        ZStack {
            BottleBackdrop()
            if let profile = state.steamProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(profile)
                        stats(profile)
                        topGames(profile)
                        recap(profile)
                        wishlistCard
                        FriendsPanel(profile: profile, onChat: nil)
                    }
                    .hubPageFrame()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(L("No signed-in Steam account found.")).font(.title3)
                    Text(L("Install Steam from the + menu and sign in once. Your hours and friends then show up here.")).foregroundStyle(.secondary)
                }
            }
        }
        .hbPageRoot()
        .sheet(isPresented: $showWishlist) { WishlistSheet().hbSheet() }
        .navigationDestination(for: StoreRoute.self) { StoreGameView(route: $0) }
        .navigationDestination(for: LibraryItem.self) { GameDetailView(passedItem: $0) }
        .task {
            state.loadSteamProfile()
            state.loadWishlist()
            // The friends' state is read from public pages: now, and every few minutes while this screen is open.
            while !Task.isCancelled {
                state.refreshPresence()
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    // MARK: header and status

    private func header(_ p: SteamProfile) -> some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            HStack(alignment: .center, spacing: 20) {
                avatar(p).frame(width: 88, height: 88).clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 2))
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.personaName).font(.system(size: 34, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 8) {
                        Circle().fill(statusColor).frame(width: 9, height: 9)
                        Text(selfText).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
            }
            statusRow
        }
    }

    /// Your own state, said exactly: what you chose, and what that means for your friends.
    private var selfText: String {
        if state.selfPresence?.state == .inGame { return String(format: L("Playing %@"), state.selfPresence?.gameName ?? "") }
        switch state.chosenStatus {
        case .online?: return L("Online")
        case .away?: return L("Away")
        case .busy?: return L("Busy: do not disturb")
        case .invisible?: return L("Invisible: you are online, but friends see you as offline")
        case .offline?: return L("Offline")
        case nil: return L("Status unknown")
        }
    }

    private var statusColor: Color {
        switch state.chosenStatus {
        case .online?: return Color(red: 0.40, green: 0.70, blue: 1.0)
        case .away?: return Color(red: 0.95, green: 0.75, blue: 0.35)
        case .busy?: return Color(red: 1.0, green: 0.50, blue: 0.45)
        default: return Color.white.opacity(0.3)
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(AppState.SteamStatus.allCases, id: \.self) { s in
                    Button { state.setSteamStatus(s); UISound.play(.select) } label: { Text(AppState.statusTitle(s)) }
                        .buttonStyle(HBCompactButtonStyle())
                }
                Spacer(minLength: 0)
            }
            if let note = state.steamStatusNote { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func avatar(_ p: SteamProfile) -> some View {
        if let url = p.avatar, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack { HB.amber.opacity(0.6); Text(String(p.personaName.prefix(1))).font(.system(size: 36, weight: .bold, design: .rounded)) }
        }
    }

    // MARK: numbers

    private func stats(_ p: SteamProfile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { statCards(p) }.fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) { statCards(p) }
        }
    }

    @ViewBuilder private func statCards(_ p: SteamProfile) -> some View {
        InfoCard(symbol: "clock", title: L("Time played"), value: hours(p.totalMinutes), detail: L("From Steam's own record on this Mac"))
        InfoCard(symbol: "gamecontroller", title: L("Games played"), value: String(p.gamesPlayed), detail: String(format: L("of %d in the library"), max(state.libraryItems.filter { $0.source == .steam }.count, p.gamesPlayed)))
        InfoCard(symbol: "calendar", title: L("Last two weeks"), value: hours(p.lastTwoWeeksMinutes))
        InfoCard(symbol: "person.2", title: L("Friends"), value: String(p.friends.count),
                 detail: String(format: L("%d online now"), state.friendPresence.values.filter { $0.state == .online || $0.state == .inGame }.count))
    }

    private func hours(_ minutes: Int) -> String {
        minutes < 60 ? String(format: L("%d min"), minutes) : String(format: L("%d h"), minutes / 60)
    }

    private func topGames(_ p: SteamProfile) -> some View {
        let top = p.top(8), most = max(top.first?.play.minutes ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("Most played"))
            ForEach(Array(top.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(state.steamGameName(row.appid)).onAppear { state.loadStoreInfo(row.appid) }.font(.system(size: 14, weight: .medium)).lineLimit(1).frame(width: 220, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(HB.amber.opacity(0.85)).frame(width: max(6, geo.size.width * CGFloat(row.play.minutes) / CGFloat(most)))
                        }
                    }.frame(height: 8)
                    Text(hours(row.play.minutes)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
    }

    // MARK: summary

    /// Steam keeps one total per game and the last two weeks, not a history by year: so this is a summary, not a "year in review".
    private func recap(_ p: SteamProfile) -> some View {
        let recent = p.plays.filter { $0.value.lastTwoWeeksMinutes > 0 }.sorted { $0.value.lastTwoWeeksMinutes > $1.value.lastTwoWeeksMinutes }.prefix(3)
        let month = state.sessionSummary(days: 30), year = state.sessionSummary(days: 365)
        return VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("Summary"))
            if !recent.isEmpty {
                Text(L("Last two weeks, in Steam")).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recent), id: \.key) { appid, play in
                    HStack { Text(state.steamGameName(appid)).lineLimit(1); Spacer(minLength: 8); Text(hours(play.lastTwoWeeksMinutes)).foregroundStyle(.secondary).monospacedDigit() }
                        .font(.system(size: 14))
                }
            }
            Divider().opacity(0.3)
            Text(L("Sessions KLYC-Box watched")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                recapNumber(L("Last 30 days"), month)
                recapNumber(L("Last 12 months"), year)
            }
            if let top = year.top.first { Text(String(format: L("Most in KLYC-Box: %@"), top.title)).font(.callout) }
            Text(L("Steam's record on this Mac holds a total per game and the last two weeks, not a history by year. The sessions above are only the ones KLYC-Box started and watched."))
                .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
    }

    private func recapNumber(_ title: String, _ s: SessionStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(hours(s.seconds / 60)).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(String(format: L("%d sessions"), s.sessions)).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: wishlist

    @ViewBuilder private var wishlistCard: some View {
        let sales = state.wishlistOnSale
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HB.eyebrow(L("Wishlist"))
                Spacer(minLength: 8)
                if !state.wishlist.isEmpty { Button { showWishlist = true } label: { Text(String(format: L("See all %d"), state.wishlist.count)) }.buttonStyle(HBTextButtonStyle()).font(.callout) }
                Button { if let url = URL(string: "https://store.steampowered.com/cart/") { NSWorkspace.shared.open(url) } } label: { Label(L("Open cart"), systemImage: "cart") }
                    .buttonStyle(HBCompactButtonStyle()).help(L("The cart belongs to your Steam account and cannot be read from here; it opens in your browser."))
            }
            if state.wishlist.isEmpty {
                Text(L("Nothing found: the wishlist is read from your public Steam profile, and an empty or private one shows nothing."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if sales.isEmpty {
                Text(String(format: L("%d games on the wishlist, none on sale right now."), state.wishlist.count)).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(String(format: L("%d of %d wishlist games are on sale"), sales.count, state.wishlist.count)).font(.callout)
                ForEach(sales.prefix(10), id: \.appid) { price in
                    HStack(spacing: 10) {
                        Text("-\(price.discount)%").font(.system(size: 12, weight: .bold)).padding(.horizontal, 7).frame(height: 22)
                            .background(Capsule().fill(HB.good.opacity(0.35)))
                        Text(state.steamGameName(price.appid)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(price.formatted ?? "").foregroundStyle(.secondary)
                    }.font(.system(size: 14))
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
    }
}

/// One friend: state dot, name, the bell right beside the name (so it is clear whose it is), and what they are doing on the right.
struct FriendRow: View {
    let friend: SteamFriend
    let presence: FriendPresence?
    let detail: String
    let color: Color
    let watched: Bool
    let toggleWatch: () -> Void
    /// Opens a chat with this friend (the Friends tab offers it; the profile's list does not).
    var chat: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(friend.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Button { UISound.play(.select); toggleWatch() } label: {
                Image(systemName: watched ? "bell.fill" : "bell").font(.system(size: 12))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(watched ? HB.amber.opacity(0.25) : Color.white.opacity(hovering ? 0.1 : 0)))
            }
            .buttonStyle(.plain).foregroundStyle(watched ? HB.amber : Color.secondary.opacity(hovering ? 1 : 0.6))
            .help(watched ? L("Stop telling me when this friend comes online") : L("Tell me when this friend comes online"))
            if let chat {
                Button { UISound.play(.select); chat() } label: {
                    Image(systemName: "bubble.left.fill").font(.system(size: 12)).frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(hovering ? 0.1 : 0)))
                }
                .buttonStyle(.plain).foregroundStyle(Color.secondary.opacity(hovering ? 1 : 0.6)).help(L("Chat with this friend"))
            }
            Spacer(minLength: 12)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

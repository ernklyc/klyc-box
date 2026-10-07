import SwiftUI
import KLYCKit

/// The friend list: who is playing what, who is online, and a bell for the ones you want to hear about.
/// Used by the profile and by the Friends tab (which adds a chat button per friend).
struct FriendsPanel: View {
    @Environment(AppState.self) private var state
    let profile: SteamProfile
    let onChat: ((SteamFriend) -> Void)?

    var body: some View {
        let sorted = profile.friends.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HB.eyebrow(L("Friends"))
                if state.presenceLoading { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                if let t = state.presenceUpdated { Text(String(format: L("Updated %@"), t.formatted(.relative(presentation: .named)))).font(.caption).foregroundStyle(.secondary) }
                Button { state.refreshPresence(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(HBCompactButtonStyle()).help(L("Refresh now"))
            }
            if sorted.isEmpty {
                Text(L("No friends in this Steam account yet.")).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, friend in
                    FriendRow(friend: friend, presence: state.friendPresence[friend.accountID], detail: detail(state.friendPresence[friend.accountID]),
                              color: color(state.friendPresence[friend.accountID]?.state ?? .unknown), watched: state.watchedFriends.contains(friend.accountID),
                              toggleWatch: { state.setWatched(friend.accountID, !state.watchedFriends.contains(friend.accountID)) },
                              chat: onChat.map { open in { open(friend) } })
                    if index < sorted.count - 1 { Divider().opacity(0.18) }
                }
            }
            Text(L("Online state comes from friends' public Steam pages; a private profile shows as unknown. The bell tells you when a friend comes online, checked every five minutes while KLYC-Box runs."))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
        .task { state.refreshPresence() }
    }

    private func rank(_ f: SteamFriend) -> Int {
        switch state.friendPresence[f.accountID]?.state { case .inGame?: return 0; case .online?: return 1; case .offline?: return 2; default: return 3 }
    }

    private func detail(_ p: FriendPresence?) -> String {
        switch p?.state {
        case .inGame?: return String(format: L("Playing %@"), p?.gameName ?? "")
        case .online?: return L("Online")
        case .offline?: return p?.message ?? L("Offline")
        default: return state.presenceUpdated == nil ? "" : L("Unknown")
        }
    }

    private func color(_ s: FriendPresence.State) -> Color {
        switch s {
        case .inGame: return Color(red: 0.55, green: 0.85, blue: 0.35)
        case .online: return Color(red: 0.40, green: 0.70, blue: 1.0)
        case .offline: return Color.white.opacity(0.28)
        case .unknown: return Color.white.opacity(0.12)
        }
    }
}

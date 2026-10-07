import SwiftUI
import KLYCKit

/// Friends in the Steam tab: who is online and what they play, a chat window for any of them, and the way to Steam's own friends window.
/// Written chat and game invites live in Steam's official web chat (opened here, signed in once); a chat with one friend can also be
/// opened in the Steam client that runs in the bottle.
struct FriendsView: View {
    @Environment(AppState.self) private var state
    @State private var showChat = false

    private let chatURL = URL(string: "https://steamcommunity.com/chat/")!

    var body: some View {
        ZStack {
            BottleBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HubHeaderSlot()
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(L("Friends")).font(.system(size: 34, weight: .heavy, design: .rounded))
                        if let p = state.steamProfile { Text(String(format: L("%d friends"), p.friends.count)).font(.callout).foregroundStyle(.secondary) }
                        Spacer(minLength: 8)
                        Button { showChat = true } label: { Label(L("Open Steam chat"), systemImage: "bubble.left.and.bubble.right.fill") }.buttonStyle(HBPrimaryButtonStyle())
                        Button { state.sendToSteam("steam://open/friends") } label: { Label(L("Friends window in Steam"), systemImage: "person.2") }.buttonStyle(HBSecondaryButtonStyle())
                            .help(L("Opens the friends list of the Steam client that runs inside KLYC-Box. Steam must be running."))
                    }
                    if let note = state.steamStatusNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                    if let profile = state.steamProfile {
                        FriendsPanel(profile: profile) { _ in showChat = true }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 40)).foregroundStyle(.secondary)
                            Text(L("No signed-in Steam account found.")).font(.title3)
                            Text(L("Install Steam from the + menu and sign in once. Your hours and friends then show up here.")).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HB.eyebrow(L("Chat, invites and voice"))
                        Text(L("Steam's official web chat opens here: written chat, game invites and voice. Sign in once in that window; what you type goes to Steam only. Voice chat needs the microphone and may not work in every case; the friends window of the Steam client is the fallback."))
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
                }
                .hubPageFrame()
            }
        }
        .hbPageRoot()
        .sheet(isPresented: $showChat) { WebSheet(title: L("Steam chat"), url: chatURL, chromeUserAgent: true).hbSheet() }
        .task { state.loadSteamProfile(); state.refreshPresence() }
    }
}

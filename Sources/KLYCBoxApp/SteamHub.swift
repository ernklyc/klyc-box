import SwiftUI
import KLYCKit

/// The parts of a store's page: the games you have, the shop, your friends, the store's own website.
enum HubTab: Hashable { case library, store, friends, web }

/// The tabs of a hub, at the top of every page of it (the root pages and the ones opened from them), moving with the page when it scrolls.
/// Liquid glass like the top bar; the chosen tab is a red pill, the others are plain text, the same switch as everywhere else.
/// The hub hands it to its pages through the environment; a page shows it with `HubHeaderSlot`.
struct HubHeader<Trailing: View>: View {
    let tabs: [(HubTab, String)]
    @Binding var selection: HubTab
    var onSelect: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            // The same switch as the library's filters (Installed / All / Ready / Favourites): one look for every set of tabs.
            HBSegment(selection: Binding(get: { selection }, set: { UISound.play(.select); onSelect(); selection = $0 }),
                      options: tabs.map { ($0.0, $0.1) })
            Spacer(minLength: 12)
            trailing
        }
    }
}

private struct HubHeaderKey: EnvironmentKey { static let defaultValue: AnyView? = nil }
extension EnvironmentValues { var hubHeader: AnyView? { get { self[HubHeaderKey.self] } set { self[HubHeaderKey.self] = newValue } } }

private struct HubResetKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues { var hubReset: () -> Void { get { self[HubResetKey.self] } set { self[HubResetKey.self] = newValue } } }

extension View {
    /// One frame for every page of a hub, so the tabs at the top sit at exactly the same place whichever page is open:
    /// the same side margins (the page margin, also used by the top bar), the same top margin, and the full width: left and right edges
    /// line up with the top bar's buttons at any window size.
    func hubPageFrame() -> some View {
        self.padding(.horizontal, HB.Metric.margin).padding(.top, 20).padding(.bottom, 50)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a page shows its hub's tabs: put it first in the page's content.
struct HubHeaderSlot: View {
    @Environment(\.hubHeader) private var header
    var body: some View { if let header { header } }
}

/// Back, forward, reload, home and "open in the browser" for a store's website.
struct WebNavButtons: View {
    let web: WebStoreController
    var body: some View {
        HStack(spacing: 8) {
            button("chevron.left", L("Back"), web.canGoBack) { web.goBack() }
            button("chevron.right", L("Forward"), web.canGoForward) { web.goForward() }
            button("arrow.clockwise", L("Refresh now"), true) { web.reload() }
            button("house", L("Store home"), true) { web.goHome() }
            button("safari", L("Open in the browser"), true) { NSWorkspace.shared.open(web.currentURL ?? web.home) }
        }
    }

    private func button(_ symbol: String, _ help: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(HBIconButtonStyle()).disabled(!enabled).help(help)
    }
}

/// Steam in one place. Always opens on the library, with every game listed (nothing filtered until you choose to).
/// KLYC_START_SECTION=store, friends or steamweb opens that tab first (handy for screenshots).
struct SteamHub: View {
    @Binding var path: NavigationPath
    @State private var tab: HubTab = {
        switch ProcessInfo.processInfo.environment["KLYC_START_SECTION"] {
        case "store"?: return .store
        case "friends"?: return .friends
        case "steamweb"?: return .web
        default: return .library
        }
    }()
    @State private var web = WebStoreController(home: URL(string: "https://store.steampowered.com/?l=\(StoreLanguage.steam)")!)
    /// Kept here, not in the store page: leaving the Store tab and coming back finds the front page as it was.
    @State private var storeModel = StoreFrontModel()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .library: LibraryView(initialSource: .steam, show: .all)
                case .store: StoreView(path: $path, model: storeModel)
                case .friends: FriendsView()
                case .web: WebStorePage(web: web, free: false)
                }
            }
            // A new page for each tab, so it opens the way every page opens (see hbPage).
            .id(tab)
        }
        .environment(\.hubHeader, AnyView(
            HubHeader(tabs: [(.library, L("Library")), (.store, L("Store")), (.friends, L("Friends")), (.web, L("Steam site"))],
                      selection: $tab, onSelect: { path = NavigationPath() }) {
                if tab == .web { WebNavButtons(web: web) }
            }))
        .environment(\.hubReset, { path = NavigationPath() })
    }
}

/// Epic the same way. Its store side is Epic's own site in a browser view, with this week's free games above it.
struct EpicHub: View {
    @Binding var path: NavigationPath
    @State private var tab: HubTab = ProcessInfo.processInfo.environment["KLYC_START_SECTION"] == "epicstore" ? .store : .library
    @State private var web = WebStoreController(home: URL(string: "https://store.epicgames.com/tr/")!)

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .library, .friends: LibraryView(initialSource: .epic, show: .all)
                case .store, .web: WebStorePage(web: web, free: true)
                }
            }
            .id(tab)
        }
        .environment(\.hubHeader, AnyView(
            HubHeader(tabs: [(.library, L("Library")), (.store, L("Store"))], selection: $tab, onSelect: { path = NavigationPath() }) {
                if tab == .store { WebNavButtons(web: web) }
            }))
        .environment(\.hubReset, { path = NavigationPath() })
    }
}

/// A store's website under the hub's tabs, with (for Epic) this week's free games above it.
struct WebStorePage: View {
    let web: WebStoreController
    /// The free-games strip is Epic's.
    let free: Bool
    @State private var showFree = true

    var body: some View {
        ZStack {
            BottleBackdrop()
            VStack(alignment: .leading, spacing: 12) {
                // Same place as on every other page of the hub (see hubPageFrame): the page itself keeps the full width below.
                HubHeaderSlot().frame(maxWidth: .infinity, alignment: .leading)
                if free { EpicFreeStrip(show: $showFree) }
                ZStack {
                    WebStoreView(controller: web)
                    if web.loading { VStack { ProgressView().controlSize(.small).padding(10).hbGlass(Capsule()); Spacer() }.padding(.top, 10).allowsHitTesting(false) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
                Text(String(format: L("This is the store's own website (%@). What you type here, your sign-in included, goes to that store only."), web.home.host ?? ""))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, HB.Metric.margin).padding(.top, 20).padding(.bottom, 20)
        }
        .hbPageRoot()
    }
}

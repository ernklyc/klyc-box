import SwiftUI
import KLYCKit

/// The store's category names, read once: a game page names its categories from them.
@MainActor
enum StoreCategories {
    static var all: [StoreCategory] = []
    private static var loading = false
    static func load() async -> [StoreCategory] {
        if !all.isEmpty { return all }
        guard !loading else { return all }
        loading = true; defer { loading = false }
        all = await SteamStore.categories()
        return all
    }
}

/// A web page in a window over the app, with back, forward and reload: the Workshop, a community hub, a mod site.
struct WebSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State private var web: WebStoreController

    init(title: String, url: URL, chromeUserAgent: Bool = false) { self.title = title; _web = State(initialValue: WebStoreController(home: url, chromeUserAgent: chromeUserAgent)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1)
                Spacer(minLength: 8)
                nav("chevron.left", L("Back"), web.canGoBack) { web.goBack() }
                nav("chevron.right", L("Forward"), web.canGoForward) { web.goForward() }
                nav("arrow.clockwise", L("Refresh now"), true) { web.reload() }
                nav("safari", L("Open in the browser"), true) { NSWorkspace.shared.open(web.currentURL ?? web.home) }
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(HBIconButtonStyle()).keyboardShortcut(.cancelAction).help(L("Close"))
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            ZStack {
                WebStoreView(controller: web)
                if web.loading { VStack { ProgressView().controlSize(.small).padding(10).hbGlass(Capsule()); Spacer() }.padding(.top, 10).allowsHitTesting(false) }
            }
            Text(String(format: L("This is the store's own website (%@). What you type here, your sign-in included, goes to that store only."), web.home.host ?? ""))
                .font(.caption2).foregroundStyle(.tertiary).padding(.vertical, 6)
        }
        .frame(minWidth: 880, idealWidth: 1040, minHeight: 600, idealHeight: 740)
    }

    private func nav(_ symbol: String, _ help: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(HBIconButtonStyle()).disabled(!enabled).help(help)
    }
}

/// Everything around a game that is not the game: its Workshop, guides and discussions on Steam, mod sites, and whether KLYC-Box
/// knows where this game's mods go. Each opens in a window here; nothing leaves the app unless asked.
struct WorkshopModsCard: View {
    @Environment(AppState.self) private var state
    let appid: Int
    let name: String
    let hasWorkshop: Bool
    @State private var sheet: SheetPage?

    struct SheetPage: Identifiable { let id = UUID(); let title: String; let url: URL }

    private var encoded: String { name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name }
    private var modsKnown: Bool { AppState.modCatalog.entry(for: "steam:\(appid)") != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("Workshop and mods"))
            FlowLayout {
                if hasWorkshop { page(L("Steam Workshop"), "wrench.and.screwdriver", "https://steamcommunity.com/app/\(appid)/workshop/") }
                page(L("Community hub"), "person.3", "https://steamcommunity.com/app/\(appid)")
                page(L("Guides"), "book", "https://steamcommunity.com/app/\(appid)/guides/")
                page(L("Discussions"), "bubble.left.and.bubble.right", "https://steamcommunity.com/app/\(appid)/discussions/")
                page("Nexus Mods", "puzzlepiece.extension", "https://www.nexusmods.com/search?keyword=\(encoded)")
                page("ModDB", "square.stack.3d.up", "https://www.moddb.com/search?q=\(encoded)")
            }
            Label(modsKnown ? L("KLYC-Box knows where this game's mods go: after installing it, add a mod from the game's page.")
                            : L("KLYC-Box does not know this game's mod folders yet; mods can still be copied in by hand."),
                  systemImage: modsKnown ? "checkmark.circle" : "info.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !hasWorkshop {
                Text(L("This game has no Steam Workshop; community mods live on the sites above."))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .sheet(item: $sheet) { WebSheet(title: $0.title, url: $0.url).hbSheet() }
    }

    private func page(_ title: String, _ symbol: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { UISound.play(.select); sheet = SheetPage(title: "\(title) · \(name)", url: u) } } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: HB.Metric.chip)
                .background(Capsule().fill(Color.white.opacity(0.09)))
        }.buttonStyle(.plain)
    }
}

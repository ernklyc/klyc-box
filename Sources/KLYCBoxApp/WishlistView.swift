import SwiftUI
import KLYCKit

/// The whole wishlist, read from the public profile: sorted, filtered, as a grid or as lines. The cart lives in the Steam account
/// and cannot be read from here, so the page says so and opens it in the browser.
struct WishlistView: View {
    @Environment(AppState.self) private var state
    @State private var model = WishlistModel()
    @AppStorage("storeLayout") private var layoutRaw = StoreLayout.grid.rawValue

    private var layout: Binding<StoreLayout> { Binding(get: { StoreLayout(rawValue: layoutRaw) ?? .grid }, set: { layoutRaw = $0.rawValue }) }

    var body: some View {
        @Bindable var model = model
        ZStack {
            BottleBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(L("Wishlist")).font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text(String(format: L("%d games"), model.cards.count)).font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if let id = state.steamProfile?.steamID64 {
                            Button { open("https://store.steampowered.com/wishlist/profiles/\(id)/") } label: { Label(L("Open in Steam"), systemImage: "safari") }.buttonStyle(HBCompactButtonStyle())
                        }
                        Button { open("https://store.steampowered.com/cart/") } label: { Label(L("Open cart"), systemImage: "cart") }.buttonStyle(HBCompactButtonStyle())
                            .help(L("The cart belongs to your Steam account and cannot be read from here; it opens in your browser."))
                    }
                    HStack(spacing: 10) {
                        chip(L("On sale"), "tag", on: model.onSaleOnly) { model.onSaleOnly.toggle() }
                        chip(L("Has a Mac build"), "applelogo", on: model.macOnly) { model.macOnly.toggle() }
                        Menu {
                            Picker(L("Sort"), selection: $model.sort) {
                                Text(L("Biggest discount")).tag(WishlistSort.discount); Text(L("Price: low to high")).tag(WishlistSort.price); Text(L("Name (A to Z)")).tag(WishlistSort.name)
                            }.pickerStyle(.inline)
                        } label: {
                            Label(L("Sort"), systemImage: "arrow.up.arrow.down").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 14).frame(height: HB.Metric.chip).hbGlass(Capsule(), interactive: true)
                        }.menuStyle(.button).buttonStyle(.plain).fixedSize()
                        Spacer(minLength: 8)
                        StoreLayoutToggle(layout: layout)
                    }
                    if model.loading {
                        if layout.wrappedValue == .grid { SkeletonGrid(count: 4) } else { SkeletonRows(count: 4) }
                    } else if model.cards.isEmpty {
                        Text(L("Nothing found: the wishlist is read from your public Steam profile, and an empty or private one shows nothing.")).foregroundStyle(.secondary)
                    } else if model.shown.isEmpty {
                        Text(L("Nothing matches these filters.")).foregroundStyle(.secondary)
                    } else {
                        StoreCards(cards: model.shown, layout: layout.wrappedValue)
                    }
                    Text(L("Adding and removing happen in Steam. The cart needs your Steam sign-in, so it opens in the browser."))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, HB.Metric.margin).padding(.top, 20).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .hbPageRoot()
        .task {
            // The ids arrive first; the details (name, price, platforms) follow in one batch.
            let ids = await state.fetchWishlistIDs()
            await model.load(ids: ids)
        }
    }

    private func open(_ s: String) { if let url = URL(string: s) { NSWorkspace.shared.open(url) } }

    private func chip(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { UISound.play(.select); action() } label: {
            Label(title, systemImage: symbol).font(.system(size: 12.5, weight: .semibold)).padding(.horizontal, 12).frame(height: HB.Metric.chip)
                .background(Capsule().fill(on ? HB.amber.opacity(0.7) : Color.white.opacity(0.09)))
        }.buttonStyle(.plain)
    }
}

/// The wishlist as a window over the profile: opening a game goes forward inside it, and the close button comes back to the profile.
struct WishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            WishlistView()
                .safeAreaPadding(.top, 36)   // room for the close button
                .navigationDestination(for: StoreRoute.self) { StoreGameView(route: $0).safeAreaPadding(.top, 36) }
                .navigationDestination(for: LibraryItem.self) { GameDetailView(passedItem: $0) }
                .navigationDestination(for: StoreResultsRoute.self) { StoreResultsView(route: $0, categories: StoreCategories.all) }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(HBIconButtonStyle()).keyboardShortcut(.cancelAction).padding(14)
                .help(L("Close"))
        }
        .overlay(alignment: .topLeading) {
            if !path.isEmpty {
                Button { if !path.isEmpty { path.removeLast() } } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(HBIconButtonStyle()).padding(14).help(L("Back"))
            }
        }
        .frame(minWidth: 860, idealWidth: 1000, minHeight: 600, idealHeight: 720)
    }
}

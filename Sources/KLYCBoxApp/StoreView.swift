import SwiftUI
import KLYCKit

/// A game in the store, as a navigation value.
struct StoreRoute: Hashable { let appid: Int; let name: String }
/// A page of results for a set of filters: opening one is a step forward, so Back always returns to where you were.
struct StoreResultsRoute: Hashable { var filters: StoreFilters; var title: String? = nil }
struct WishlistRoute: Hashable {}

/// Chips that wrap onto the next line instead of running off the window.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// How a list of games is shown, remembered between visits.
enum StoreLayout: String { case grid, list }

/// The store's front page: a way in (search, filters, quick lists), a few featured games and short shelves.
/// Everything else is one step away, on a results page with its own Back.
struct StoreView: View {
    @Environment(AppState.self) private var state
    @Binding var path: NavigationPath
    let model: StoreFrontModel
    @State private var suggestions: [StoreCard] = []
    @State private var suggestTask: Task<Void, Never>?
    @State private var term = ""
    @State private var showFilters = false
    @State private var draft = StoreFilters()

    var body: some View {
        ZStack {
            BottleBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HubHeaderSlot()
                    header
                    quickChips
                    front
                    Text(L("Prices are shown in the currency the Turkish store answers with. Buying happens in your browser."))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .hubPageFrame()
            }
        }
        .hbPageRoot()
        .onChange(of: term) { _, new in updateSuggestions(for: new) }
        .navigationDestination(for: StoreRoute.self) { StoreGameView(route: $0) }
        .navigationDestination(for: LibraryItem.self) { GameDetailView(passedItem: $0) }
        .navigationDestination(for: WishlistRoute.self) { _ in WishlistView() }
        .navigationDestination(for: StoreResultsRoute.self) { StoreResultsView(route: $0, categories: model.categories) }
        .sheet(isPresented: $showFilters) {
            StoreFiltersSheet(filters: $draft, categories: model.categories) { path.append(StoreResultsRoute(filters: draft)) }.hbSheet()
        }
        .task {
            state.loadSteamProfile()
            await model.load(lists: macShelves.map { ($0.key, $0.filters) })
            // KLYC_START_STORE=mac|sale|free|filters|game opens that page first (handy for screenshots).
            switch ProcessInfo.processInfo.environment["KLYC_START_STORE"] {
            case "mac"?: var f = StoreFilters(); f.mac = true; path.append(StoreResultsRoute(filters: f, title: L("On Mac")))
            case "sale"?: path.append(StoreResultsRoute(filters: .sale, title: L("On sale")))
            case "filters"?: draft = StoreFilters(); showFilters = true
            case "game"?:
                let id = ProcessInfo.processInfo.environment["KLYC_START_APPID"].flatMap { Int($0) }   // another game's page, for screenshots
                path.append(StoreRoute(appid: id ?? 1145360, name: id == nil ? "Hades" : ""))
            case "compat"?: var f = StoreFilters(); f.compat = .works; path.append(StoreResultsRoute(filters: f, title: L("Works on this Mac")))
            case "wishlist"?: path.append(WishlistRoute())
            case "list"?: UserDefaults.standard.set("list", forKey: "storeLayout"); path.append(StoreResultsRoute(filters: .sale, title: L("On sale")))
            default: break
            }
        }
    }

    /// The search and the filters; the tabs above them stay put.
    @ViewBuilder private var header: some View {
        let bar = StoreSearchBar(term: $term, filterCount: 0, onSubmit: search, onFilters: { draft = StoreFilters(); showFilters = true })
            .overlay(alignment: .topLeading) { suggestionList.offset(y: 48) }
            .zIndex(10)
        bar
    }

    /// While typing: the games that match, one click from their page. Enter shows all of them as results.
    @ViewBuilder private var suggestionList: some View {
        if !suggestions.isEmpty && !term.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions) { card in
                    NavigationLink(value: StoreRoute(appid: card.appid, name: card.name)) {
                        HStack(spacing: 10) {
                            StoreThumb(url: card.image, width: 92, height: 43).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(card.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            SupportLine(appid: card.appid, native: card.mac, compact: true)
                            Spacer(minLength: 8)
                            if let f = card.finalText { Text(f).font(.callout).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).simultaneousGesture(TapGesture().onEnded { term = ""; suggestions = [] })
                }
            }
            .padding(.vertical, 6).frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.06, green: 0.07, blue: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        }
    }

    private func updateSuggestions(for text: String) {
        suggestTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { suggestions = []; return }
        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let found = await SteamStore.search(q)
            guard !Task.isCancelled else { return }
            suggestions = Array(found.prefix(6))
        }
    }

    private func search() {
        suggestions = []
        var f = StoreFilters(); f.term = term.trimmingCharacters(in: .whitespaces)
        guard !f.term.isEmpty else { return }
        path.append(StoreResultsRoute(filters: f, title: f.term)); term = ""
    }

    // MARK: quick lists

    private func with(_ change: (inout StoreFilters) -> Void) -> StoreFilters { var f = StoreFilters(); change(&f); return f }

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    /// The ways in that matter on a Mac, first; the rest after. Each one opens a results page.
    private var quickChips: some View {
        FlowLayout {
            quick(L("Works on this Mac"), "checkmark.seal", with { $0.compat = .works })
            quick(L("On Mac"), "applelogo", with { $0.mac = true; $0.list = .topSellers })
            quick(L("New and popular"), "sparkles", with { $0.list = .topSellers; $0.minYear = thisYear - 1 })
            quick(L("On sale"), "tag", .sale)
            quick(L("Free to play"), "gift", .free)
            quick(L("Turkish language"), "character.bubble", with { $0.turkish = true; $0.list = .topSellers })
            quick(L("Coming soon"), "calendar", with { $0.list = .comingSoon })
            quick(L("Best reviewed"), "hand.thumbsup", with { $0.sort = .reviews; $0.minYear = thisYear - 5 })
        }
    }

    private func quick(_ title: String, _ symbol: String, _ filters: StoreFilters) -> some View {
        Button { UISound.play(.select); path.append(StoreResultsRoute(filters: filters, title: title)) } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).lineLimit(1).padding(.horizontal, 14).frame(height: HB.Metric.chip)
                .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    // MARK: front page

    /// What the front page shows besides the featured row: current, Mac-relevant lists, each with its own "see all".
    private var macShelves: [(title: String, filters: StoreFilters, key: String)] {
        [(L("New and popular on Mac"), with { $0.mac = true; $0.list = .topSellers; $0.minYear = thisYear - 1 }, "fresh"),
         (L("On sale on Mac"), with { $0.mac = true; $0.onSale = true; $0.list = .topSellers }, "deals"),
         (L("Coming soon on Mac"), with { $0.mac = true; $0.list = .comingSoon }, "soon")]
    }

    @ViewBuilder private var front: some View {
        frontBody.animation(HB.Motion.standard, value: model.loading).animation(HB.Motion.standard, value: model.listsLoading)
    }

    @ViewBuilder private var frontBody: some View {
        if model.loading {
            // The shape of the page while it loads, not a spinner: nothing jumps when the games arrive.
            VStack(alignment: .leading, spacing: 20) { SkeletonFeatured(); SkeletonShelf(); SkeletonShelf() }.transition(.opacity)
        } else if model.shelves.isEmpty && model.lists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("The store could not be reached. Check the connection and open this tab again.")).foregroundStyle(.secondary)
                Button(L("Try again")) { Task { await model.load(lists: macShelves.map { ($0.key, $0.filters) }, force: true) } }.buttonStyle(HBSecondaryButtonStyle())
            }
        } else {
            var seen = Set<Int>()
            let featured = Array(((model.shelves.first { $0.id == "top_sellers" }?.cards ?? []).prefix(2)) + (model.shelves.first { $0.id == "specials" }?.cards ?? []))
                .filter { seen.insert($0.appid).inserted }.prefix(3).map { $0 }
            if !featured.isEmpty { FeaturedRow(cards: featured) }
            let known = worksHere
            if !known.isEmpty { shelf(L("Works on this Mac"), known, with { $0.compat = .works }) }
            ForEach(macShelves, id: \.key) { s in
                if let cards = model.lists[s.key] { if !cards.isEmpty { shelf(s.title, cards, s.filters) } }
                else if model.listsLoading { SkeletonShelf() }
            }
            let unplayed = neverPlayed
            if !unplayed.isEmpty { shelf(L("In your library, never played"), unplayed, nil) }
        }
    }

    private func shelf(_ title: String, _ cards: [StoreCard], _ more: StoreFilters?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HB.eyebrow(title)
                Spacer(minLength: 8)
                if let more { Button(L("See all")) { path.append(StoreResultsRoute(filters: more, title: title)) }.buttonStyle(HBTextButtonStyle()).font(.callout) }
            }
            StoreGrid(cards: Array(cards.prefix(4)))
        }
    }

    private static func header(_ appid: Int) -> URL? { URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appid)/header.jpg") }

    /// Games the compatibility database lists as working (the project's own verification first), that you do not own yet.
    /// Nothing here is a guess: it is the database's own status.
    private var worksHere: [StoreCard] {
        let owned = Set(state.libraryItems.compactMap(\.steamAppID))
        let rank = ["verified-local": 0, "reported-upstream": 1, "community": 2]
        return state.gameDB.byAppID.values
            .filter { e in e.steam_appid.map { !owned.contains($0) } == true && rank[e.status] != nil }
            .sorted { (rank[$0.status] ?? 9, $0.title) < (rank[$1.status] ?? 9, $1.title) }
            .prefix(4)
            .compactMap { e in e.steam_appid.map { StoreCard(appid: $0, name: e.title, image: Self.header($0)) } }
    }

    /// Steam games you own with no time played in Steam's own record.
    private var neverPlayed: [StoreCard] {
        guard let profile = state.steamProfile else { return [] }
        return state.libraryItems
            .filter { $0.source == .steam && ($0.steamAppID.map { (profile.plays[$0]?.minutes ?? 0) == 0 } ?? false) }
            .prefix(4)
            .compactMap { item in item.steamAppID.map { StoreCard(appid: $0, name: state.displayTitle(item), image: Self.header($0)) } }
    }
}

// MARK: - pieces

struct StoreSearchBar: View {
    @Binding var term: String
    var filterCount: Int
    var onSubmit: () -> Void
    var onFilters: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search the Steam store"), text: $term).textFieldStyle(.plain).onSubmit(onSubmit)
                if !term.isEmpty { Button { term = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 14).frame(height: 42).hbGlass(Capsule())
            Button(action: onFilters) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text(L("Filters"))
                    if filterCount > 0 { Text("\(filterCount)").font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(HB.amber)) }
                }
                .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 16).frame(height: 42).hbGlass(Capsule(), interactive: true)
            }
            .buttonStyle(.plain).fixedSize()
        }
    }
}

/// Three featured games: not a banner, a row, so the page below it is still in view.
struct FeaturedRow: View {
    let cards: [StoreCard]
    var body: some View {
        FillGrid(count: cards.count, minimum: 280, spacing: 16, rowSpacing: 16, maximum: 460) {
            ForEach(cards) { card in
                NavigationLink(value: StoreRoute(appid: card.appid, name: card.name)) {
                    AsyncImage(url: card.heroImage ?? card.image, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.06) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 150).clipped()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom))
                    .overlay(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: 8) {
                            Text(card.name).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
                            Spacer(minLength: 6)
                            if card.onSale { Text("-\(card.discount)%").font(.system(size: 12, weight: .bold)).padding(.horizontal, 7).frame(height: 22).background(Capsule().fill(HB.good.opacity(0.85))) }
                            if let f = card.finalText { Text(f).font(.system(size: 13, weight: .semibold)) }
                        }.padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StoreGrid: View {
    let cards: [StoreCard]
    var body: some View {
        FillGrid(count: cards.count, minimum: 220, spacing: 16, rowSpacing: 18, maximum: 360) {
            ForEach(cards) { StoreTile(card: $0) }
        }
    }
}

struct StoreTile: View {
    let card: StoreCard
    @State private var hovering = false
    var body: some View {
        NavigationLink(value: StoreRoute(appid: card.appid, name: card.name)) {
            VStack(alignment: .leading, spacing: 8) {
                // The frame comes from a clear block of the right shape; the picture is an overlay, so its own size never changes the layout.
                Color.clear.aspectRatio(460.0 / 215.0, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: card.image, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else if case .failure = phase {
                                // The first picture is missing: the smaller capsule, then a plain block.
                                AsyncImage(url: card.fallbackImage ?? URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(card.appid)/capsule_231x87.jpg"), transaction: Transaction(animation: .easeOut(duration: 0.25))) { second in
                                    if let image = second.image { image.resizable().scaledToFill() }
                                    else { Image(systemName: "gamecontroller").font(.system(size: 28)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.06)) }
                                }
                            }
                            else { Color.white.opacity(0.06) }
                        }
                    }
                    .frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if card.onSale {
                        Text("-\(card.discount)%").font(.system(size: 12, weight: .bold)).padding(.horizontal, 7).frame(height: 22)
                            .background(Capsule().fill(HB.good.opacity(0.85))).padding(8)
                    }
                }
                Text(card.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                SupportLine(appid: card.appid, native: card.mac, compact: true)
                HStack(spacing: 8) {
                    if card.onSale, let o = card.originalText { Text(o).strikethrough().font(.caption).foregroundStyle(.secondary) }
                    if let f = card.finalText { Text(f).font(.system(size: 13, weight: .medium)) }
                    Spacer(minLength: 0)
                    if let p = card.reviewPercent { Label("%\(p)", systemImage: "hand.thumbsup.fill").font(.caption).foregroundStyle(.secondary).help(card.reviewLabel ?? "") }
                    if card.mac { Image(systemName: "applelogo").font(.caption).foregroundStyle(.secondary).help(L("Has a Mac build")) }
                }
            }
        }
        .buttonStyle(.plain)
        // A small lift under the pointer: the tile that will open is the one that moves.
        .scaleEffect(hovering ? 1.02 : 1).animation(HB.Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// One game per line: more facts at a glance, for scanning long lists.
struct StoreRow: View {
    let card: StoreCard
    var body: some View {
        NavigationLink(value: StoreRoute(appid: card.appid, name: card.name)) {
            HStack(spacing: HB.Space.m) {
                AsyncImage(url: card.fallbackImage ?? card.image, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.06) }
                }
                .frame(width: 150, height: 70).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.name).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 10) {
                        if let l = card.reviewLabel, let p = card.reviewPercent { Label("\(l) · %\(p)", systemImage: "hand.thumbsup.fill").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        if card.windows { Image(systemName: "pc").font(.caption).foregroundStyle(.secondary) }
                        if card.mac { Label("Mac", systemImage: "applelogo").font(.caption).foregroundStyle(HB.amber) }
                        SupportLine(appid: card.appid, native: card.mac, compact: true)
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    if card.onSale {
                        Text("-\(card.discount)%").font(.system(size: 12, weight: .bold)).padding(.horizontal, 7).frame(height: 22).background(Capsule().fill(HB.good.opacity(0.85)))
                        if let o = card.originalText { Text(o).strikethrough().font(.caption).foregroundStyle(.secondary) }
                    }
                    if let f = card.finalText { Text(f).font(.system(size: 14, weight: .semibold)) }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A list of games as a grid or as lines, whichever the player picked.
struct StoreCards: View {
    let cards: [StoreCard]
    let layout: StoreLayout
    var body: some View {
        if layout == .grid { StoreGrid(cards: cards) }
        else { LazyVStack(spacing: 8) { ForEach(cards) { StoreRow(card: $0) } } }
    }
}

struct StoreLayoutToggle: View {
    @Binding var layout: StoreLayout
    var body: some View {
        HBSegment(selection: $layout, options: [(StoreLayout.grid, L("Grid")), (.list, L("List"))])
    }
}

/// A picture that fills its frame, a quiet block while it loads.
struct StoreThumb: View {
    let url: URL?
    var width: CGFloat = 240
    var height: CGFloat = 135
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.06) }
        }
        .frame(width: width, height: height)
    }
}


private struct FillGridWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A card grid whose rows always reach both edges of the page: the columns share the whole width instead of stopping at a maximum, and a
/// shelf of three or more cards that would leave a gap on a wide window uses exactly that many columns, so the row ends at the page margin.
struct FillGrid<Content: View>: View {
    let count: Int
    let minimum: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    /// The widest a card may grow when a short shelf is stretched to fill the row; beyond it the shelf keeps the normal column count.
    var maximum: CGFloat = .infinity
    @ViewBuilder let content: () -> Content
    @State private var width: CGFloat = 900

    private var columns: [GridItem] {
        let fit = max(1, Int((max(width, minimum) + spacing) / (minimum + spacing)))
        let stretched = (max(width, minimum) - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1))
        let n = (count >= 3 && count < fit && stretched <= maximum) ? count : fit
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: n)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing, content: content)
            .background(GeometryReader { Color.clear.preference(key: FillGridWidth.self, value: $0.size.width) })
            .onPreferenceChange(FillGridWidth.self) { if abs($0 - width) > 0.5 { width = $0 } }
    }
}

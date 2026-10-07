import SwiftUI
import KLYCKit

/// The answer to a set of filters, as long as the player keeps scrolling. The filters can be changed here without going back.
/// Everything it decides lives in `StoreResultsModel`; this file only draws it.
struct StoreResultsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.hubReset) private var hubReset
    let categories: [StoreCategory]
    @State private var model: StoreResultsModel
    @State private var showFilters = false
    @AppStorage("storeLayout") private var layoutRaw = StoreLayout.grid.rawValue

    init(route: StoreResultsRoute, categories: [StoreCategory]) {
        self.categories = categories
        _model = State(initialValue: StoreResultsModel(filters: route.filters, title: route.title))
    }

    private var layout: Binding<StoreLayout> { Binding(get: { StoreLayout(rawValue: layoutRaw) ?? .grid }, set: { layoutRaw = $0.rawValue }) }

    var body: some View {
        @Bindable var model = model
        ZStack {
            BottleBackdrop()
            ScrollView {
                // Lazy: the "load more" trigger only fires when the end of the list is really scrolled into view.
                LazyVStack(alignment: .leading, spacing: 16) {
                    HubHeaderSlot()
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(model.pageTitle).font(.system(size: 30, weight: .heavy, design: .rounded)).lineLimit(1)
                        if model.showsTotal { Text(String(format: L("%d games"), model.total)).font(.callout).foregroundStyle(.secondary) }
                    }
                    StoreSearchBar(term: $model.term, filterCount: model.filters.activeCount, onSubmit: model.submitTerm, onFilters: { showFilters = true })
                    toolbar(sort: $model.filters.sort)
                    activeChips
                    content
                }
                .hubPageFrame()
            }
        }
        .hbPageRoot()
        .sheet(isPresented: $showFilters) { StoreFiltersSheet(filters: $model.filters, categories: categories) {}.hbSheet() }
        .task(id: model.filters) { await model.reload(db: state.gameDB, atlas: state.atlas) }
        // The last filter taken off: that is the store's front page again, not a long list of everything.
        .onChange(of: model.filters) { old, new in if new.isPlain && !old.isPlain { hubReset() } }
    }

    private func toolbar(sort: Binding<StoreFilters.Sort>) -> some View {
        HStack(spacing: 12) {
            Menu {
                Picker(L("Sort"), selection: sort) { ForEach(StoreFilters.Sort.allCases, id: \.self) { Text(sortTitle($0)).tag($0) } }.pickerStyle(.inline)
            } label: {
                Label(sortTitle(model.filters.sort), systemImage: "arrow.up.arrow.down").font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14).frame(height: HB.Metric.secondary).hbGlass(Capsule(), interactive: true)
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            Spacer(minLength: 8)
            StoreLayoutToggle(layout: layout)
        }
    }

    /// What is switched on, each removable with one click.
    @ViewBuilder private var activeChips: some View {
        let chips = model.filters.chips
        if model.filters.hasStoreOnlyRulesOverCompat {
            Text(L("With the Mac-support choice on, categories, features, language and Steam Deck are not applied: the list comes from our own records."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if !chips.isEmpty {
            FlowLayout {
                ForEach(chips, id: \.self) { chip in
                    Button { UISound.play(.back); withAnimation(HB.Motion.quick) { model.remove(chip) } } label: {
                        HStack(spacing: 6) { Text(title(of: chip)); Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: HB.Metric.chip).background(Capsule().fill(HB.amber.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                Button(L("Clear all")) { withAnimation(HB.Motion.quick) { model.clearAll() } }.buttonStyle(HBTextButtonStyle()).font(.caption)
            }
        }
    }

    private func title(of chip: StoreFilterChip) -> String {
        let f = model.filters
        switch chip {
        case .tag(let id): return categories.first { $0.id == id }?.name ?? "#\(id)"
        case .compat:
            switch f.compat { case .works: return L("Works on this Mac"); case .tested: return L("Tested"); case .reported: return L("Player reports"); case .likely: return L("Likely to run (prediction)"); default: return L("Does not run") }
        case .list:
            switch f.list { case .topSellers: return L("Best sellers"); case .popularNew: return L("Popular new releases"); default: return L("Coming soon") }
        case .minYear(let y): return String(format: L("Released %d or later"), y)
        case .mac: return L("Has a Mac build")
        case .deck: return L("Steam Deck verified")
        case .turkish: return L("Turkish language")
        case .onSale: return L("On sale")
        case .price:
            if case .under(let n) = f.price { return String(format: L("Up to $%d"), n) }
            return L("Free to play")
        case .feature(let id): return Self.featureName(id)
        case .term(let t): return "“\(t)”"
        }
    }

    static func featureName(_ id: Int) -> String {
        switch id {
        case 2: return L("Single-player"); case 1: return L("Multi-player"); case 9: return L("Co-op"); case 28: return L("Full controller support")
        case 23: return L("Steam Cloud"); case 30: return L("Steam Workshop"); case 22: return L("Achievements"); case 29: return L("Trading cards")
        default: return "#\(id)"
        }
    }

    private func sortTitle(_ s: StoreFilters.Sort) -> String {
        switch s {
        case .relevance: return L("Most relevant"); case .newest: return L("Newest"); case .reviews: return L("Best reviewed")
        case .priceLow: return L("Price: low to high"); case .priceHigh: return L("Price: high to low"); case .name: return L("Name (A to Z)")
        }
    }

    // MARK: results

    @ViewBuilder private var content: some View {
        contentBody.animation(HB.Motion.standard, value: model.cards.isEmpty).animation(HB.Motion.standard, value: model.loading)
    }

    @ViewBuilder private var contentBody: some View {
        if model.cards.isEmpty && model.loading {
            Group { if layout.wrappedValue == .grid { SkeletonGrid(count: 12) } else { SkeletonRows(count: 8) } }.transition(.opacity)
        } else if model.cards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.failed ? L("The store could not be reached. Check the connection and open this tab again.") : L("Nothing matches these filters.")).foregroundStyle(.secondary)
                if model.failed { Button(L("Try again")) { Task { await model.reload(db: state.gameDB, atlas: state.atlas) } }.buttonStyle(HBSecondaryButtonStyle()) }
            }.padding(.top, 20)
        } else {
            StoreCards(cards: model.cards, layout: layout.wrappedValue)
            if model.loading { HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.padding(.vertical, 12) }
            else if model.hasMore {
                Color.clear.frame(height: 1).onAppear { Task { await model.more() } }
                Button(L("Show more")) { Task { await model.more() } }.buttonStyle(HBSecondaryButtonStyle()).frame(maxWidth: .infinity)
            }
        }
    }
}

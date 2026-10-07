import SwiftUI
import KLYCKit

/// Every filter the store has, in one window: platform, price, features, language and all of Steam's categories.
struct StoreFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: StoreFilters
    let categories: [StoreCategory]
    let onApply: () -> Void
    @State private var tagSearch = ""
    @State private var showAllTags = false

    private let prices: [(StoreFilters.Price, String)] = [(.any, "Any"), (.free, "Free to play"), (.under(5), "Up to $5"), (.under(10), "Up to $10"), (.under(20), "Up to $20"), (.under(30), "Up to $30")]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Filters")).font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button(L("Clear all")) { let s = filters.sort; filters = StoreFilters(); filters.sort = s }.disabled(filters.activeCount == 0)
                Button { dismiss() } label: { Image(systemName: "xmark") }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    group(L("Lists")) {
                        pill(L("Any"), on: filters.list == .none) { filters.list = .none }
                        pill(L("Best sellers"), on: filters.list == .topSellers) { filters.list = .topSellers }
                        pill(L("Popular new releases"), on: filters.list == .popularNew) { filters.list = .popularNew }
                        pill(L("Coming soon"), on: filters.list == .comingSoon) { filters.list = .comingSoon }
                    }
                    group(L("Release")) {
                        let year = Calendar.current.component(.year, from: Date())
                        pill(L("Any"), on: filters.minYear == nil) { filters.minYear = nil }
                        pill(L("Last year"), on: filters.minYear == year - 1) { filters.minYear = year - 1 }
                        pill(L("Last 2 years"), on: filters.minYear == year - 2) { filters.minYear = year - 2 }
                        pill(L("Last 5 years"), on: filters.minYear == year - 5) { filters.minYear = year - 5 }
                    }
                    group(L("On this Mac")) {
                        pill(L("Any"), on: filters.compat == .any) { filters.compat = .any }
                        pill(L("Works (tested or reported)"), on: filters.compat == .works) { filters.compat = .works }
                        pill(L("Tested"), on: filters.compat == .tested) { filters.compat = .tested }
                        pill(L("Player reports"), on: filters.compat == .reported) { filters.compat = .reported }
                        pill(L("Likely to run (prediction)"), on: filters.compat == .likely) { filters.compat = .likely }
                        pill(L("Does not run"), on: filters.compat == .blocked) { filters.compat = .blocked }
                    }
                    group(L("Platform and language")) {
                        toggle(L("Has a Mac build"), "applelogo", $filters.mac)
                        toggle(L("Steam Deck verified"), "gamecontroller", $filters.deckVerified)
                        toggle(L("Turkish language"), "character.bubble", $filters.turkish)
                    }
                    group(L("Discounts")) { toggle(L("On sale"), "tag", $filters.onSale) }
                    group(L("Price")) {
                        ForEach(prices, id: \.1) { price, title in
                            pill(L(title), on: filters.price == price) { filters.price = price }
                        }
                    }
                    group(L("Features")) {
                        ForEach(StoreFilters.features, id: \.self) { id in
                            pill(StoreResultsView.featureName(id), on: filters.feature.contains(id)) {
                                if filters.feature.contains(id) { filters.feature.remove(id) } else { filters.feature.insert(id) }
                            }
                        }
                    }
                    categoriesSection
                }
                .padding(24)
            }
            Divider().opacity(0.3)
            HStack {
                Text(filters.activeCount == 0 ? L("No filters") : String(format: L("%d filters on"), filters.activeCount)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Show games")) { onApply(); dismiss() }.buttonStyle(HBPrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 680, height: 660)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { HB.eyebrow(title); FlowLayout { content() } }
    }

    private func toggle(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        Button { UISound.play(.select); on.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: HB.Metric.chip)
                .background(Capsule().fill(on.wrappedValue ? HB.amber.opacity(0.7) : Color.white.opacity(0.09)))
                .animation(HB.Motion.quick, value: on.wrappedValue)
        }.buttonStyle(.plain)
    }

    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { UISound.play(.select); action() } label: {
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: HB.Metric.chip)
                .background(Capsule().fill(on ? HB.amber.opacity(0.7) : Color.white.opacity(0.09)))
                .animation(HB.Motion.quick, value: on)
        }.buttonStyle(.plain)
    }

    private var categoriesSection: some View {
        let needle = tagSearch.trimmingCharacters(in: .whitespaces)
        let chosen = categories.filter { filters.tags.contains($0.id) }
        var shown = needle.isEmpty ? (showAllTags ? categories : Array(categories.prefix(24))) : categories.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        shown = chosen + shown.filter { !filters.tags.contains($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HB.eyebrow(L("Categories"))
                Spacer(minLength: 8)
                Text(String(format: L("%d in Steam"), categories.count)).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Find a category"), text: $tagSearch).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(Color.white.opacity(0.07)))
            if categories.isEmpty { ProgressView().controlSize(.small) }
            FlowLayout {
                ForEach(shown) { c in
                    pill(c.name, on: filters.tags.contains(c.id)) {
                        if filters.tags.contains(c.id) { filters.tags.removeAll { $0 == c.id } } else { filters.tags.append(c.id) }
                    }
                }
            }
            if needle.isEmpty && !showAllTags && categories.count > 24 {
                Button(String(format: L("Show all %d categories"), categories.count)) { showAllTags = true }.buttonStyle(HBTextButtonStyle())
            }
        }
    }
}

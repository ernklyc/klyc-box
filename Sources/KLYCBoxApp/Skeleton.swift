import SwiftUI
import KLYCKit

/// A quiet placeholder while something loads: a block with a slow light moving across it. With Reduce Motion it just sits there.
struct SkeletonBlock: View {
    var radius: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(0.06))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.09), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.55).offset(x: phase * geo.size.width * 1.4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                }
            }
            .onAppear { guard !reduceMotion else { return }; withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 } }
            .accessibilityHidden(true)
    }
}

/// The shape of a store tile while its picture and text load.
struct SkeletonTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(460.0 / 215.0, contentMode: .fit).overlay { SkeletonBlock(radius: 12) }
            SkeletonBlock(radius: 5).frame(width: 150, height: 12)
            SkeletonBlock(radius: 9).frame(width: 110, height: 18)
            SkeletonBlock(radius: 5).frame(width: 70, height: 12)
        }
    }
}

struct SkeletonGrid: View {
    var count = 8
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
            ForEach(0..<count, id: \.self) { _ in SkeletonTile() }
        }
    }
}

/// The shape of the Downloads page's download card while its first look is still under way.
struct SkeletonDownloadCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonBlock(radius: 5).frame(width: 110, height: 11)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(radius: 5).frame(width: 220, height: 14)
                    SkeletonBlock(radius: 4).frame(height: 6)
                    SkeletonBlock(radius: 5).frame(width: 160, height: 11)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
        .accessibilityLabel(L("Loading"))
    }
}

struct SkeletonRows: View {
    var count = 6
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: HB.Space.m) {
                    SkeletonBlock(radius: 8).frame(width: 150, height: 70)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(radius: 5).frame(width: 220, height: 14)
                        SkeletonBlock(radius: 9).frame(width: 150, height: 18)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
            }
        }
    }
}

/// A shelf (title and a row of tiles) while its games are being fetched.
struct SkeletonShelf: View {
    var count = 4
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(radius: 4).frame(width: 190, height: 11)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(0..<count, id: \.self) { _ in SkeletonTile() }
            }
        }
    }
}

/// The three featured games while they load.
struct SkeletonFeatured: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in SkeletonBlock(radius: 14).frame(height: 150) }
        }
    }
}

/// What the store's front page keeps between visits to its tab: switching to the library and back must not fetch everything again.
@Observable @MainActor
final class StoreFrontModel {
    var shelves: [StoreShelf] = []
    var lists: [String: [StoreCard]] = [:]
    var categories: [StoreCategory] = []
    var loading = true
    var listsLoading = false
    private var loadedAt: Date?
    private var inFlight = false
    /// Fresh enough to show without asking again.
    static let maxAge: TimeInterval = 10 * 60

    var isFresh: Bool { loadedAt.map { Date().timeIntervalSince($0) < Self.maxAge } ?? false }

    /// The featured row and the Mac lists, read one after another (the store answers politely that way).
    func load(lists specs: [(key: String, filters: StoreFilters)], force: Bool = false) async {
        guard !inFlight, force || !isFresh else { return }
        inFlight = true; defer { inFlight = false }
        if force { shelves = []; lists = [:]; loading = true }
        async let c = SteamStore.categories()
        if shelves.isEmpty { shelves = await SteamStore.featured() }
        loading = false
        listsLoading = true
        for spec in specs where lists[spec.key] == nil {
            let slice = await SteamStore.collect(spec.filters, want: 8)
            if !slice.failed { lists[spec.key] = Array(slice.cards.prefix(8)) }
        }
        listsLoading = false
        if categories.isEmpty { categories = await c }
        // Only a complete read counts as fresh: a failed one is tried again on the next visit.
        if !shelves.isEmpty && specs.allSatisfy({ lists[$0.key] != nil }) { loadedAt = Date() }
    }
}

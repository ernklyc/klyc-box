import Observation
import KLYCKit

/// State and decisions of the library screen. The view only draws what this says; the filtering and ordering
/// itself is `LibraryQuery` in KLYCKit, which is tested without a window.
@Observable @MainActor
final class LibraryViewModel {
    var query: LibraryQuery
    /// The game under the pointer: its art becomes the screen's background.
    var hovered: LibraryItem?

    init(source: LibrarySource? = nil, show: LibraryQuery.Show = .installed) { query = LibraryQuery(source: source, show: show) }

    func items(in state: AppState) -> [LibraryItem] {
        query.apply(to: state.libraryItems, favorites: state.favorites,
                    title: { state.displayTitle($0) },
                    isReady: { state.gameDB.entry(for: $0)?.status == "verified-local" })
    }

    var pageTitle: String {
        switch query.source { case .steam?: return "Steam"; case .epic?: return "Epic Games"; default: return L("Library") }
    }
}

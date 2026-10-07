import Observation
import KLYCKit

/// State and decisions of the home screen: which game is focused, what the search typed, who can be played.
/// The shelf's order is `HomeShelf` in KLYCKit (tested); this class only holds the focus.
@Observable @MainActor
final class HomeViewModel {
    var focusID: String?
    var search = ""

    func shelf(in state: AppState) -> [LibraryItem] {
        HomeShelf.order(state.libraryItems, favorites: state.favorites, search: search, title: { state.displayTitle($0) })
    }

    func focused(in shelf: [LibraryItem]) -> LibraryItem? {
        shelf.first { $0.id == focusID } ?? shelf.first
    }

    /// One step along the shelf; false when already at the end.
    func move(_ delta: Int, in shelf: [LibraryItem]) -> Bool {
        guard let i = shelf.firstIndex(where: { $0.id == focused(in: shelf)?.id }) else { return false }
        let n = min(max(i + delta, 0), shelf.count - 1)
        guard n != i else { return false }
        focusID = shelf[n].id
        return true
    }

    func canPlay(_ item: LibraryItem, in state: AppState) -> Bool {
        let blocked = state.gameDB.entry(for: item)?.isBlocked == true
        return (state.prefersMacBuild(item) || (item.installed && !blocked)) && !state.busy
    }

    /// The games next to the focused one, whose key art is worth fetching ahead of time.
    func neighbours(of focused: LibraryItem?, in shelf: [LibraryItem]) -> [LibraryItem] {
        guard let i = shelf.firstIndex(where: { $0.id == focused?.id }) else { return [] }
        return [i - 1, i + 1, i + 2].filter { shelf.indices.contains($0) }.map { shelf[$0] }
    }
}

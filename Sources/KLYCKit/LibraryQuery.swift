import Foundation

/// What the library screen shows: which games, in which order. Pure, so it is tested without a window.
public struct LibraryQuery: Equatable, Sendable {
    public enum Show: String, CaseIterable, Sendable { case installed, all, ready, favorites }
    public enum Sort: String, CaseIterable, Sendable { case name, recent, size }

    public var source: LibrarySource?
    public var show: Show
    public var sort: Sort
    public var search: String

    public init(source: LibrarySource? = nil, show: Show = .installed, sort: Sort = .name, search: String = "") {
        self.source = source; self.show = show; self.sort = sort; self.search = search
    }

    /// `title` is the name the user sees (a custom name beats the store's); `isReady` says the compatibility
    /// database verified the game on this machine class.
    public func apply(to items: [LibraryItem], favorites: Set<String>,
                      title: (LibraryItem) -> String, isReady: (LibraryItem) -> Bool) -> [LibraryItem] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            if let source, item.source != source { return false }
            switch show {
            case .installed: if !item.installedAnywhere { return false }
            case .all: break
            case .ready: if !isReady(item) { return false }
            case .favorites: if !favorites.contains(item.id) { return false }
            }
            if !needle.isEmpty, !item.title.localizedCaseInsensitiveContains(needle),
               !title(item).localizedCaseInsensitiveContains(needle) { return false }
            return true
        }
        .sorted { a, b in
            let byName = title(a).localizedCaseInsensitiveCompare(title(b)) == .orderedAscending
            switch sort {
            case .name: return byName
            case .recent:
                let (x, y) = (a.lastPlayed ?? .distantPast, b.lastPlayed ?? .distantPast)
                return x != y ? x > y : byName
            case .size: return a.sizeOnDisk != b.sizeOnDisk ? a.sizeOnDisk > b.sizeOnDisk : byName
            }
        }
    }
}

/// The order of the home screen's shelf: starred games first, then what was played last, then the rest of what is installed.
public enum HomeShelf {
    public static func order(_ items: [LibraryItem], favorites: Set<String>, search: String = "",
                             title: (LibraryItem) -> String) -> [LibraryItem] {
        let installed = items.filter { $0.installedAnywhere }
        func recentFirst(_ list: [LibraryItem]) -> [LibraryItem] {
            list.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
        let stars = recentFirst(installed.filter { favorites.contains($0.id) })
        let played = recentFirst(installed.filter { $0.lastPlayed != nil && !favorites.contains($0.id) })
        var seen = Set((stars + played).map(\.id))
        var all = stars + played
        for item in installed where !seen.contains(item.id) { all.append(item); seen.insert(item.id) }
        let needle = search.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? all : all.filter { title($0).localizedCaseInsensitiveContains(needle) }
    }
}

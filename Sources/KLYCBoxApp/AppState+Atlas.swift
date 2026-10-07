import KLYCKit

/// The Atlas feed: the cache is read at once, and a newer feed is fetched in the background (at most once a day).
/// Nothing here runs until the site's address is configured (`AtlasSite`).
extension AppState {
    func loadAtlas() {
        let store = AtlasFeedStore(paths: paths)
        if atlas.isEmpty { atlas = store.cached() }
        guard let url = AtlasSite.feedURL() else { return }
        Task { [weak self] in
            let feed = await store.refresh(url: url)
            await MainActor.run { if let self, feed != self.atlas { self.atlas = feed } }
        }
    }

    func atlasEntry(for item: LibraryItem) -> AtlasEntry? { item.steamAppID.flatMap { atlas[$0] } }
}

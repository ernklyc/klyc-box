import Foundation

/// What is known about modding one game: where its mod folders are and a few plain notes.
/// Data in `db/mods.json`, keyed by library id ("steam:244210"); a game without an entry still gets the generic tools.
public struct ModCatalog: Codable, Sendable {
    public struct Folder: Codable, Sendable, Hashable { public var title: String; public var path: String }
    public struct Entry: Codable, Sendable {
        public var folders: [Folder]?
        public var notes: [String]?
    }
    public var games: [String: Entry]

    public init(games: [String: Entry] = [:]) { self.games = games }

    public func entry(for libraryID: String) -> Entry? { games[libraryID] }

    /// The catalog shipped inside the app, or `db/mods.json` of the repository when run from source.
    public static func load(bundle: Bundle = .main, fallback: URL = URL(fileURLWithPath: "db/mods.json")) -> ModCatalog {
        for url in [bundle.url(forResource: "mods", withExtension: "json"), fallback].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(ModCatalog.self, from: data) { return catalog }
        }
        return ModCatalog()
    }
}

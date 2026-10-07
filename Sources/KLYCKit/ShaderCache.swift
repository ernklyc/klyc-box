import Foundation

/// A Steam game's shader cache: what its graphics layer compiled while it ran, kept by Steam in
/// `steamapps/shadercache/<appid>` next to the game's manifest so the next start does not
/// compile it again.
///
/// It already persists across sessions, game updates and KLYC-Box's own cleanups; nothing here
/// warms it up (a cache can only be filled by playing). What a player can use is to see how much
/// space it takes and to clear it when a game shows glitches or crashes after a graphics-mode,
/// engine or driver change, which is the standard first step for a corrupt cache. It is only
/// ever a cache: the game rebuilds it, with some stutter in the first minutes.
public enum ShaderCache {
    /// The cache folders that exist for a game, one per Steam library folder that holds it.
    /// `steamapps` are the library folders' `steamapps` directories.
    public static func folders(appid: Int, steamapps: [URL]) -> [URL] {
        steamapps.compactMap { dir in
            guard FileManager.default.fileExists(atPath: dir.appending(path: "appmanifest_\(appid).acf").path) else { return nil }
            let cache = dir.appending(path: "shadercache/\(appid)", directoryHint: .isDirectory)
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: cache.path, isDirectory: &isDir) && isDir.boolValue ? cache : nil
        }
    }

    /// Total bytes of the files under the folders.
    public static func size(of folders: [URL]) -> UInt64 {
        var total: UInt64 = 0
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { continue }
            for case let url as URL in walker {
                let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true { total += UInt64(v?.fileSize ?? 0) }
            }
        }
        return total
    }

    /// The only shape that is deleted: `.../shadercache/<digits>`. Anything else is refused, so a
    /// wrong path can never turn this into a general delete.
    static func isCacheFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return !name.isEmpty && name.allSatisfy(\.isNumber) && url.deletingLastPathComponent().lastPathComponent == "shadercache"
    }

    /// Empties the folders (Steam expects the folder itself to stay) and returns the bytes freed.
    @discardableResult
    public static func clear(_ folders: [URL]) -> UInt64 {
        let before = size(of: folders.filter(isCacheFolder))
        for folder in folders where isCacheFolder(folder) {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
        return before - size(of: folders.filter(isCacheFolder))
    }
}

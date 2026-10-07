import Foundation

/// A folder that holds games from somewhere else (another launcher's library, a drive of installs): which Steam games it carries
/// and which plain game folders it has, each with the program to start. Nothing is changed here; this only looks.
public struct GameFolderScan: Sendable, Equatable {
    public struct Program: Sendable, Equatable {
        public var name: String
        public var executable: URL
        public init(name: String, executable: URL) { self.name = name; self.executable = executable }
    }
    /// The folder, when it has a `steamapps` with Steam manifests: Steam can use it as a library folder.
    public var steamLibrary: URL?
    public var steamGames: [String]
    public var programs: [Program]
    public var isEmpty: Bool { steamLibrary == nil && programs.isEmpty }

    static let skipFolders: Set<String> = ["steamapps", "logs", "downloads", "tmp", "temp", "cache", "backup", "backups", "__macosx"]
    /// Files that are part of a game's plumbing, not the game.
    static let skipExecutables = ["unins", "crash", "redist", "vc_redist", "dxsetup", "dotnet", "windowsdesktop", "setup", "installer", "helper", "eosoverlay", "easyanticheat", "battleye", "report"]

    public static func scan(_ root: URL, fileManager fm: FileManager = .default) -> GameFolderScan {
        var steamLibrary: URL?
        var steamGames: [String] = []
        let steamapps = root.appending(path: "steamapps", directoryHint: .isDirectory)
        if let files = try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      let m = text.firstMatch(of: #/"name"\s+"([^"]*)"/#), !text.contains("\"appid\"\t\t\"228980\"") else { continue }
                steamGames.append(String(m.1))
            }
            if !steamGames.isEmpty { steamLibrary = root }
        }
        var programs: [Program] = []
        let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for dir in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, !skipFolders.contains(dir.lastPathComponent.lowercased()),
                  let exe = bestExecutable(in: dir, fileManager: fm) else { continue }
            programs.append(Program(name: humanName(dir.lastPathComponent), executable: exe))
        }
        return GameFolderScan(steamLibrary: steamLibrary, steamGames: steamGames.sorted(), programs: programs)
    }

    /// The games a Steam library folder holds, with their sizes, for the library list Steam keeps.
    public static func steamAppSizes(in library: URL, fileManager fm: FileManager = .default) -> [(appid: String, bytes: Int64)] {
        let steamapps = library.appending(path: "steamapps", directoryHint: .isDirectory)
        let files = (try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }.compactMap { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8), let id = text.firstMatch(of: #/"appid"\s+"(\d+)"/#) else { return nil }
            let size = text.firstMatch(of: #/"SizeOnDisk"\s+"(\d+)"/#).flatMap { Int64($0.1) } ?? 0
            return (String(id.1), size)
        }
    }

    /// "AlanWakeRemastered" → "Alan Wake Remastered".
    static func humanName(_ folder: String) -> String {
        var out = ""
        for (i, ch) in folder.enumerated() {
            if i > 0, ch.isUppercase, let last = out.last, last.isLowercase || last.isNumber { out.append(" ") }
            out.append(ch)
        }
        return out.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The program to start: the one named like the folder, else the biggest at the top of the folder, else the biggest one level down.
    static func bestExecutable(in folder: URL, fileManager fm: FileManager) -> URL? {
        func executables(depth: Int) -> [(url: URL, size: Int)] {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
            var out: [(URL, Int)] = []
            func add(_ url: URL) {
                guard url.pathExtension.lowercased() == "exe" else { return }
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                if skipExecutables.contains(where: { name.contains($0) }) { return }
                out.append((url, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            }
            for item in items {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if depth >= 2, let inner = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) { inner.forEach(add) }
                } else { add(item) }
            }
            return out
        }
        func compact(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let target = compact(folder.lastPathComponent)
        for depth in [1, 2] {
            let found = executables(depth: depth)
            if let named = found.first(where: { compact($0.url.deletingPathExtension().lastPathComponent) == target }) { return named.url }
            if let biggest = found.max(by: { $0.size < $1.size }) { return biggest.url }
        }
        return nil
    }
}

/// Steam's `libraryfolders.vdf`: the places Steam keeps games. Reading maps Windows paths to the Mac's; adding writes one more place.
public enum SteamLibraryFolders {
    /// "Z:\Volumes\SSD\GameHub" as Wine sees it, from the Mac path (Wine's Z: is the whole disk).
    public static func windowsPath(forHost path: String) -> String { "Z:" + path.replacingOccurrences(of: "/", with: "\\") }

    /// A path as Steam wrote it, on the Mac. `driveC` is the bottle's C:, `dosdevices` its drive letters.
    public static func hostPath(forWindows path: String, driveC: URL, dosdevices: URL) -> URL? {
        let unescaped = path.replacingOccurrences(of: "\\\\", with: "\\")
        guard unescaped.count >= 2, unescaped[unescaped.index(after: unescaped.startIndex)] == ":" else { return nil }
        let letter = unescaped.prefix(1).lowercased()
        let rest = unescaped.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        if letter == "c" { return URL(fileURLWithPath: driveC.path + (rest.hasPrefix("/") ? rest : "/" + rest)).standardizedFileURL }
        if letter == "z" { return URL(fileURLWithPath: rest.isEmpty ? "/" : rest).standardizedFileURL }
        let link = dosdevices.appending(path: "\(letter):")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        let base = target.hasPrefix("/") ? URL(fileURLWithPath: target) : dosdevices.appending(path: target)
        return URL(fileURLWithPath: base.standardizedFileURL.path + (rest.hasPrefix("/") ? rest : "/" + rest)).standardizedFileURL
    }

    /// Every library folder Steam lists, other than its own, on the Mac.
    public static func extraFolders(vdf text: String, driveC: URL, dosdevices: URL) -> [URL] {
        let own = driveC.appending(path: "Program Files (x86)/Steam").standardizedFileURL.path.lowercased()
        var out: [URL] = []
        for m in text.matches(of: #/"path"\s+"((?:\\.|[^"\\])*)"/#) {
            guard let url = hostPath(forWindows: String(m.1), driveC: driveC, dosdevices: dosdevices), url.path.lowercased() != own, !out.contains(url) else { continue }
            out.append(url)
        }
        return out
    }

    /// The library folders both this Steam and another Steam list. Two Steam installs on one folder each try to update its games
    /// (and one may replace the other's version), which is how a Mac build and a Windows build end up fighting.
    public static func shared(vdf text: String, driveC: URL, dosdevices: URL, with other: [URL]) -> [URL] {
        let theirs = Set(other.map { $0.standardizedFileURL.path.lowercased() })
        return extraFolders(vdf: text, driveC: driveC, dosdevices: dosdevices).filter { theirs.contains($0.standardizedFileURL.path.lowercased()) }
    }

    /// The file's text without the given library folders (Steam's own, number 0, always stays), or nil when none of them is listed.
    public static func removing(folders: [URL], from text: String, driveC: URL, dosdevices: URL) -> String? {
        let drop = Set(folders.map { $0.standardizedFileURL.path.lowercased() })
        var out = text, changed = false
        for block in text.matches(of: #/\t"(\d+)"\n\t\{.*?\n\t\}\n/#.dotMatchesNewlines()) {
            let body = String(block.0)
            guard block.1 != "0", let path = body.firstMatch(of: #/"path"\s+"((?:\\.|[^"\\])*)"/#),
                  let host = hostPath(forWindows: String(path.1), driveC: driveC, dosdevices: dosdevices),
                  drop.contains(host.standardizedFileURL.path.lowercased()) else { continue }
            out = out.replacingOccurrences(of: body, with: ""); changed = true
        }
        return changed ? out : nil
    }

    public static func contains(vdf text: String, windowsPath: String) -> Bool {
        let wanted = windowsPath.lowercased()
        return text.matches(of: #/"path"\s+"((?:\\.|[^"\\])*)"/#).contains { String($0.1).replacingOccurrences(of: "\\\\", with: "\\").lowercased() == wanted }
    }

    /// The file's text with one more library folder (and the games it holds), or nil when it is already listed or the file is not
    /// in the shape Steam writes. Steam must not be running: it rewrites this file when it quits.
    public static func adding(folder: URL, games: [(appid: String, bytes: Int64)], to text: String) -> String? {
        let win = windowsPath(forHost: folder.path)
        guard !contains(vdf: text, windowsPath: win), let close = text.lastIndex(of: "}") else { return nil }
        let keys = text.matches(of: #/^\t"(\d+)"\s*$/#.anchorsMatchLineEndings()).compactMap { Int($0.1) }
        let next = (keys.max() ?? -1) + 1
        let escaped = win.replacingOccurrences(of: "\\", with: "\\\\")
        var block = "\t\"\(next)\"\n\t{\n\t\t\"path\"\t\t\"\(escaped)\"\n\t\t\"label\"\t\t\"\"\n\t\t\"contentid\"\t\t\"\(UInt64.random(in: 1...UInt64(Int64.max)))\"\n\t\t\"totalsize\"\t\t\"0\"\n\t\t\"apps\"\n\t\t{\n"
        for g in games { block += "\t\t\t\"\(g.appid)\"\t\t\"\(g.bytes)\"\n" }
        block += "\t\t}\n\t}\n"
        var out = text
        out.insert(contentsOf: block, at: close)
        return out
    }
}

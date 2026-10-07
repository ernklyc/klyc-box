import Foundation

/// Finding a game's save files inside its Wine environment, and backing them up and restoring them.
/// Saves are looked for where Windows games keep them (Documents, My Games, AppData, Saved Games) by the game's
/// name, plus Steam's own cloud-save folder for the game id. A guess, so the page shows what was found.
public enum SaveLocator {
    public struct Candidate: Hashable, Sendable {
        public var title: String
        public var url: URL
        public init(title: String, url: URL) { self.title = title; self.url = url }
    }

    static func normalized(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    public static func candidates(driveC: URL, steamAppID: Int?, names: [String]) -> [Candidate] {
        let fm = FileManager.default
        var found: [Candidate] = []
        // Steam Cloud saves: userdata/<account>/<appid>
        if let appid = steamAppID {
            let userdata = driveC.appending(path: "Program Files (x86)/Steam/userdata")
            for account in (try? fm.contentsOfDirectory(atPath: userdata.path)) ?? [] {
                let url = userdata.appending(path: "\(account)/\(appid)")
                if isDirectory(url) { found.append(Candidate(title: "Steam: \(appid)", url: url)) }
            }
        }
        let keys = names.map(normalized).filter { $0.count >= 4 }
        guard !keys.isEmpty else { return found }
        let users = driveC.appending(path: "users")
        let subroots = ["Documents", "Documents/My Games", "AppData/Roaming", "AppData/Local", "AppData/LocalLow", "Saved Games"]
        for user in (try? fm.contentsOfDirectory(atPath: users.path)) ?? [] where user != "Public" {
            for sub in subroots {
                let root = users.appending(path: "\(user)/\(sub)")
                for child in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
                    let key = normalized(child)
                    guard key.count >= 4, keys.contains(where: { $0 == key || $0.contains(key) || key.contains($0) }) else { continue }
                    let url = root.appending(path: child)
                    if isDirectory(url) { found.append(Candidate(title: "\(sub)/\(child)", url: url)) }
                }
            }
        }
        return Array(Set(found)).sorted { $0.url.path < $1.url.path }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }
}

public enum SaveBackup {
    public struct Entry: Identifiable, Hashable, Sendable {
        public var url: URL
        public var date: Date
        public var size: Int64
        public var id: URL { url }
    }

    public enum Failure: Error, Equatable { case nothingToBackUp, toolFailed(String) }

    /// Zips the folders (kept under their path inside the environment, so restoring puts them back exactly).
    @discardableResult
    public static func create(folders: [URL], driveC: URL, into directory: URL, now: Date = Date()) throws -> URL {
        let root = driveC.resolvingSymlinksInPath().path + "/"
        let relatives = folders.compactMap { f -> String? in
            let p = f.resolvingSymlinksInPath().path
            return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : nil
        }
        guard !relatives.isEmpty else { throw Failure.nothingToBackUp }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let out = directory.appending(path: "saves-\(f.string(from: now)).zip")
        try run("/usr/bin/zip", ["-r", "-q", "-y", out.path] + relatives, in: driveC)
        return out
    }

    public static func list(in directory: URL) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension == "zip" }.compactMap { u in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return Entry(url: u, date: v?.contentModificationDate ?? .distantPast, size: Int64(v?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    /// Puts a backup back. The saves as they are now are zipped first, so a restore can itself be undone.
    public static func restore(_ backup: URL, driveC: URL, currentFolders: [URL], safetyDirectory: URL) throws {
        if !currentFolders.isEmpty { _ = try? create(folders: currentFolders, driveC: driveC, into: safetyDirectory) }
        try run("/usr/bin/unzip", ["-o", "-q", backup.path, "-d", driveC.path], in: driveC)
    }

    static func run(_ tool: String, _ arguments: [String], in directory: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool); p.arguments = arguments; p.currentDirectoryURL = directory
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw Failure.toolFailed(String(decoding: err.fileHandleForReading.readDataToEndOfFile().suffix(300), as: UTF8.self))
        }
    }
}

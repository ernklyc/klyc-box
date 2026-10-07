import Foundation

/// Puts mod files into a game's folder without losing anything: whatever a mod replaces is copied to a
/// backup first, every install is recorded, and the last one can be undone. Pure file work, no Wine.
public enum ModInstaller {
    public struct Plan: Equatable, Sendable {
        /// Destination path (relative to the game folder) for every file, in order.
        public var files: [(source: URL, relative: String)]
        public var conflicts: [String]
        public static func == (l: Plan, r: Plan) -> Bool { l.files.map(\.relative) == r.files.map(\.relative) && l.conflicts == r.conflicts }
    }

    public struct Result: Equatable, Sendable {
        public var added: [String]
        public var replaced: [String]
        public var skipped: [String]
    }

    public struct Record: Codable, Equatable, Sendable {
        public var date: Date
        public var added: [String]
        public var replaced: [String]
        public var backup: String
    }

    public enum Failure: Error, Equatable { case outsideGameFolder, nothingToInstall }

    static let backupDirName = ".klyc-mod-backups"

    /// What installing `sources` into `root`/`subfolder` would do: every file's destination, and which already exist.
    /// A folder is copied with its name (and everything under it); a file lands directly in the destination.
    public static func plan(sources: [URL], into root: URL, subfolder: String? = nil) throws -> Plan {
        let base = try destination(root: root, subfolder: subfolder)
        var files: [(URL, String)] = []
        let fm = FileManager.default
        for source in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { continue }
            let head = source.lastPathComponent
            if isDir.boolValue {
                // The enumerator reports resolved paths (/private/var for /var), so both sides are resolved first.
                let resolved = source.resolvingSymlinksInPath()
                let walker = fm.enumerator(at: resolved, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let url = walker?.nextObject() as? URL {
                    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    let inner = String(url.resolvingSymlinksInPath().path.dropFirst(resolved.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    files.append((url, relativePath(base: base, root: root, tail: head + "/" + inner)))
                }
            } else {
                files.append((source, relativePath(base: base, root: root, tail: head)))
            }
        }
        guard !files.isEmpty else { throw Failure.nothingToInstall }
        // Every destination must stay inside the game folder, whatever a path contains.
        let rootPath = root.standardizedFileURL.path + "/"
        for (_, relative) in files where !root.appending(path: relative).standardizedFileURL.path.hasPrefix(rootPath) { throw Failure.outsideGameFolder }
        let conflicts = files.map(\.1).filter { fm.fileExists(atPath: root.appending(path: $0).path) }
        return Plan(files: files, conflicts: conflicts)
    }

    /// Copies the plan. With `overwrite` false an existing file is left alone; with true it is backed up and replaced.
    @discardableResult
    public static func install(_ plan: Plan, into root: URL, overwrite: Bool, now: Date = Date()) throws -> Result {
        let fm = FileManager.default
        var added: [String] = [], replaced: [String] = [], skipped: [String] = []
        let stamp = backupStamp(now)
        let backup = root.appending(path: "\(backupDirName)/\(stamp)", directoryHint: .isDirectory)
        for (source, relative) in plan.files {
            let target = root.appending(path: relative)
            let exists = fm.fileExists(atPath: target.path)
            if exists && !overwrite { skipped.append(relative); continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if exists {
                let saved = backup.appending(path: "files/\(relative)")
                try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: target, to: saved)
                try fm.removeItem(at: target)
                replaced.append(relative)
            } else {
                added.append(relative)
            }
            try fm.copyItem(at: source, to: target)
        }
        if !added.isEmpty || !replaced.isEmpty {
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            let record = Record(date: now, added: added, replaced: replaced, backup: stamp)
            try JSONEncoder.klycbox.encode(record).write(to: backup.appending(path: "record.json"), options: .atomic)
        }
        return Result(added: added, replaced: replaced, skipped: skipped)
    }

    /// Every install that has not been undone, newest first.
    public static func records(in root: URL) -> [Record] {
        let dir = root.appending(path: backupDirName, directoryHint: .isDirectory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted().reversed()
        return names.compactMap { name in
            (try? Data(contentsOf: dir.appending(path: "\(name)/record.json"))).flatMap { try? JSONDecoder.klycbox.decode(Record.self, from: $0) }
        }
    }

    /// The most recent install that has not been undone.
    public static func lastRecord(in root: URL) -> Record? {
        let dir = root.appending(path: backupDirName, directoryHint: .isDirectory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        for name in names.reversed() {
            if let data = try? Data(contentsOf: dir.appending(path: "\(name)/record.json")),
               let record = try? JSONDecoder.klycbox.decode(Record.self, from: data) { return record }
        }
        return nil
    }

    /// Removes what the last install added, puts back what it replaced, and forgets the record.
    @discardableResult
    public static func undoLast(in root: URL) throws -> Int {
        guard let record = lastRecord(in: root) else { return 0 }
        let fm = FileManager.default
        let backup = root.appending(path: "\(backupDirName)/\(record.backup)", directoryHint: .isDirectory)
        for relative in record.added { try? fm.removeItem(at: root.appending(path: relative)) }
        for relative in record.replaced {
            let target = root.appending(path: relative)
            try? fm.removeItem(at: target)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: backup.appending(path: "files/\(relative)"), to: target)
        }
        try? fm.removeItem(at: backup)
        // Folders the install created and nothing else uses.
        for relative in record.added {
            var dir = root.appending(path: relative).deletingLastPathComponent()
            while dir.standardizedFileURL.path.count > root.standardizedFileURL.path.count,
                  (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
                try? fm.removeItem(at: dir); dir.deleteLastPathComponent()
            }
        }
        return record.added.count + record.replaced.count
    }

    // MARK: helpers

    static func destination(root: URL, subfolder: String?) throws -> String {
        guard let sub = subfolder?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), !sub.isEmpty else { return "" }
        let probe = root.appending(path: sub).standardizedFileURL.path + "/"
        guard probe.hasPrefix(root.standardizedFileURL.path + "/") else { throw Failure.outsideGameFolder }
        return sub
    }

    static func relativePath(base: String, root: URL, tail: String) -> String {
        base.isEmpty ? tail : base + "/" + tail
    }

    static func backupStamp(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}

/// How a Unix path looks to a program running under Wine: the game's folder as the Windows path a mod
/// tool asks for ("where is the game installed?").
public enum WindowsPath {
    public static func string(for url: URL, driveC: URL) -> String {
        let path = url.standardizedFileURL.path, root = driveC.standardizedFileURL.path
        if path == root { return "C:\\" }
        if path.hasPrefix(root + "/") { return "C:\\" + path.dropFirst(root.count + 1).replacingOccurrences(of: "/", with: "\\") }
        return "Z:" + path.replacingOccurrences(of: "/", with: "\\")
    }
}

/// The DLL overrides a mod needs for one game, kept as one `WINEDLLOVERRIDES+` entry ("dwrite,version=n,b"):
/// Wine's own copy of the library is skipped in favor of the one the mod put next to the game.
public enum ModDLLOverrides {
    public static let key = "WINEDLLOVERRIDES+"
    public static let presets = ["dwrite", "version", "winmm", "dinput8", "xinput1_3", "d3d9", "d3d11", "dxgi"]

    /// The library names in an environment's override entry.
    public static func names(in environment: [String: String]) -> [String] {
        guard let value = environment[key] else { return [] }
        return value.replacingOccurrences(of: "=n,b", with: "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func setting(_ names: [String], in environment: [String: String]) -> [String: String] {
        var env = environment
        let clean = Array(Set(names.map { $0.lowercased().replacingOccurrences(of: ".dll", with: "") })).sorted()
        env[key] = clean.isEmpty ? nil : clean.joined(separator: ",") + "=n,b"
        return env
    }

    public static func adding(_ name: String, to environment: [String: String]) -> [String: String] {
        setting(names(in: environment) + [name], in: environment)
    }

    public static func removing(_ name: String, from environment: [String: String]) -> [String: String] {
        let lower = name.lowercased()
        return setting(names(in: environment).filter { $0.lowercased() != lower }, in: environment)
    }
}

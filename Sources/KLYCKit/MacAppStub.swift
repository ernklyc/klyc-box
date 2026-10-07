import Foundation

/// "Make a Mac app": a real, tiny app bundle in ~/Applications/KLYC-Box named after the game,
/// with its cover as the icon, whose only job is to open one play URL and exit. Locally created,
/// ad-hoc signed with the system's codesign, so it has a stable identity and no quarantine flag.
/// Nothing touches the Dock's preferences: the person drags it there like any app (UX plan §3.9).
public enum MacAppStub {
    public static func folder() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/KLYC-Box", directoryHint: .isDirectory)
    }

    /// A file-system-safe app name from a title ("Portal 2" -> "Portal 2", "Half-Life: Alyx" -> "Half-Life Alyx").
    public static func appName(for title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "[/:\\\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "KLYC-Box game" : String(cleaned.prefix(60))
    }

    public static func infoPlist(appName: String, bundleID: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>launch</string>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundleName</key><string>\(appName)</string>
          <key>CFBundleDisplayName</key><string>\(appName)</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleShortVersionString</key><string>1.0</string>
          <key>CFBundleVersion</key><string>1</string>
          <key>CFBundleIconFile</key><string>icon</string>
          <key>LSMinimumSystemVersion</key><string>14.0</string>
          <key>LSUIElement</key><true/>
        </dict></plist>
        """
    }

    /// The launcher: opens the play URL and exits. `open` hands the URL to KLYC-Box whether it
    /// is running or not; `-g` keeps KLYC-Box in the background so the game, not the library,
    /// is what comes to the front (issue #53).
    public static func launchScript(url: URL) -> String {
        "#!/bin/sh\nexec /usr/bin/open -g \"\(url.absoluteString)\"\n"
    }

    public static func bundleID(for libraryID: String) -> String {
        let safe = libraryID.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return "com.klyc.klycbox.stub.\(safe)"
    }

    /// Writes (or rewrites) the bundle and returns its location. `cover` is any image file; it
    /// becomes the icon when sips and iconutil can convert it, and the stub still works without.
    @discardableResult
    /// The shortcut app for a title, if one was made.
    public static func existing(for title: String) -> URL? {
        let app = folder().appending(path: "\(appName(for: title)).app", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: app.path) ? app : nil
    }

    /// The Desktop, where the shortcut for a game is put on request.
    public static func desktop() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    /// The game's Mac app, copied onto the Desktop. A copy and not a Finder alias: an alias made
    /// from a bookmark carries no icon of its own and the Finder showed the generic application
    /// icon for it, while the app bundle carries the game's icon inside. The app is a script that
    /// opens one play URL, a few kilobytes, so a second copy costs nothing. An older copy, and an
    /// alias an earlier version left, are replaced.
    @discardableResult
    public static func copyToDesktop(_ app: URL, in desktop: URL = desktop()) throws -> URL {
        let fm = FileManager.default
        let target = desktop.appending(path: app.lastPathComponent, directoryHint: .isDirectory)
        try? fm.removeItem(at: target)
        // The alias the first version of this feature made had the app's name without ".app".
        let oldAlias = desktop.appending(path: app.deletingPathExtension().lastPathComponent)
        if (try? oldAlias.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true { try? fm.removeItem(at: oldAlias) }
        try fm.copyItem(at: app, to: target)
        // A new modification date makes the Finder read the icon again instead of keeping the one
        // it showed for an earlier file of the same name.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
        return target
    }

    /// The Desktop copy for a title, if one was put there.
    public static func existingDesktopCopy(for title: String, in desktop: URL = desktop()) -> URL? {
        let copy = desktop.appending(path: "\(appName(for: title)).app", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: copy.appending(path: "Contents/Info.plist").path) else { return nil }
        // Only ours: a stub carries the klycbox play-link launcher.
        let launcher = copy.appending(path: "Contents/MacOS/launch")
        guard let script = try? String(contentsOf: launcher, encoding: .utf8), script.contains("klycbox://") else { return nil }
        return copy
    }

    /// Moves the title's shortcut app to the Trash (issue #97). Nothing else references it.
    public static func remove(for title: String) throws {
        guard let app = existing(for: title) else { return }
        try FileManager.default.trashItem(at: app, resultingItemURL: nil)
    }

    public static func write(title: String, libraryID: String, url: URL, cover: URL?, icon: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let name = appName(for: title)
        let app = folder().appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try? fm.removeItem(at: app)
        try fm.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
        try infoPlist(appName: name, bundleID: bundleID(for: libraryID)).write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
        let script = contents.appending(path: "MacOS/launch")
        try launchScript(url: url).write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        // The program's own icon when it has one (item 8), else the cover cropped square.
        if let icon { try? makeIcon(from: icon, to: contents.appending(path: "Resources/icon.icns")) }
        else if let cover { try? makeIcon(from: cover, to: contents.appending(path: "Resources/icon.icns")) }
        // Ad-hoc signature: a stable identity for macOS, no certificate needed for a local file.
        _ = try? Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    /// The size that makes a picture just cover a square of `side`: its short side becomes `side`,
    /// the long one grows in proportion. Nil for a size that cannot be scaled.
    static func coverFitSize(width: Int, height: Int, side: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0, side > 0 else { return nil }
        let scale = Double(side) / Double(min(width, height))
        return (max(side, Int((Double(width) * scale).rounded())), max(side, Int((Double(height) * scale).rounded())))
    }

    /// `pixelWidth: 600` / `pixelHeight: 900` lines of `sips -g`.
    static func pixelSize(fromSips output: String) -> (width: Int, height: Int)? {
        func value(_ key: String) -> Int? {
            output.split(separator: "\n").compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 && parts[0] == key ? Int(parts[1]) : nil
            }.first
        }
        guard let w = value("pixelWidth"), let h = value("pixelHeight") else { return nil }
        return (w, h)
    }

    /// Cover to .icns through the system's own tools; a square crop at 512 and the standard set.
    static func makeIcon(from cover: URL, to icns: URL) throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "hb-icon-\(UUID().uuidString)")
        let iconset = work.appending(path: "icon.iconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let base = work.appending(path: "base.png")
        try Shell.run("/usr/bin/sips", ["-s", "format", "png", cover.path, "--out", base.path])
        // Fill the square, then crop from the centre. Scaling the long side to 1024 (what this did
        // first) leaves a tall cover narrower than the square, and the crop padded the rest with
        // black bars.
        let info = try Shell.capture("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", base.path])
        if let size = Self.pixelSize(fromSips: info), let fit = Self.coverFitSize(width: size.width, height: size.height, side: 1024) {
            try Shell.run("/usr/bin/sips", ["-z", String(fit.height), String(fit.width), base.path, "--out", base.path])
        }
        try Shell.run("/usr/bin/sips", ["-c", "1024", "1024", base.path, "--out", base.path])
        for (size, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                             (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
                             (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
            try Shell.run("/usr/bin/sips", ["-z", String(size), String(size), base.path, "--out", iconset.appending(path: "\(name).png").path])
        }
        try Shell.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path])
    }
}

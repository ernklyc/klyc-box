import AppKit
import Foundation
import KLYCKit

/// Games that live somewhere KLYC-Box was not told about (another launcher's library, a drive of installs): pick the folder, see what
/// is in it, and add it. Steam libraries become one more library folder of the app's Steam; plain game folders become programs.
extension AppState {
    func chooseGameFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.title = L("Add games from a folder")
        panel.message = L("Choose the folder that holds your games. KLYC-Box shows what it found before it adds anything.")
        panel.prompt = L("Scan")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addGameFolder(URL(fileURLWithPath: url.path, isDirectory: true))
    }

    func addGameFolder(_ folder: URL) {
        let scan = GameFolderScan.scan(folder)
        guard !scan.isEmpty else {
            errorMessage = L("No games were found in this folder.")
            return
        }
        var lines: [String] = []
        if !scan.steamGames.isEmpty { lines.append(L("Steam games (the folder becomes a library folder of the Steam in KLYC-Box):") + "\n  " + scan.steamGames.joined(separator: "\n  ")) }
        if !scan.programs.isEmpty { lines.append(L("Programs (added to your library):") + "\n  " + scan.programs.map(\.name).joined(separator: "\n  ")) }
        let alert = NSAlert()
        alert.messageText = L("Add these games?")
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: L("Add")); alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var notes: [String] = []
        if let library = scan.steamLibrary { notes.append(addSteamLibraryFolder(library)) }
        if !scan.programs.isEmpty, let bottle = defaultBottle {
            var copy = bottle
            var added = 0
            for program in scan.programs {
                let path = Pin.storagePath(for: program.executable, driveC: bottle.driveC)
                if copy.settings.pins.contains(where: { $0.path.lowercased() == path.lowercased() }) { continue }
                copy.settings.pins.append(Pin(name: program.name, path: path))
                added += 1
            }
            if added > 0 { update(copy) }
            notes.append(String(format: L("%d programs added to your library."), added))
        }
        refresh()
        let done = NSAlert()
        done.messageText = L("Done")
        done.informativeText = notes.joined(separator: "\n\n")
        done.runModal()
    }

    /// The Mac's own Steam keeps its games in these folders.
    private var macSteamLibraryRoots: [URL] { MacSteam.steamappsDirectories().map { $0.deletingLastPathComponent() } }

    func findSharedSteamFolders() -> [URL] {
        guard let bottle = steamBottle, let root = SteamLibrary.steamRoot(of: bottle),
              let text = try? String(contentsOf: root.appending(path: "steamapps/libraryfolders.vdf"), encoding: .utf8) else { return [] }
        let dos = bottle.url.appending(path: "dosdevices", directoryHint: .isDirectory)
        return SteamLibraryFolders.shared(vdf: text, driveC: bottle.driveC, dosdevices: dos, with: macSteamLibraryRoots)
    }

    /// Takes the shared folders out of the Steam in KLYC-Box's library list (the files in them are not touched). A copy of the list is
    /// kept beside it. Not while that Steam runs: it rewrites the list when it quits and would put them back.
    func separateSteamFromMacSteam() {
        guard let bottle = steamBottle, let root = SteamLibrary.steamRoot(of: bottle) else { return }
        if steamClients.contains(bottle.name) { steamStatusNote = L("Close Steam first (Stop it from the bar at the bottom), then separate the libraries."); return }
        let vdf = root.appending(path: "steamapps/libraryfolders.vdf")
        guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { return }
        let dos = bottle.url.appending(path: "dosdevices", directoryHint: .isDirectory)
        guard let cleaned = SteamLibraryFolders.removing(folders: sharedSteamFolders, from: text, driveC: bottle.driveC, dosdevices: dos) else { sharedSteamFolders = []; return }
        let backup = vdf.deletingLastPathComponent().appending(path: "libraryfolders.vdf.klycbox-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: vdf, to: backup)
        do { try cleaned.write(to: vdf, atomically: true, encoding: .utf8) } catch { return }
        steamStatusNote = L("Separated: the Steam in KLYC-Box no longer lists the Mac Steam's game folders.")
        refresh()
    }

    /// One more library folder in the bottle's Steam. The file is copied aside first, and nothing is written while Steam runs
    /// (it rewrites the file when it quits and would undo the change).
    private func addSteamLibraryFolder(_ library: URL) -> String {
        guard let bottle = steamBottle, let root = SteamLibrary.steamRoot(of: bottle) else {
            return L("Steam is not installed in KLYC-Box yet, so the Steam games were not added.")
        }
        if steamClients.contains(bottle.name) { return L("Close Steam first (Stop it from the bar at the bottom), then add the folder again: Steam would overwrite the change.") }
        // A folder the Mac's own Steam uses would then be updated by two Steams at once: refused.
        if macSteamLibraryRoots.contains(where: { $0.standardizedFileURL.path.lowercased() == library.standardizedFileURL.path.lowercased() }) {
            return L("That folder is a library of the Mac's own Steam. Two Steams on one folder both try to update its games, so it was not added.")
        }
        let vdf = root.appending(path: "steamapps/libraryfolders.vdf")
        guard let text = try? String(contentsOf: vdf, encoding: .utf8) else { return L("Steam's library list could not be read; nothing was changed.") }
        guard let updated = SteamLibraryFolders.adding(folder: library, games: GameFolderScan.steamAppSizes(in: library), to: text) else {
            return L("That folder is already one of Steam's library folders.")
        }
        let backup = vdf.deletingLastPathComponent().appending(path: "libraryfolders.vdf.klycbox-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: vdf, to: backup)
        do { try updated.write(to: vdf, atomically: true, encoding: .utf8) } catch { return L("Steam's library list could not be written; nothing was changed.") }
        return L("The folder is now a Steam library folder. Open Steam once: it checks the games and lists them. (A copy of the old list is next to the file: libraryfolders.vdf.klycbox-backup.)")
    }
}

import Foundation
import KLYCKit

/// Save-file backups for one game: where its saves seem to be, backing them up, putting a backup back.
extension AppState {
    func saveBackupDirectory(for item: LibraryItem) -> URL {
        let safe = item.id.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        return paths.home.appending(path: "save-backups/\(safe)", directoryHint: .isDirectory)
    }

    /// What the save search needs, gathered on the main actor so the search itself can run off it.
    func saveSearch(for item: LibraryItem) -> (driveC: URL, steamAppID: Int?, names: [String])? {
        guard let bottle = modBottle(for: item) else { return nil }
        var names = [item.title, displayTitle(item)]
        if let appid = item.steamAppID, let dir = gamesByBottle[bottle.name]?.first(where: { $0.appid == appid })?.installdir { names.append(dir) }
        return (bottle.driveC, item.steamAppID, names)
    }

    /// Reads the disk: never call it from a view body (it walks the environment's user folders; on a slow disk that froze the window).
    func saveFolders(for item: LibraryItem) -> [SaveLocator.Candidate] {
        guard let q = saveSearch(for: item) else { return [] }
        return SaveLocator.candidates(driveC: q.driveC, steamAppID: q.steamAppID, names: q.names)
    }

    func saveBackups(for item: LibraryItem) -> [SaveBackup.Entry] { SaveBackup.list(in: saveBackupDirectory(for: item)) }

    /// A sentence for the panel; a failure is the sentence.
    func backUpSaves(for item: LibraryItem) -> String {
        guard let bottle = modBottle(for: item) else { return L("The game's environment was not found.") }
        let folders = saveFolders(for: item).map(\.url)
        do {
            try SaveBackup.create(folders: folders, driveC: bottle.driveC, into: saveBackupDirectory(for: item))
            appendLog("\(item.title): saves backed up (\(folders.count) folders)")
            notify(L("Saves backed up."))
            return L("Saves backed up.")
        } catch SaveBackup.Failure.nothingToBackUp {
            return L("No save folders were found for this game yet. Play it once, then try again.")
        } catch {
            notify(L("The backup failed."), style: .warning)
            return String(format: L("Backup failed: %@"), error.localizedDescription)
        }
    }

    func restoreSaves(_ backup: SaveBackup.Entry, for item: LibraryItem) -> String {
        guard let bottle = modBottle(for: item) else { return L("The game's environment was not found.") }
        do {
            try SaveBackup.restore(backup.url, driveC: bottle.driveC, currentFolders: saveFolders(for: item).map(\.url),
                                   safetyDirectory: saveBackupDirectory(for: item).appending(path: "before-restore", directoryHint: .isDirectory))
            appendLog("\(item.title): saves restored from \(backup.url.lastPathComponent)")
            notify(L("Saves restored."))
            return L("Saves restored. What was there before was kept in the backup folder.")
        } catch {
            notify(L("The restore failed."), style: .warning)
            return String(format: L("Restore failed: %@"), error.localizedDescription)
        }
    }

    func deleteSaveBackup(_ backup: SaveBackup.Entry) {
        do { try FileManager.default.removeItem(at: backup.url); notify(L("Backup deleted."), style: .info) }
        catch { notify(L("The backup could not be deleted."), style: .warning) }
    }
}

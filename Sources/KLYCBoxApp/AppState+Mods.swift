import AppKit
import KLYCKit

/// Modding a game: files into its folder (with a backup), the mod DLL overrides it needs, mod tools run in
/// its environment. The file work lives in KLYCKit (`ModInstaller`); this is only the glue to the app.
extension AppState {
    static let modCatalog = ModCatalog.load()

    func modEntry(for item: LibraryItem) -> ModCatalog.Entry? { Self.modCatalog.entry(for: item.id) }

    func modBottle(for item: LibraryItem) -> Bottle? {
        item.bottleName.flatMap { name in bottles.first { $0.name == name } }
    }

    /// The game folder as the Windows path a mod tool asks for.
    func windowsPath(for item: LibraryItem) -> String? {
        guard let folder = programFolder(for: item), let bottle = modBottle(for: item) else { return nil }
        return WindowsPath.string(for: folder, driveC: bottle.driveC)
    }

    // MARK: components a game needs

    /// The Windows components the game's recipe lists that this environment does not have yet (.NET, runtimes).
    /// The recipe's own list comes first, then what the executable's imports add (`derivedComponents`).
    func missingComponents(for item: LibraryItem) -> [KLYCKit.Recipe] {
        guard let bottle = modBottle(for: item) else { return [] }
        var required = fixRecipe(for: item)?.requires ?? []
        for id in derivedComponents[item.id] ?? [] where !required.contains(id) { required.append(id) }
        let tweaks = Self.tweakRecipes()
        return required.compactMap { id in tweaks.first { $0.id == id } }
            .filter { !bottle.settings.recipes.contains($0.id) && !tweakIsInstalled($0, in: bottle) }
    }

    /// Reads the game's executable for the components it links against. Once per game: the answer
    /// changes only when the game is updated, and a launch of this page asks again.
    func refreshDerivedComponents(for item: LibraryItem) async {
        guard item.installed, let exe = programExecutable(for: item) else { return }
        let ids = await Task.detached(priority: .utility) { ProgramNeeds.windowsComponents(program: exe) }.value
        if derivedComponents[item.id] != ids { derivedComponents[item.id] = ids }
    }

    // MARK: shader cache

    /// The Steam shader cache folders of a game, empty for anything that is not an installed Steam game.
    func shaderCacheFolders(for item: LibraryItem) -> [URL] {
        guard item.source == .steam, let appid = item.steamAppID, let bottle = modBottle(for: item) else { return [] }
        return ShaderCache.folders(appid: appid, steamapps: SteamLibrary.steamappsFolders(of: bottle))
    }

    // MARK: files

    func planMods(_ sources: [URL], for item: LibraryItem, subfolder: String?) throws -> ModInstaller.Plan {
        guard let folder = programFolder(for: item) else { throw ModInstaller.Failure.outsideGameFolder }
        return try ModInstaller.plan(sources: sources, into: folder, subfolder: subfolder)
    }

    /// Returns a sentence for the panel. Never throws: a failure is the sentence.
    func installMods(_ plan: ModInstaller.Plan, for item: LibraryItem, overwrite: Bool) -> String {
        guard let folder = programFolder(for: item) else { return L("The game's folder was not found.") }
        do {
            let result = try ModInstaller.install(plan, into: folder, overwrite: overwrite)
            appendLog("\(item.title): mod files added \(result.added.count), replaced \(result.replaced.count), skipped \(result.skipped.count)")
            var parts = [String(format: L("%d files added"), result.added.count)]
            if !result.replaced.isEmpty { parts.append(String(format: L("%d replaced (backed up)"), result.replaced.count)) }
            if !result.skipped.isEmpty { parts.append(String(format: L("%d skipped"), result.skipped.count)) }
            return parts.joined(separator: " · ")
        } catch {
            return String(format: L("Could not add the files: %@"), error.localizedDescription)
        }
    }

    func lastModInstall(for item: LibraryItem) -> ModInstaller.Record? {
        programFolder(for: item).flatMap { ModInstaller.lastRecord(in: $0) }
    }

    func undoMods(for item: LibraryItem) -> String {
        guard let folder = programFolder(for: item) else { return L("The game's folder was not found.") }
        do {
            let n = try ModInstaller.undoLast(in: folder)
            return String(format: L("Undone: %d files"), n)
        } catch {
            return String(format: L("Could not undo: %@"), error.localizedDescription)
        }
    }

    // MARK: mod DLL overrides, kept per game

    func modDLLs(for item: LibraryItem) -> [String] {
        ModDLLOverrides.names(in: modBottle(for: item)?.settings.gameEnvironment[item.id] ?? [:])
    }

    func setModDLLs(_ names: [String], for item: LibraryItem) {
        guard var bottle = modBottle(for: item) else { return }
        let env = ModDLLOverrides.setting(names, in: bottle.settings.gameEnvironment[item.id] ?? [:])
        bottle.settings.gameEnvironment[item.id] = env.isEmpty ? nil : env
        update(bottle)
        notify(L("DLL overrides saved. Stop the environment's processes and start the game again to apply them."))
    }

    /// Programs a mod tool is likely to be: the executables near the top of the game's folder.
    func toolsInGameFolder(_ item: LibraryItem) -> [URL] {
        guard let folder = programFolder(for: item) else { return [] }
        let skip = ["unins", "crash", "dxsetup", "vcredist", "redist", "dotnet", "oalinst", "setup"]
        var found: [URL] = []
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                for inner in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] where inner.pathExtension.lowercased() == "exe" { found.append(inner) }
            } else if url.pathExtension.lowercased() == "exe" { found.append(url) }
        }
        return found.filter { f in !skip.contains { f.lastPathComponent.lowercased().contains($0) } }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }.prefix(40).map { $0 }
    }
}

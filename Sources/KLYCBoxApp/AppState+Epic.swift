import AppKit
import Foundation
import KLYCKit
import SwiftUI

/// Epic: playing and installing through Legendary. Split out of AppState.swift; it holds no stored state of its own.
extension AppState {

    var epicStore: EpicStore { EpicStore(paths: paths) }

    func epicRefresh() {
        epicSignedIn = epicStore.isAuthenticated
        guard epicSignedIn else { epicOwned = []; epicInstalls = [:]; return }
        // Unfinished installs first, from what is on disk: the library list below takes a network
        // round trip, and until then a paused download would look as if it did not exist.
        restoreEpicDownloads()
        guard !epicFetchInFlight else { return }
        epicFetchInFlight = true
        epicLoading = epicOwned.isEmpty
        Task.detached { [store = epicStore] in
            let owned = (try? store.ownedGames()) ?? []
            let installed = (try? store.installedGames()) ?? []
            await MainActor.run { [weak self] in
                self?.epicOwned = owned.sorted { $0.app_title < $1.app_title }
                self?.epicInstalls = EpicStore.installMap(installed)
                self?.epicLoading = false
                self?.epicFetchInFlight = false
                self?.rebuildLibrary()   // Epic results arrive after refresh(); fold them in
                self?.epicDownloads.discard(installed: Set(EpicStore.installMap(installed).keys))
                self?.restoreEpicDownloads()
            }
        }
    }

    /// Installed *in this bottle* — a game legendary installed into another bottle's
    /// drive_c is not playable here.
    func epicInstalled(_ appName: String, in bottle: Bottle) -> Bool {
        guard let path = epicInstalls[appName] else { return false }
        return EpicStore.isInstalled(path: path, inDriveC: bottle.driveC)
    }

    func epicSignIn(code: String) {
        runBusy(L("Connecting your Epic account"), stop: .cancelTask(label: L("Stop"))) { [self] in
            let store = epicStore
            _ = try await store.ensureInstalled()
            try await Task.detached { try store.authenticate(code: code) }.value
            await MainActor.run { self.epicRefresh() }
        }
    }

    /// Starts an Epic install as a download the app can show, pause and resume: not a busy
    /// operation, so the rest of the app stays usable during a download that takes an hour.
    func epicInstall(_ game: EpicStore.Game, in bottle: Bottle) {
        wireEpicDownloads()
        // A copy of this install left running by an earlier run of the app (it was quit or restarted
        // mid-download) would write to the same files as a second one: it is stopped first.
        if stopLeftoverEpicInstalls(of: game.app_name, then: { [weak self] in self?.epicInstall(game, in: bottle) }) { return }
        let store = epicStore
        do {
            // Asking for it again is the person changing their mind about a cancel.
            var file = EpicDownloadStore.load(from: epicDownloadsFile)
            if file.dismissed.contains(game.app_name) { file.dismissed.removeAll { $0 == game.app_name }; EpicDownloadStore.save(file, to: epicDownloadsFile) }
            try epicDownloads.start(appName: game.app_name, title: game.app_title, bottleName: bottle.name) { name, onLine, onExit in
                try store.startInstall(name, into: bottle, onLine: onLine, onExit: onExit)
            }
            notify(String(format: L("Downloading %@. Follow it, pause it or cancel it under Downloads."), game.app_title), style: .info)
        } catch { fail(error) }
    }

    /// What happens when an install ends or prints something; set once.
    private func wireEpicDownloads() {
        guard !epicDownloadsWired else { return }
        epicDownloadsWired = true
        epicDownloads.onLog = { [weak self] line in self?.appendLog(line) }
        epicDownloads.onPersist = { [weak self] saved in
            guard let self else { return }
            var file = EpicDownloadStore.load(from: self.epicDownloadsFile)
            file.downloads = saved
            EpicDownloadStore.save(file, to: self.epicDownloadsFile)
        }
        epicDownloads.onCancelled = { [weak self] appName in
            guard let self else { return }
            var file = EpicDownloadStore.load(from: self.epicDownloadsFile)
            if !file.dismissed.contains(appName) { file.dismissed.append(appName) }
            EpicDownloadStore.save(file, to: self.epicDownloadsFile)
        }
        epicDownloads.onFinished = { [weak self] appName, title, succeeded in
            guard let self else { return }
            if succeeded {
                // Status 0 is Legendary saying it is done, not proof the game is installed: look.
                let store = self.epicStore
                Task {
                    let installed = (try? await Task.detached { try store.installedGames() }.value) ?? []
                    if EpicStore.installMap(installed)[appName] != nil {
                        self.epicRefresh()
                        self.notify(String(format: L("%@ is installed."), title))
                    } else {
                        self.epicDownloads.reinstate(appName)
                        self.notify(String(format: L("Legendary ended, but %@ is not installed yet. Resume to continue."), title), style: .warning)
                    }
                }
            } else {
                self.notify(String(format: L("The download of %@ stopped. See Downloads."), title), style: .warning)
            }
        }
        // Quitting while a download runs: tell it to save its place, so it continues next time.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.epicDownloads.pauseAll() }
        }
        // The same when the app is ended with a signal (`kill`, `pkill`, a script that quits it,
        // the terminal's Ctrl-C): that does not run the notification above, and the download
        // would go on with nobody holding it, then collide with a new run of the same install.
        for sig in [SIGTERM, SIGHUP, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.epicDownloads.pauseAll() }
                // Legendary saves its place in its own time; the app does not wait for it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
            }
            source.resume()
            epicSignalSources.append(source)
        }
    }

    var epicDownloadsFile: URL { paths.home.appending(path: "epic-downloads.json") }

    /// Brings back installs an earlier run left unfinished, as paused downloads, so they are on the
    /// Downloads page without anyone starting them again. Legendary keeps `<app>.resume` for each.
    func restoreEpicDownloads() {
        wireEpicDownloads()
        let file = EpicDownloadStore.load(from: epicDownloadsFile)
        let resumable = EpicDownloadStore.resumableApps(in: paths.home.appending(path: "legendary/tmp", directoryHint: .isDirectory))
        // The library list when it is here; Legendary's own catalog copy on disk when it is not yet.
        var titles = Dictionary(epicOwned.map { ($0.app_name, $0.app_title) }, uniquingKeysWith: { a, _ in a })
        let metadata = paths.home.appending(path: "legendary/metadata", directoryHint: .isDirectory)
        for app in resumable where titles[app] == nil {
            if let title = EpicDownloadStore.title(forApp: app, metadata: metadata) { titles[app] = title }
        }
        let pending = EpicDownloadStore.pending(file: file, resumable: resumable, installed: Set(epicInstalls.keys), titles: titles)
        // A download an earlier run left going with nobody holding it is asked to stop at once, so
        // that no two runs of one install ever write to the same files. It saves its place and
        // the download then shows as paused, ready to resume.
        for app in resumable { releaseLeftoverEpicInstalls(of: app) }
        guard !pending.isEmpty else { return }
        let store = epicStore
        epicDownloads.restore(pending) { [weak self] saved in
            // Back into the environment it was going to, or the default one.
            let bottle = self?.bottles.first { $0.name == saved.bottleName } ?? self?.defaultBottle
            return { name, onLine, onExit in
                guard let bottle else { throw KLYCError.failed("There is no environment to install \(saved.title) into.") }
                return try store.startInstall(name, into: bottle, onLine: onLine, onExit: onExit)
            }
        }
    }

    /// Asks any run of this install that this app did not start to stop, and ends it the plain way
    /// if it has not after a while. Once per app run per game.
    private func releaseLeftoverEpicInstalls(of appName: String) {
        guard !epicReleased.contains(appName) else { return }
        epicReleased.insert(appName)
        let leftovers = epicStore.runningInstalls(appName: appName).filter { $0.parent != getpid() }.map(\.pid)
        guard !leftovers.isEmpty else { return }
        appendLog("[epic] an earlier download of \(appName) is still running in the background; asking it to stop")
        for pid in leftovers { kill(pid, SIGINT) }
        Task {
            try? await Task.sleep(for: .seconds(150))
            for pid in leftovers where kill(pid, 0) == 0 { kill(pid, SIGTERM) }
        }
    }

    func epicResume(_ appName: String) {
        wireEpicDownloads()
        if stopLeftoverEpicInstalls(of: appName, then: { [weak self] in self?.epicResume(appName) }) { return }
        do { try epicDownloads.resume(appName) } catch { fail(error) }
    }

    /// Installs of this game that this app did not start, left over from before a restart. Two
    /// Legendary runs on one game write to the same files, so any such one is asked to stop (it
    /// saves its place, which can take a minute or two), and `then` runs once it is gone. Returns
    /// true when there was one and the caller should wait for `then`.
    private func stopLeftoverEpicInstalls(of appName: String, then proceed: @escaping @MainActor () -> Void) -> Bool {
        let leftovers = epicStore.runningInstalls(appName: appName).filter { $0.parent != getpid() }.map(\.pid)
        guard !leftovers.isEmpty else { return false }
        guard !epicStopping.contains(appName) else {
            notify(L("The earlier download is still saving its place. It continues by itself in a moment."), style: .info)
            return true
        }
        epicStopping.insert(appName)
        notify(L("An earlier download of this game is still running in the background. Stopping it first; this continues by itself in a minute or two."), style: .info)
        for pid in leftovers { kill(pid, SIGINT) }
        Task { [weak self] in
            // A run whose app is gone has nobody reading its output; it may not answer the polite
            // request, so after a while it is ended the plain way (Legendary resumes after that too).
            var waited = 0
            while waited < 240 {
                try? await Task.sleep(for: .seconds(2)); waited += 2
                let alive = leftovers.filter { kill($0, 0) == 0 }
                if alive.isEmpty { break }
                if waited == 150 { for pid in alive { kill(pid, SIGTERM) } }
            }
            guard let self else { return }
            self.epicStopping.remove(appName)
            if self.epicStore.runningInstalls(appName: appName).filter({ $0.parent != getpid() }).isEmpty { proceed() }
            else { self.notify(L("The earlier download did not stop. Quit it in Activity Monitor (legendary), then try again."), style: .warning) }
        }
        return true
    }

    // renderer nil = the bottle's own renderer (the old hardcoded .dxvk default ignored it).
    func epicPlay(_ game: EpicStore.Game, in bottle: Bottle, renderer: Renderer? = nil) {
        guard let engine = engine(for: bottle) else { return }
        if runningSessions.contains(where: { $0.title == game.app_title && $0.bottleName == bottle.name }) {
            fail(KLYCError.failed("\(game.app_title) is already running."))
            return
        }
        runBusy("Starting \(game.app_title)", done: .handedOff, stop: .killBottle(bottle, label: L("Stop"))) { [self] in
            let store = epicStore
            // Fresh single-use token, fetched off the main thread right before launch.
            let info = try await Task.detached { try store.launchInfo(game.app_name) }.value
            let runner = WineRunner(paths: paths, engine: engine, bottle: bottle)
            let box = LaunchOutcome()
            let log = logLine(box)
            let executable = info.executable
            var arguments = info.arguments
            // The variables this game's recipe scoped to it, on top of Legendary's.
            let gameEnvironment = bottle.settings.environment(forGames: [gameDB.byEpicAppName[game.app_name]?.id, "epic:\(game.app_name)"])
            // What the user typed for this game goes last.
            arguments += PlaytimeText.arguments(from: launchArguments["epic:\(game.app_name)"] ?? "")
            watchedLaunch(box) {
                try await runner.start(executable, arguments: arguments,
                                       renderer: renderer, extraEnvironment: info.environment.merging(gameEnvironment) { _, new in new },
                                       workingDirectory: info.workingDirectory, onOutput: log)
            }
            let markers = SessionWatch.markers(executable: info.executable)
            let handedOff = try await awaitHandoff(box, program: game.app_title, timeout: 360) {
                SessionWatch.isAlive(markers: markers, ps: await Self.processList())
            } crashed: { result in
                let current = renderer ?? bottle.settings.renderer
                self.presentCrash(CrashSuggestion(program: game.app_title, bottleName: bottle.name,
                                                       renderer: Renderer.suggestion(after: current, d3dmetalAvailable: engine.rendererDir("d3dmetal") != nil, vkd3dAvailable: engine.rendererDir("vkd3d") != nil),
                                                       logPath: result.log.path, current: current, seconds: Int(result.duration),
                                                       alternateEngine: self.alternateEngine(for: bottle)))
            }
            guard handedOff else { return }
            beginSession(GameSession(title: game.app_title, bottleName: bottle.name, appid: nil, markers: markers,
                                     renderer: (renderer ?? bottle.settings.renderer).rawValue))
        }
    }

    func setDpi(_ scale: Int, retinaAt100: Bool? = nil, in bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        var copy = bottle
        copy.settings.dpiScale = scale
        if let retinaAt100 { copy.settings.retinaAt100 = retinaAt100 }
        update(copy)
        let retina = copy.settings.retinaAt100
        runBusy("Applying display scaling", showLogSheet: false) { [self] in
            try await WineRunner(paths: paths, engine: engine, bottle: copy).setDpi(logPixels: scale, retinaAt100: retina)
        }
    }

    func killBottle(_ bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        _ = try? WineRunner(paths: paths, engine: engine, bottle: bottle).kill()
    }

    /// True while any Wine process from any bottle is alive. Every Wine process (wineserver,
    /// preloaders, services) runs from the engines directory, so its path in `ps` is the marker.
    func wineProcessesRunning() -> Bool {
        guard let ps = try? Shell.capture("/bin/ps", ["axww"]) else { return false }
        return ps.contains(paths.engines.path)
    }

    /// Stop every bottle's wineserver (and with it all Windows processes).
    func killAllBottles() {
        for bottle in bottles { killBottle(bottle) }
    }

    func loadGPTKLicense() {
        for candidate in [Self.repoRoot?.appending(path: "spike/d3dmetal-license.txt"),
                          Bundle.main.url(forResource: "d3dmetal-license", withExtension: "txt")].compactMap({ $0 }) {
            if let text = try? String(contentsOf: candidate, encoding: .utf8) { gptkLicenseText = text; return }
        }
        gptkLicenseText = "License text unavailable locally. Read it at github.com/Gcenx/game-porting-toolkit (License.pdf) before accepting."
    }
}

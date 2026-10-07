import KLYCKit

/// Favorites and "Improve" (try the graphics modes one game can use, keep the one that works on this Mac).
extension AppState {
    // MARK: Improve (find the graphics mode that works best for one game, on this Mac)

    func loadTuning() { tuning = TuningStore(paths: paths).all() }

    func clearTuning() {
        for id in tuning.keys { TuningStore(paths: paths).remove(id) }
        loadTuning()
    }

    // MARK: Favorites
    func isFavorite(_ item: LibraryItem) -> Bool { favorites.contains(item.id) }
    func toggleFavorite(_ item: LibraryItem) {
        let on = !favorites.contains(item.id)
        libraryStore.setFavorite(on, for: item.id)
        favorites = libraryStore.favorites()
        UISound.play(on ? .select : .back)
    }

    /// An installed Steam or Epic game that is not blocked and not running: the kinds this can test.
    func canImprove(_ item: LibraryItem) -> Bool {
        guard item.installed, !busy, gameDB.entry(for: item)?.isBlocked != true, gameDB.entry(for: item)?.nativeVulkan != true else { return false }
        switch item.source {
        case .steam: return item.steamAppID.map { session(forAppID: $0) == nil } ?? false
        case .epic: return item.epicAppName.map { epicInstalls[$0] != nil } ?? false
        case .pin: return false
        }
    }

    func improve(_ item: LibraryItem) {
        guard canImprove(item), let name = item.bottleName,
              let bottle = bottles.first(where: { $0.name == name }), let engine = engine(for: bottle) else { return }
        guard runningSessions.isEmpty else { fail(KLYCError.failed(L("Close the running games first."))); return }
        let entry = gameDB.entry(for: item)
        // The row's own mode goes first, then DXMT (the default), DXVK, and Apple's DirectX 12 when its licence is accepted.
        var order: [Renderer] = []
        if let wanted = entry?.effectiveRenderer() { order.append(wanted) }
        for r in [Renderer.dxmt, .dxvk, .d3dmetal] where !order.contains(r) { order.append(r) }
        let candidates = order.filter { $0.availability(in: engine) == .available }
        guard !candidates.isEmpty else { return }
        let gameEnvironment = bottle.settings.environment(forGames: [entry?.id, item.id])
        let userArguments = PlaytimeText.arguments(from: launchArguments[item.id] ?? "")
        let steamGame = item.steamAppID.flatMap { id in gamesByBottle[name]?.first { $0.appid == id } }
        let epicName = item.epicAppName
        let store = epicStore
        runBusy(String(format: L("Improving %@"), displayTitle(item)), expected: L("about 2 to 4 minutes per graphics mode"),
                stop: .killBottle(bottle, label: L("Stop"))) { [self] in
            var attempts: [TuningResult.Attempt] = []
            let verifier = Verifier(paths: paths, engine: engine, bottle: bottle)
            let log: @Sendable (String) -> Void = { line in Task { @MainActor in self.appendLog(line) } }
            // Epic: the launch token is single use, so each try asks for a fresh one; the game's process markers
            // come from a first look at the launch parameters.
            var epicMarkers: [String] = []
            if let epicName {
                let info = try await Task.detached { try store.launchInfo(epicName) }.value
                epicMarkers = SessionWatch.markers(executable: info.executable)
            }
            for (i, renderer) in candidates.enumerated() {
                stage = String(format: L("Trying %@ (%d of %d)"), GamePageCopy.plainName(renderer), i + 1, candidates.count)
                let outcome: VerifyOutcome
                if let game = steamGame {
                    outcome = try await verifier.run(game: game, renderer: renderer, runSeconds: 60, gameEnvironment: gameEnvironment, log: log)
                } else if let epicName {
                    let runner = WineRunner(paths: paths, engine: engine, bottle: bottle)
                    outcome = try await verifier.run(title: item.title, markers: epicMarkers, renderer: renderer, runSeconds: 60, log: log) { renderer, logEnvironment in
                        let info = try await Task.detached { try store.launchInfo(epicName) }.value
                        try await runner.start(info.executable, arguments: info.arguments + userArguments, renderer: renderer,
                                               extraEnvironment: info.environment.merging(gameEnvironment) { _, new in new }.merging(logEnvironment) { _, new in new },
                                               workingDirectory: info.workingDirectory)
                    }
                } else { break }
                attempts.append(.init(renderer: renderer, verdict: outcome.verdict, secondsAlive: outcome.secondsAlive))
                if outcome.verdict == .renders { break }   // the first mode that draws and stays up is the pick; no need to spend minutes on the rest
            }
            let result = TuningResult(best: TuningResult.pick(attempts), attempts: attempts, engine: engine.id)
            TuningStore(paths: paths).save(result, for: item.id)
            loadTuning()
            if let best = result.best { setRendererOverride(best, for: item.id) }
        }
    }
}

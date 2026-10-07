import AppKit
import KLYCKit

/// "Verified on your Mac": the player's own answer after a game, kept here and shown in place of other people's data.
extension AppState {
    /// The library id of a finished session: by Steam id when there is one, else by title in the same environment.
    func libraryID(forAppID appid: Int?, title: String, bottle: String) -> String? {
        appid.map { "steam:\($0)" } ?? libraryItems.first { $0.title == title && $0.bottleName == bottle }?.id
    }

    func recordVerdict(for item: LibraryItem, works: Bool, fps: Int?, renderer: String? = nil, minutes: Int? = nil, auto: Bool = false, fpsMeasured: Bool = false) {
        let bottle = modBottle(for: item)
        let mode = renderer ?? rendererOverride(for: item)?.rawValue ?? gameDB.entry(for: item)?.effectiveRenderer()?.rawValue ?? bottle?.settings.renderer.rawValue
        let verdict = LocalVerdict(works: works, fps: fps, renderer: mode, engine: bottle?.settings.engineID ?? "?",
                                   chip: Machine.chip(), macos: Machine.macOSVersion(), minutes: minutes, title: item.title, auto: auto ? true : nil, fpsMeasured: fpsMeasured && fps != nil ? true : nil)
        LocalVerdictStore(paths: paths).set(verdict, for: item.id)
        localVerdicts = LocalVerdictStore(paths: paths).all()
        appendLog("\(item.title): marked \(works ? "works" : "has problems") on this Mac\(fps.map { ", \($0) fps" } ?? "")")
        if !auto { notify(L("Your result was saved on this Mac.")) }
    }

    /// From the "How did it go?" row after a session.
    func recordVerdict(from record: SessionRecord, works: Bool, fps: Int?) {
        guard let id = libraryID(forAppID: record.appid, title: record.title, bottle: record.bottle),
              let item = libraryItems.first(where: { $0.id == id }) else { return }
        recordVerdict(for: item, works: works, fps: fps, renderer: record.renderer, minutes: record.seconds / 60)
        postPlay = nil
    }

    /// A long, normal session is the answer: no question, nothing typed. Returns true when it settled the matter.
    @discardableResult
    func autoVerdict(for record: SessionRecord, measured: HUDLog.Summary? = nil) -> Bool {
        guard AutoVerdict.works(reason: record.reason, seconds: record.seconds),
              let id = libraryID(forAppID: record.appid, title: record.title, bottle: record.bottle),
              let item = libraryItems.first(where: { $0.id == id }),
              AutoVerdict.mayReplace(existing: localVerdicts[id]) else { return false }
        // The player's own frame rate, if they gave one earlier, is kept.
        let fps = measured?.median ?? localVerdicts[id]?.fps
        recordVerdict(for: item, works: true, fps: fps, renderer: record.renderer, minutes: record.seconds / 60, auto: true,
                      fpsMeasured: measured != nil || localVerdicts[id]?.fpsMeasured == true)
        return true
    }

    /// The frame rate of a finished session, read from the Metal HUD log of its launch (only when the HUD was on for the game).
    func measuredFPS(for session: GameSession) -> HUDLog.Summary? {
        guard let id = libraryID(forAppID: session.appid, title: session.title, bottle: session.bottleName),
              let item = libraryItems.first(where: { $0.id == id }), metalHUD(for: item), let log = lastLaunchLog(for: item) else { return nil }
        return HUDLog.summary(in: HUDLog.tail(of: log), from: session.started, to: Date())
    }

    /// A measured frame rate goes onto the game's existing verdict, whoever made it; it never creates or flips one.
    func applyMeasuredFPS(_ measured: HUDLog.Summary, for record: SessionRecord) {
        guard let id = libraryID(forAppID: record.appid, title: record.title, bottle: record.bottle),
              var v = localVerdicts[id], v.works else { return }
        v.fps = measured.median; v.fpsMeasured = true
        LocalVerdictStore(paths: paths).set(v, for: id)
        localVerdicts = LocalVerdictStore(paths: paths).all()
    }

    func removeVerdict(for item: LibraryItem) {
        LocalVerdictStore(paths: paths).set(nil, for: item.id)
        localVerdicts = LocalVerdictStore(paths: paths).all()
        notify(L("Your result was removed."), style: .info)
    }

    /// The pill for a game: the player's own answer first, then what the compatibility data says.
    func statusKind(for item: LibraryItem) -> StatusPill.Kind {
        if let local = localVerdicts[item.id] { return local.works ? .ready : .problems }
        return StatusPill.kind(forStatus: gameDB.entry(for: item)?.status)
    }

    /// Opens the project's report form with this Mac's result filled in. Nothing is sent: the player presses Create.
    func shareVerdict(for item: LibraryItem) {
        guard let v = localVerdicts[item.id] else { return }
        let bottle = modBottle(for: item)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let settings = bottle.map { PlayReport.settingsSummary($0.settings) }
        NSWorkspace.shared.open(PlayReport.url(title: item.title, appid: item.steamAppID, renderer: v.renderer, chip: v.chip, macos: v.macos,
                                               engine: v.engine, minutes: v.minutes ?? 0, version: version, settings: settings,
                                               works: v.works, fps: v.fps))
    }
}

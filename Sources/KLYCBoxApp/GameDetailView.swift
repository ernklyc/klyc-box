import SwiftUI
import KLYCKit

/// A game's page (UX plan §3.5): a verdict written as a sentence, Play as the only button, an
/// honest list of what Play will do, and every identifier behind one Advanced triangle.
struct GameDetailView: View {
    @Environment(AppState.self) private var state
    let passedItem: LibraryItem
    @State private var showBottleSettings = false
    @State private var coverDropTargeted = false
    /// The live row: after an install, a delete or a rename, the passed-in copy goes stale.
    private var item: LibraryItem { state.libraryItems.first { $0.id == passedItem.id } ?? passedItem }
    @State private var showWhy = false
    @State private var showAdvanced = false
    // KLYC_SHOW_PLAN=1 opens the plan from the start (handy for screenshots).
    @State private var showPlan = ProcessInfo.processInfo.environment["KLYC_SHOW_PLAN"] != nil
    @State private var fpsEntry = ""
    @State private var communityDraft: CommunityVote?
    /// Read from the game's executable when the plan is opened, off the main thread.
    @State private var profile: ProgramProfile?

    private var entry: GameDBEntry? { state.gameDB.entry(for: item) }
    private var bottle: Bottle? { item.bottleName.flatMap { name in state.bottles.first { $0.name == name } } }
    private var blocked: Bool { entry?.isBlocked == true }
    /// Steam already has an appmanifest for it (downloading or updating), as opposed to a game
    /// that is only owned.
    private var steamHasManifest: Bool {
        guard let name = item.bottleName, let appid = item.steamAppID else { return false }
        return state.gamesByBottle[name]?.contains { $0.appid == appid } == true
    }
    private var fixRecipe: KLYCKit.Recipe? { state.fixRecipe(for: item) }
    private var fixApplied: Bool {
        guard let fixRecipe, let bottle else { return false }
        return bottle.settings.recipes.contains(fixRecipe.id) && fixRecipe.artifactsPresent(driveC: bottle.driveC)
    }
    private var running: GameSession? {
        if let appid = item.steamAppID, let s = state.session(forAppID: appid) { return s }
        return state.runningSessions.first { $0.title == item.title && $0.bottleName == item.bottleName }
    }
    private var verdict: GamePageCopy.Verdict { GamePageCopy.verdict(entry, myChip: state.machineChip) }
    private var willDo: [GamePageCopy.WillDo] {
        GamePageCopy.willDo(entry, recipe: fixRecipe, applied: fixApplied, bottleRenderer: bottle?.settings.renderer ?? .dxvk,
                            explicit: bottle?.settings.rendererExplicit ?? false, gameOverride: state.rendererOverride(for: item))
    }
    private var engineName: String? { bottle.flatMap { state.engine(for: $0) }?.displayName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                infoCards
                anticheatCard
                atlasCard
                missingCard
                if item.installed { verdictEditor }
                detailsCard
                SteamInfoPanel(item: item)
                if item.installed { PlayOptionsPanel(item: item) }
                if item.installed { ModsPanel(item: item) }
                if item.installed { SavesPanel(item: item) }
                if item.installed { ScreenshotsPanel(item: item) }
                if let macBuild { macBlock(macBuild) }
                if item.installed, !blocked { willDoCard }
                advanced
                Spacer(minLength: 0)
            }
            .padding(.horizontal, HB.Metric.margin).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HeroBackdrop(item: item, dim: 0.12))
        .hbPageRoot()
        .task(id: item.id) { await state.refreshDerivedComponents(for: item) }
        .sheet(item: $communityDraft) { draft in CommunityVoteSheet(item: item, draft: draft) }
        .sheet(isPresented: $showBottleSettings) {
            if let bottle { BottleSettingsSheet(bottle: bottle).hbSheet() }
        }
    }

    // MARK: Pieces

    /// The key art is the page's background; the title, one line of facts, the status and a big
    /// Play sit over it, bottom-left, the way a console shows a game.
    private var header: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            Text(state.displayTitle(item))
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .lineLimit(3).minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)
            infoLine
            StatusPill(kind: state.statusKind(for: item))
            playRow
            HStack(spacing: HB.Space.s) {
                Button { state.toggleFavorite(item) } label: {
                    Image(systemName: state.isFavorite(item) ? "heart.fill" : "heart")
                        .foregroundStyle(state.isFavorite(item) ? HB.amber : .white)
                }
                .buttonStyle(HBIconButtonStyle())
                .help(state.isFavorite(item) ? L("Remove from favorites") : L("Add to favorites"))
                if state.canImprove(item) {
                    Button { state.improveAsk = item } label: { Label(L("Improve"), systemImage: "wand.and.stars") }
                        .buttonStyle(HBSecondaryButtonStyle())
                        .help(L("Tries this game with different graphics modes and keeps the one that works best on this Mac."))
                }
                Button { withAnimation(HB.Motion.quick) { showAdvanced.toggle() } } label: {
                    Label(L("Expert settings"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(HBSecondaryButtonStyle())   // the same height as the buttons beside it
            }
        }
        .padding(.top, 170)
        // A dropped image becomes this game's cover (it still shows on the library tile).
        .onDrop(of: [.image], isTargeted: $coverDropTargeted) { providers in
            state.acceptCoverDrop(providers, for: item)
        }
    }

    /// "Steam · 68 GB · last played …": what used to sit at the bottom of the page.
    private var infoLine: some View {
        let source = item.source == .steam ? "Steam" : item.source == .epic ? "Epic Games" : L("Windows program")
        var parts = [source]
        if item.sizeOnDisk > 0 { parts.append(ByteCountFormatter.string(fromByteCount: item.sizeOnDisk, countStyle: .file)) }
        if let played = item.lastPlayed { parts.append(L("Last played") + ": " + played.formatted(date: .abbreviated, time: .omitted)) }
        return Text(parts.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
    }

    private var verdictColor: Color {
        switch entry?.status {
        case "verified-local": return HB.good
        case let s? where s.hasPrefix("blocked-"): return HB.bad
        case nil: return .secondary
        default: return HB.amber
        }
    }

    /// A game with a risky anti-cheat and no row of its own: said before Play, with the source.
    @ViewBuilder private var anticheatCard: some View {
        if let appid = item.steamAppID, case let names = state.gameDB.anticheatNotice(appid: appid), !names.isEmpty {
            HStack(alignment: .top, spacing: HB.Space.m) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(HB.amber).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: L("This game uses %@"), names.joined(separator: ", "))).font(.system(size: 15, weight: .semibold))
                    Text(L("Anti-cheats like this often refuse to start under Wine on a Mac. Nobody has tested this game here, so it may not start."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(L("Source: Are We Anti-Cheat Yet?")).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HB.amber.opacity(0.45), lineWidth: 1))
        }
    }

    /// What the Atlas (the site's shared knowledge) says, beside our own record.
    @ViewBuilder private var atlasCard: some View {
        if let appid = item.steamAppID, let atlas = state.atlasEntry(for: item) {
            VStack(alignment: .leading, spacing: 10) {
                HB.eyebrow(L("Atlas"))
                AtlasRows(appid: appid, entry: atlas)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
        }
    }

    /// Before Play: what this game needs that the environment lacks, with the way to add it.
    @ViewBuilder private var missingCard: some View {
        let missing = state.missingComponents(for: item)
        if item.installed, !missing.isEmpty, let bottle {
            HStack(alignment: .top, spacing: HB.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(HB.amber).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("This game needs Windows components this environment does not have yet")).font(.system(size: 15, weight: .semibold))
                    Text(L("Without them it may not start. Installing can take a while; Steam and anything open in Windows is closed first.")).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(missing, id: \.id) { r in
                            Button { state.applyRecipe(r.id, to: bottle) } label: { Label(String(format: L("Install %@"), r.title), systemImage: "arrow.down.circle") }
                                .buttonStyle(HBCompactButtonStyle()).disabled(state.busy)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HB.amber.opacity(0.45), lineWidth: 1))
        }
    }

    private var infoCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { infoCardItems }.fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) { infoCardItems }
        }
    }

    @ViewBuilder private var infoCardItems: some View {
        Group {
            // The player's own result first: other people's numbers are about their Macs.
            if let local = state.localVerdicts[item.id] { localCard(local) }
            InfoCard(symbol: "checkmark.seal", title: state.localVerdicts[item.id] == nil ? L("Status") : L("Other people's results"),
                     value: verdict.headline, detail: verdict.detail, tint: verdictColor)
            InfoCard(symbol: "slider.horizontal.3", title: L("Settings"), value: settingValue, detail: L("The best mode is picked for you."))
            if let tuned = state.tuning[item.id] { tuningCard(tuned) }
        }
    }

    private func localCard(_ v: LocalVerdict) -> some View {
        InfoCard(symbol: v.works ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", title: L("Your Mac"),
                 value: v.works ? L("Works on this Mac") : L("Had problems on this Mac"),
                 detail: [v.machine, v.fps.map { String(format: v.fpsMeasured == true ? L("%d fps measured") : L("%d fps seen"), $0) }, v.date.formatted(date: .abbreviated, time: .omitted),
                          v.auto == true ? L("worked out automatically") : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                 tint: v.works ? HB.good : HB.bad)
    }

    /// "How is it on your Mac?": the answer can be given (or changed) here at any time, not only after a session.
    private var verdictEditor: some View {
        let local = state.localVerdicts[item.id]
        return VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("How is it on your Mac?"))
            HStack(spacing: 10) {
                Button { state.recordVerdict(for: item, works: true, fps: Int(fpsEntry.trimmingCharacters(in: .whitespaces)) ?? local?.fps); UISound.play(.select) } label: {
                    Label(L("Works"), systemImage: "checkmark.circle")
                }.buttonStyle(HBCompactButtonStyle())
                Button { state.recordVerdict(for: item, works: false, fps: nil); UISound.play(.back) } label: {
                    Label(L("Has problems"), systemImage: "exclamationmark.triangle")
                }.buttonStyle(HBCompactButtonStyle())
                TextField(L("fps (optional)"), text: $fpsEntry).textFieldStyle(.roundedBorder).frame(width: 110)
                Spacer(minLength: 8)
                if local != nil {
                    if let draft = state.communityDraft(for: item) {
                        Button(state.sentVotes[draft.appid] == nil ? L("Tell players…") : L("Your report…")) { communityDraft = draft }.buttonStyle(HBCompactButtonStyle())
                            .help(L("Sends an anonymous report (works or not, 1 to 5, your chip and macOS) to help other players. You see every field first."))
                    }
                    Button(L("Share…")) { state.shareVerdict(for: item) }.buttonStyle(HBCompactButtonStyle())
                        .help(L("Opens the project's report form with this Mac's result filled in. Nothing is sent until you press Create."))
                    Button(L("Forget")) { state.removeVerdict(for: item) }.buttonStyle(HBCompactButtonStyle())
                }
            }
            Text(L("Kept on this Mac and shown above other people's results. The frame rate is whatever you read off the screen."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
    }

    /// What is known about the game, in plain rows.
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HB.eyebrow(L("Details"))
            row(L("Source"), item.source == .steam ? "Steam" : item.source == .epic ? "Epic Games" : L("Windows program"))
            if item.sizeOnDisk > 0 { row(L("Size on disk"), ByteCountFormatter.string(fromByteCount: item.sizeOnDisk, countStyle: .file)) }
            if let steam = state.steamMinutes(for: item) { row(L("Time played on Steam"), PlaytimeText.format(seconds: steam * 60)) }
            if let total = state.playtimes[item.id], state.steamMinutes(for: item) == nil { row(L("Time played"), PlaytimeText.format(seconds: total)) }
            if let played = item.lastPlayed { row(L("Last played"), played.formatted(date: .abbreviated, time: .shortened)) }
            if let name = item.bottleName { row(L("Environment"), name) }
            if let appid = item.steamAppID { row(L("Steam ID"), String(appid)) }
            if let folder = state.programFolder(for: item) { row(L("Location"), folder.path) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hbCard(radius: 16)
    }

    private func tuningCard(_ t: TuningResult) -> some View {
        let when = t.date.formatted(date: .abbreviated, time: .omitted)
        if let best = t.best, let a = t.attempts.first(where: { $0.renderer == best }) {
            return InfoCard(symbol: "wand.and.stars", title: L("Improved"), value: GamePageCopy.plainName(best),
                            detail: String(format: L("Tested on this Mac on %@: ran %d s without trouble."), when, a.secondsAlive),
                            tint: HB.good)
        }
        let started = t.attempts.contains { $0.verdict != .neverStarted }
        return InfoCard(symbol: "wand.and.stars", title: L("Improved"), value: L("No mode worked cleanly"),
                        detail: started ? String(format: L("Tried on %@. Every mode crashed or showed a black screen."), when)
                                        : String(format: L("Tried on %@. The game never started: make sure you are signed in to Steam."), when),
                        tint: HB.bad)
    }

    private var settingValue: String {
        if let r = entry?.effectiveRenderer() { return GamePageCopy.plainName(r) }
        return L("Automatic")
    }

    private var verdictBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(verdictColor).frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(verdict.headline).font(.system(size: 17, weight: .semibold))
                if let detail = verdict.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var macBuild: GamePageCopy.MacBuild? {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        return GamePageCopy.macBuild(state.macSteamBuild(for: item), entry: entry, myChip: state.machineChip, macOS: os)
    }

    /// A native Mac build on Steam: what it is, why it matters, what it needs. Above the verdict,
    /// which is about the Windows build.
    private func macBlock(_ copy: GamePageCopy.MacBuild) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "apple.logo").foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(copy.headline).font(.callout.weight(.semibold))
                Text(copy.detail).font(.callout).foregroundStyle(.secondary)
                // This Mac only next to what the build asks for: the verdict below already names the chip.
                if let requirements = copy.requirements {
                    Text(requirements).font(.callout).foregroundStyle(.secondary)
                    Text(copy.yourMac).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    macButton
                    Text(copy.source).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .hbGlass(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.35)))
    }

    /// Only when the Windows build is the installed one: otherwise the play row already offers
    /// the Mac build (Play on Mac, Install on Mac).
    @ViewBuilder private var macButton: some View {
        if item.installed, !item.installedOnMac {
            Button(state.steamForMacInstalled ? L("Install on Mac") : L("Get Steam for Mac")) { state.installOnMac(item) }
                .controlSize(.small)
        }
    }

    private var playRow: some View {
        HStack(spacing: HB.Space.m) {
            if let running {
                Button(L("Stop")) { state.stopSession(running) }.buttonStyle(HBSecondaryButtonStyle())
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    Text(ActivityText.minutes(since: running.started, now: ctx.date)
                            .map { String(format: L("Running for %d min"), $0) } ?? L("Running"))
                        .font(.callout).foregroundStyle(HB.good)
                }
            } else if state.prefersMacBuild(item) {
                // The native build first; a Windows copy in a bottle stays one click away.
                Button { state.playOnMac(item) } label: {
                    Label(L("Play on Mac"), systemImage: "play.fill")
                }
                .buttonStyle(HBPrimaryButtonStyle())
                if item.installed {
                    Button(L("Play the Windows version")) { state.play(item, windowsBuild: true) }
                        .buttonStyle(HBSecondaryButtonStyle()).disabled(state.busy || blocked)
                } else {
                    Text(L("Starts through Steam for Mac.")).font(.callout).foregroundStyle(.secondary)
                }
            } else if item.installed {
                Button { state.play(item) } label: {
                    Label(L("Play"), systemImage: "play.fill")
                }
                .buttonStyle(HBPrimaryButtonStyle())
                .disabled(state.busy || blocked)
                if item.installedOnMac {
                    // The row put the Windows build first (a Mac build missing content); the Mac one stays a click away.
                    Button(L("Play on Mac")) { state.playOnMac(item) }.buttonStyle(HBSecondaryButtonStyle())
                } else {
                    Text(!blocked ? L("After a long session KLYC-Box notes by itself that it works on this Mac.")
                         : entry?.status == "blocked-publisher" ? L("Its publisher stops it on macOS on purpose.")
                         : L("Its anti-cheat does not run on macOS."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if item.source == .epic {
                Button(L("Install")) { state.install(item) }.buttonStyle(HBPrimaryButtonStyle())
                    .disabled(state.busy)
                Text(String(format: L("Installs into %@."), state.defaultBottle?.name ?? L("your environment"))).font(.callout).foregroundStyle(.secondary)
            } else if item.source == .steam, !steamHasManifest, state.macSteamBuild(for: item) != nil {
                // A native build exists: that's the install on offer; the Windows one is the
                // way around it, not the default.
                // Two ways to install, each a real button with its own line underneath: the Mac build (the default) and the Windows one.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) { macInstallOption; windowsInstallOption }
                    VStack(alignment: .leading, spacing: HB.Space.m) { macInstallOption; windowsInstallOption }
                }
            } else if item.source == .steam, !steamHasManifest {
                // Owned, never installed here: Steam's own dialog takes it from here.
                Button(L("Install")) { state.install(item) }.buttonStyle(HBPrimaryButtonStyle())
                    .disabled(state.busy)
                Text(L("Steam asks where to put it.")).font(.callout).foregroundStyle(.secondary)
            } else if item.source == .steam {
                Text(L("Not downloaded yet. Install it from the Steam window.")).font(.callout).foregroundStyle(.secondary)
                if let b = bottle ?? state.defaultBottle { Button(L("Open Steam")) { state.showSteam(in: b) }.buttonStyle(HBSecondaryButtonStyle()) }
            } else {
                Text(L("Not installed.")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var macInstallOption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { state.installOnMac(item) } label: {
                Label(state.steamForMacInstalled ? L("Install on Mac") : L("Get Steam for Mac"), systemImage: "apple.logo")
            }
            .buttonStyle(HBPrimaryButtonStyle())
            Text(state.steamForMacInstalled ? L("Steam for Mac asks where to put it.") : L("The Mac build installs through Steam for Mac."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
        }
    }

    private var windowsInstallOption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { state.install(item) } label: { Label(L("Install the Windows version instead"), systemImage: "pc") }
                .buttonStyle(HBSecondaryButtonStyle()).disabled(state.busy || blocked)
            Text(L("For when the Mac build lags behind or a mod needs the Windows one."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
        }
    }

    private var willDoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Next to Play on Mac, "Play" alone would read as the Mac build's. Collapsed: the page
            // says what is ready, this says exactly what Play will do for anyone who wants to know.
            Button { withAnimation(HB.Motion.quick) { showPlan.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: showPlan ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold)).frame(width: 12)
                    HB.eyebrow(state.prefersMacBuild(item) ? L("When you play the Windows version, KLYC-Box will") : L("When you press Play, KLYC-Box will"))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showPlan { ForEach(Array(willDo.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: line.done ? "checkmark" : (line.cost == nil ? "checkmark" : "hourglass"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(line.cost == nil || line.done ? HB.good : HB.amber)
                        .frame(width: 14)
                    Text(line.text).font(.callout)
                    if let cost = line.cost {
                        Text(cost).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } }
            if showPlan, let profile, !profile.isEmpty { programProfileLines(profile) }
            if showPlan, let held = GamePageCopy.rowRendererHeldBack(entry, bottleRenderer: bottle?.settings.renderer ?? .dxvk,
                                                           explicit: bottle?.settings.rendererExplicit ?? false,
                                                           gameOverride: state.rendererOverride(for: item)),
               let engine = bottle.flatMap({ state.engine(for: $0) }), held.availability(in: engine) == .available {
                Button(String(format: L("Use %@ for this game"), GamePageCopy.plainName(held))) {
                    state.setRendererOverride(held, for: item.id)
                }
                .controlSize(.small).padding(.top, 2)
            }
            if showPlan { HStack(spacing: 6) {
                Text(entry == nil ? L("No row in the compatibility database yet.") : L("From the open compatibility database."))
                    .font(.caption).foregroundStyle(.secondary)
                if entry != nil {
                    Button(L("Why these settings?")) { showWhy.toggle() }
                        .buttonStyle(HBTextButtonStyle()).font(.caption)
                        .popover(isPresented: $showWhy, arrowEdge: .bottom) { whyPopover }
                }
            } }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hbGlass(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HB.cardStroke))
        // The executable's headers are read once the plan is opened, never while the page loads.
        .task(id: showPlan ? item.id : "") {
            guard showPlan, let exe = state.programExecutable(for: item) else { profile = nil; return }
            profile = await Task.detached(priority: .utility) { ProgramProfile.read(program: exe) }.value
        }
    }

    /// What the program's own file says it needs, and what KLYC-Box does about it. Every line is
    /// something the code does (the same rules Play applies), never advice about the game.
    @ViewBuilder private func programProfileLines(_ p: ProgramProfile) -> some View {
        let bits = p.is64Bit.map { $0 ? "64-bit" : "32-bit" }
        let apis = p.apis.map(\.displayName).joined(separator: ", ")
        VStack(alignment: .leading, spacing: 4) {
            Text([bits, apis.isEmpty ? nil : apis].compactMap { $0 }.joined(separator: " · "))
                .font(.callout)
            ForEach(Array(profileNotes(p).enumerated()), id: \.offset) { _, note in
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private func profileNotes(_ p: ProgramProfile) -> [String] {
        var notes: [String] = []
        if p.isUnreal5 {
            notes.append(L("An Unreal Engine 5 build loads Direct3D 12 when it starts, so KLYC-Box picks a mode that has it, unless a row or your own choice says otherwise."))
        } else if p.needsDirect3D12 {
            notes.append(L("It only has Direct3D 12, so KLYC-Box picks a mode that has it, unless a row or your own choice says otherwise."))
        }
        if p.is64Bit == false, p.apis.contains(where: { $0 == .direct3D11 || $0 == .direct3D10 }) {
            notes.append(L("It is 32-bit, and Apple's DirectX 12 mode is 64-bit only, so its Direct3D 11 runs through DXMT."))
        }
        if p.apis.contains(.direct3D9) {
            notes.append(L("Direct3D 9 runs through DXVK in every mode."))
        }
        return notes
    }

    /// The explanation, and the way out: the environment's own settings are one click away.
    private var whyPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Why these settings")).font(.headline)
            if let notes = entry?.notes { Text(notes).font(.callout) }
            if let p = entry?.provenance {
                Text(p).font(.caption).foregroundStyle(.secondary)
            }
            if let results = entry?.rendererResults, !results.isEmpty {
                Divider()
                ForEach(results.keys.sorted(), id: \.self) { key in
                    if let r = results[key] {
                        Text("\(key.uppercased()): \(r.verdict)\(r.detail.map { ", \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text(L("To play with the environment's own graphics mode instead, change it under Advanced below; KLYC-Box then leaves it alone for every game in that environment."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 420)
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            if showAdvanced {
                VStack(alignment: .leading, spacing: 10) {
                    if let bottle {
                        if entry?.nativeVulkan == true {
                            row(L("Graphics mode"), L("Does not apply: this game draws with Vulkan directly, not through any Direct3D layer."))
                        } else {
                            if let engine = state.engine(for: bottle) {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(L("Mode for this game")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading).padding(.top, 4)
                                    Picker("", selection: Binding(
                                        get: { state.rendererOverride(for: item)?.rawValue ?? "" },
                                        set: { state.setRendererOverride(Renderer(rawValue: $0), for: item.id) })) {
                                        Text(L("Environment's mode")).tag("")
                                        // Shipped modes, licence accepted or not: a pick that still
                                        // needs Apple's licence is asked for at Play.
                                        ForEach(Renderer.allCases.filter { $0.availability(in: engine) != .notShipped }, id: \.self) { r in
                                            Text(GamePageCopy.plainName(r)).tag(r.rawValue)
                                        }
                                    }.labelsHidden().frame(maxWidth: 360)
                                }
                            }
                            HStack(alignment: .top, spacing: 12) {
                                Text(L("Environment's mode")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading).padding(.top, 4)
                                GraphicsModePicker(bottle: bottle)
                            }
                        }
                        if let emulated = state.displayModeEmulation(for: item) {
                            HStack(alignment: .top, spacing: 12) {
                                Text(L("Display mode")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle(L("Emulate display mode changes"), isOn: Binding(
                                        get: { emulated }, set: { state.setDisplayModeEmulation($0, for: item) }))
                                        .toggleStyle(.checkbox)
                                    Text(L("For a game that opens small, off-centre, or refuses its fullscreen mode. The Mac cannot switch its display for it, so Wine pretends and scales the picture instead. A fix from the database may have set this already."))
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        row(L("Engine"), (state.engine(for: bottle)?.displayName).map { "\($0) · \(bottle.settings.engineID)" } ?? bottle.settings.engineID)
                        // Variables a fix scoped to this game: the environment's own
                        // editor shows only the environment-wide ones, so the page says what this
                        // game gets on top of them.
                        let scoped = bottle.settings.environment(forGame: entry?.id)
                        if !scoped.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Text(L("This game's variables")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(scoped.keys.sorted(), id: \.self) { key in
                                        Text("\(key)=\(scoped[key] ?? "")").font(.callout.monospaced()).textSelection(.enabled)
                                    }
                                    Text(L("Set by this game's fix, applied to its launches only."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(L("Environment")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            Text(bottle.name).font(.callout)
                            Button(L("Environment settings…")) { showBottleSettings = true }.controlSize(.small)
                        }
                        if !item.otherBottles.isEmpty {
                            row(L("Also installed in"), item.otherBottles.joined(separator: ", "))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(L("Files")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            if let folder = state.programFolder(for: item) {
                                Button(L("Show the game's folder")) { NSWorkspace.shared.open(folder) }.controlSize(.small)
                                    .help(L("Opens the game's own folder in the Finder, where mods and config files go."))
                            }
                            Button(L("Show the Windows drive")) { NSWorkspace.shared.open(bottle.driveC) }.controlSize(.small)
                            if item.installed {
                                Button(L("Uninstall…"), role: .destructive) { state.askUninstall(item) }.controlSize(.small)
                                    .help(L("Steam and the Epic tools do their own uninstalling, so their libraries stay right."))
                            }
                            if MacAppStub.existing(for: item.title) != nil {
                                Button(L("Remove the Mac app")) { state.removeMacApp(title: item.title) }.controlSize(.small)
                                    .help(L("Moves this game's Mac app in ~/Applications/KLYC-Box to the Trash."))
                            } else if PlayLink.target(for: item) != nil {
                                Button(L("Make a Mac app…")) { state.makeMacApp(for: item) }.controlSize(.small)
                                    .help(L("A real app in ~/Applications/KLYC-Box with the game's own icon, for the Dock, Spotlight or Launchpad. It starts the game without opening KLYC-Box first."))
                            }
                            if MacAppStub.existingDesktopCopy(for: item.title) != nil {
                                Button(L("Remove from the Desktop")) { state.removeDesktopShortcut(for: item) }.controlSize(.small)
                            } else if PlayLink.target(for: item) != nil {
                                Button(L("Add to the Desktop")) { state.addDesktopShortcut(for: item) }.controlSize(.small)
                                    .help(L("Puts a shortcut with the game's own icon on the Desktop. Double-clicking it starts the game."))
                            }
                        }
                        if let log = state.lastLaunchLog(for: item) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(L("Log")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                Button(L("Show the last launch log")) { NSWorkspace.shared.open(log) }.controlSize(.small)
                                    .help(log.lastPathComponent)
                            }
                        }
                        if let fixRecipe, item.installed {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(L("Fix")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                                Button(fixApplied ? String(format: L("Re-apply the %@ fix"), fixRecipe.title) : String(format: L("Apply the %@ fix now"), fixRecipe.title)) {
                                    state.applyRecipe(fixRecipe.id, to: bottle)
                                }
                                .controlSize(.small).disabled(state.busy)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hbGlass(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 6)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}

private extension ProgramProfile.API {
    /// Product names, the same in every language.
    var displayName: String {
        switch self {
        case .direct3D12: return "Direct3D 12"
        case .direct3D11: return "Direct3D 11"
        case .direct3D10: return "Direct3D 10"
        case .direct3D9: return "Direct3D 9"
        case .direct3D8: return "Direct3D 8"
        case .directDraw: return "DirectDraw"
        case .openGL: return "OpenGL"
        case .vulkan: return "Vulkan"
        }
    }
}

import SwiftUI
import KLYCKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, library, steam, epic, profile, downloads, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return L("Home")
        case .library: return L("Library")
        case .steam: return "Steam"
        case .epic: return "Epic Games"
        case .profile: return L("Profile")
        case .downloads: return L("Downloads")
        case .settings: return L("Settings")
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .library: return "books.vertical"
        case .steam: return "gamecontroller"
        case .epic: return "bag"
        case .profile: return "person.crop.circle"
        case .downloads: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }
}

/// The main window: a fixed top bar (back, sections, add, settings) over the chosen section.
/// The bar is ours, not the native toolbar: it never rebuilds when the section changes, so nothing jumps.
struct MainShell: View {
    @Environment(AppState.self) private var state
    /// KLYC_START_SECTION=library opens that section first (handy for screenshots).
    @State private var section: AppSection = ProcessInfo.processInfo.environment["KLYC_START_SECTION"].map { ["store", "friends", "steamweb"].contains($0) ? "steam" : ($0 == "epicstore" ? "epic" : $0) }.flatMap(AppSection.init(rawValue:)) ?? .home
    @State private var path = NavigationPath()
    private let pad = Gamepad.shared

    var body: some View {
        ZStack(alignment: .top) {
            content
                .id(section)
                .transition(.opacity)
                .toolbar(.hidden, for: .windowToolbar)
                // Room for the top bar: art still runs under it (the backdrops ignore the safe area).
                .safeAreaPadding(.top, 64)
            TopBar(section: $section, path: $path)
        }
        .animation(HB.Motion.standard, value: section)
        .hbToasts()
        .hbScrollEdgeClear()
        .onChange(of: section) { _, _ in path = NavigationPath() }
        // Back from the keyboard too: Escape and Command-[ go one step back, wherever the page was scrolled to.
        .onExitCommand { if !path.isEmpty { UISound.play(.back); path.removeLast() } }
        .background(Button("") { if !path.isEmpty { UISound.play(.back); path.removeLast() } }.keyboardShortcut("[", modifiers: .command).opacity(0).allowsHitTesting(false))
        .onAppear { pad.start() }
        // After a crash: offer a pre-filled GitHub report (nothing is sent without the person pressing submit there).
        .task {
            try? await Task.sleep(for: .seconds(6))
            CrashPrompt.checkOnLaunch(chip: state.machineChip)
        }
        // KLYC_TOAST_DEMO=1 shows a confirmation a moment after launch (handy for screenshots).
        .task {
            guard ProcessInfo.processInfo.environment["KLYC_TOAST_DEMO"] != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            state.notify(String(format: L("Frame rate cap: %d fps. Takes effect the next time the game starts."), 60))
        }
        // KLYC_START_GAME=assetto opens that game's page first (handy for screenshots).
        .task {
            guard let want = ProcessInfo.processInfo.environment["KLYC_START_GAME"] else { return }
            for _ in 0..<60 {
                if let item = state.libraryItems.first(where: { state.displayTitle($0).localizedCaseInsensitiveContains(want) }) { path.append(item); return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        // Bumpers switch sections, B goes back: the same things the top bar does.
        .onChange(of: pad.event?.id) { _, _ in
            let tabs = AppSection.allCases.filter { $0 != .settings }
            guard let button = pad.event?.button, let i = tabs.firstIndex(of: section) else { return }
            switch button {
            case .previousSection: UISound.play(.select); section = tabs[max(i - 1, 0)]
            case .nextSection: UISound.play(.select); section = tabs[min(i + 1, tabs.count - 1)]
            case .back: if !path.isEmpty { UISound.play(.back); path.removeLast() }
            default: break
            }
        }
        // Key art runs to the very top: no title bar, no bar background.
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(red: 0.044, green: 0.051, blue: 0.068, alpha: 1)
        })
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .home: NavigationStack(path: $path) { HomeView() }
        case .library: NavigationStack(path: $path) { LibraryView(initialSource: nil) }
        case .steam: SteamHub(path: $path)
        case .epic: EpicHub(path: $path)
        case .profile: NavigationStack(path: $path) { ProfileView() }
        case .downloads: NavigationStack(path: $path) { DownloadsView() }
        case .settings: NavigationStack(path: $path) { SettingsView() }
        }
    }
}

/// Always at the top, always centered, glass over whatever is behind it (also in full screen).
struct TopBar: View {
    @Environment(AppState.self) private var state
    @Binding var section: AppSection
    @Binding var path: NavigationPath

    var body: some View {
        ZStack {
            HBTabs(selection: $section).hbGlass(Capsule())
            HStack(spacing: 10) {
                if !path.isEmpty {
                    Button { UISound.play(.back); if !path.isEmpty { path.removeLast() } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(HBIconButtonStyle())
                        .help(L("Back"))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                Spacer(minLength: 0)
                AddGamesMenu()
                Button { UISound.play(.select); section = .settings } label: { Image(systemName: "gearshape") }
                    .buttonStyle(HBIconButtonStyle())
                    .overlay(alignment: .topTrailing) {
                        if let version = UpdateStatus.shared.availableVersion {
                            Circle().fill(HB.amber).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
                                .offset(x: 2, y: -2)
                                .help(String(format: L("Version %@ is available"), version))
                                .accessibilityLabel(String(format: L("Version %@ is available"), version))
                        }
                    }
                    .help(UpdateStatus.shared.availableVersion.map { String(format: L("Version %@ is available"), $0) } ?? L("Settings"))
            }
            // The back button sits on the same left margin as the page below it. The window buttons are in the title bar, a row above.
            .padding(.horizontal, HB.Metric.margin)
        }
        .frame(height: 56)
        .padding(.top, 6)
        .animation(HB.Motion.standard, value: path.isEmpty)
    }
}

/// Reads the library again from disk: what was installed or deleted outside KLYC-Box shows up (or goes away) without a restart.
struct RefreshLibraryButton: View {
    @Environment(AppState.self) private var state
    @State private var spin = 0.0
    var body: some View {
        Button {
            UISound.play(.select)
            withAnimation(.easeInOut(duration: 0.6)) { spin += 360 }
            state.refresh()
        } label: {
            Image(systemName: "arrow.clockwise").rotationEffect(.degrees(spin))
        }
        .buttonStyle(HBIconButtonStyle())
        .help(L("Refresh the library (⌘R)"))
    }
}

struct AddGamesMenu: View {
    @Environment(AppState.self) private var state
    var body: some View {
        Menu {
            Button(state.defaultBottle.map(state.steamInstalled) == true ? L("Open Steam") : L("Install Steam")) { state.installSteam() }
            if state.epicSignedIn {
                // The menu said "Connect" even once connected (0.8.0 feedback).
                Button(L("Epic account connected")) {}.disabled(true)
            } else {
                Button(L("Connect Epic account…")) { state.showEpicSignIn = true }
            }
            Divider()
            Button(L("Add games from a folder…")) { state.chooseGameFolder() }
            Button(L("A Windows program I have…")) { state.chooseProgramToRun() }
        } label: {
            Image(systemName: "plus").hbIconChrome()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(state.busy || state.bottles.isEmpty)
        .help(L("Add games"))
    }
}

// MARK: - Home (the console-style screen)

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var model = HomeViewModel()
    @FocusState private var shelfFocused: Bool
    private let pad = Gamepad.shared

    var body: some View {
        GeometryReader { geo in
            let shelf = model.shelf(in: state)
            let focused = model.focused(in: shelf)
            let wide = geo.size.width >= 1000
            let titleSize = min(56, max(32, geo.size.width / 22))
            ZStack {
                HeroBackdrop(item: focused)
                if let focused {
                    VStack(alignment: .leading, spacing: 0) {
                        ShelfRow(items: shelf, focusID: Binding(get: { focused.id }, set: { model.focusID = $0 }), tile: wide ? 128 : 104)
                            .padding(.top, 62)   // the whole width: search and refresh sit on their own row above
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 28) {
                            FocusedDetails(item: focused, titleSize: titleSize)
                                .id(focused.id)
                                .transition(.opacity)
                            Spacer(minLength: 0)
                            if wide { FocusedFacts(item: focused) }
                        }
                        .padding(.bottom, 44)
                        .animation(.spring(duration: 0.4), value: focused.id)
                    }
                    .padding(.horizontal, wide ? HB.Metric.margin : 24)
                    .focusable()
                    .focused($shelfFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.leftArrow) { move(-1, in: shelf); return .handled }
                    .onKeyPress(.rightArrow) { move(1, in: shelf); return .handled }
                    .onKeyPress(.return) { if model.canPlay(focused, in: state) { UISound.play(.start); state.play(focused) }; return .handled }
                    .onAppear { shelfFocused = true; prefetch(focused, in: shelf) }
                    .onChange(of: focused.id) { _, _ in prefetch(focused, in: shelf) }
                    .onChange(of: pad.event?.id) { _, _ in
                        switch pad.event?.button {
                        case .left: move(-1, in: shelf)
                        case .right: move(1, in: shelf)
                        case .accept: if model.canPlay(focused, in: state) { UISound.play(.start); state.play(focused) }
                        default: break
                        }
                    }
                } else if !model.search.isEmpty {
                    Text(L("Nothing matches your search.")).font(.title3).foregroundStyle(.white.opacity(0.7))
                } else {
                    ScrollView { GettingStarted().padding(.top, 60) }
                }
            }
            .overlay(alignment: .topLeading) { SharedLibraryBanner().padding(.top, 84).padding(.leading, HB.Metric.margin) }
            .overlay(alignment: .topTrailing) {
                if !shelf.isEmpty || !model.search.isEmpty {
                    HStack(spacing: 10) {
                        RefreshLibraryButton()
                        HBSearchField(text: $model.search, prompt: L("Search your games"), width: wide ? 250 : 170)
                    }
                    .padding(.top, 14).padding(.trailing, wide ? HB.Metric.margin : 24)
                }
            }
        }
        .hbPageRoot()
        .navigationDestination(for: LibraryItem.self) { GameDetailView(passedItem: $0) }
    }

    /// Warms the image cache with the next games' key art so moving along the shelf never waits for a download.
    private func prefetch(_ focused: LibraryItem, in shelf: [LibraryItem]) {
        let urls = model.neighbours(of: focused, in: shelf).compactMap { item in
            item.steamAppID.flatMap { URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\($0)/library_hero.jpg") }
        }
        Task.detached(priority: .utility) {
            for url in urls { _ = try? await URLSession.shared.data(from: url) }
        }
    }

    private func move(_ delta: Int, in shelf: [LibraryItem]) {
        let before = model.focusID
        withAnimation(.spring(duration: 0.28)) { _ = model.move(delta, in: shelf) }
        if model.focusID != before { UISound.play(.move) }
    }
}

/// The row of small covers; the focused one grows and gets a white ring.
struct ShelfRow: View {
    @Environment(AppState.self) private var state
    let items: [LibraryItem]
    @Binding var focusID: String
    /// The side of a cover that is not selected; the selected one is bigger by the same factor as before.
    var tile: CGFloat = 82
    private var focusedTile: CGFloat { tile * 1.45 }

    var body: some View {
        ScrollViewReader { proxy in
            HScroll {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        let on = item.id == focusID
                        Button {
                            if !on { UISound.play(.move) }
                            withAnimation(.spring(duration: 0.28)) { focusID = item.id }
                        } label: {
                            CoverArt(item: item)
                                .frame(width: on ? focusedTile : tile, height: on ? focusedTile : tile)
                                .clipShape(RoundedRectangle(cornerRadius: on ? 22 : 16))
                                .overlay(RoundedRectangle(cornerRadius: on ? 22 : 16)
                                    .stroke(Color.white.opacity(on ? 0.95 : 0.14), lineWidth: on ? 3 : 1))
                                .overlay(alignment: .topTrailing) {
                                    if state.favorites.contains(item.id) {
                                        Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                            .padding(5).background(Circle().fill(HB.amber)).padding(4)
                                    }
                                }
                                .shadow(color: .black.opacity(on ? 0.5 : 0.25), radius: on ? 16 : 6, y: on ? 8 : 3)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 4)
            }
            .onChange(of: focusID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
        }
        .frame(height: focusedTile + 24)
    }
}

struct FocusedDetails: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    var titleSize: CGFloat = 52

    private var entry: GameDBEntry? { state.gameDB.entry(for: item) }
    private var blocked: Bool { entry?.isBlocked == true }
    private var playable: Bool { (state.prefersMacBuild(item) || (item.installed && !blocked)) && !state.busy }
    private var verdict: GamePageCopy.Verdict { GamePageCopy.verdict(entry, myChip: state.machineChip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.displayTitle(item))
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.55)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 4)
            Text(meta).font(.system(size: 14)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            Text(verdict.headline).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(2).frame(maxWidth: 520, alignment: .leading)
            HStack(spacing: 12) {
                Button { UISound.play(.start); state.play(item) } label: {
                    Label(L("Play"), systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold)).lineLimit(1).fixedSize()
                        .foregroundStyle(HB.ink)
                        .frame(minWidth: 150, minHeight: 54)
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(HB.lit.opacity(0.96)))
                .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
                .disabled(!playable).opacity(playable ? 1 : 0.5)
                NavigationLink(value: item) {
                    Text(L("Open page")).font(.system(size: 15, weight: .medium)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 22).frame(height: 54)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { UISound.play(.select) })
                .hbGlass(Capsule(), interactive: true)
                Button { state.toggleFavorite(item) } label: {
                    Image(systemName: state.isFavorite(item) ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(state.isFavorite(item) ? HB.amber : .white)
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.plain)
                .hbGlass(Circle(), interactive: true)
                .help(state.isFavorite(item) ? L("Remove from favorites") : L("Add to favorites"))
                Button { UISound.play(.select); state.setMetalHUD(!state.metalHUD(for: item), for: item) } label: {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(state.metalHUD(for: item) ? HB.amber : .white)
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.plain)
                .hbGlass(Circle(), interactive: true)
                .help(state.metalHUD(for: item) ? L("Frame rate overlay is on for this game (next start)") : L("Show the frame rate while playing, and measure it"))
                if state.canImprove(item) {
                    Button { UISound.play(.select); state.improveAsk = item } label: {
                        Label(L("Improve"), systemImage: "wand.and.stars")
                            .font(.system(size: 15, weight: .medium)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 22).frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .hbGlass(Capsule(), interactive: true)
                }
            }
            .padding(.top, 6)
        }
    }

    private var meta: String {
        var parts = [item.source == .steam ? "Steam" : item.source == .epic ? "Epic Games" : L("Windows program")]
        if item.sizeOnDisk > 0 { parts.append(ByteCountFormatter.string(fromByteCount: item.sizeOnDisk, countStyle: .file)) }
        if let steam = state.steamMinutes(for: item) { parts.append(PlaytimeText.format(seconds: steam * 60)) }
        else if let total = state.playtimes[item.id] { parts.append(PlaytimeText.format(seconds: total)) }
        if let played = item.lastPlayed { parts.append(played.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}

/// Bottom-right glass panel: what is known about the focused game, nothing invented.
struct FocusedFacts: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    private var entry: GameDBEntry? { state.gameDB.entry(for: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(L("Status")) { StatusPill(kind: state.statusKind(for: item)) }
            row(L("Settings")) {
                Text(entry?.effectiveRenderer().map { GamePageCopy.plainName($0) } ?? L("Automatic"))
                    .font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            if let fps = entry?.verified?.fps.flatMap({ GamePageCopy.fpsPhrase($0) }) {
                row(L("Performance")) { Text(fps).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8) }
            }
        }
        .padding(16)
        .frame(width: 270, alignment: .leading)
        .hbGlass(RoundedRectangle(cornerRadius: 18))
    }

    private func row<V: View>(_ title: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 12)
            value()
        }
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @Environment(AppState.self) private var state
    @State private var transfers: [SteamTransfer] = []
    @State private var rates = SteamTransferRates()
    /// False until the first look at Steam's files is done: until then "nothing is downloading"
    /// would be a guess, so a placeholder stands there.
    @State private var looked = false

    private var active: [SteamTransfer] { transfers.filter { $0.state != .installed }.sorted { $0.name < $1.name } }
    private var installed: [SteamTransfer] { transfers.filter { $0.state == .installed }.sorted { $0.sizeOnDisk > $1.sizeOnDisk } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if state.busy {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.busyTitle).font(.system(size: 15, weight: .semibold))
                            if !state.stage.isEmpty { Text(state.stage).font(.callout).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        if let stop = state.busyStop { Button(stop.label) { state.stopBusy() }.buttonStyle(HBSecondaryButtonStyle()) }
                    }
                    .padding(16).hbCard()
                }
                if !state.epicDownloads.downloads.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HB.eyebrow(L("Epic downloads"))
                        ForEach(state.epicDownloads.downloads) { EpicDownloadRow(download: $0) }
                        Text(L("Pause keeps what was downloaded; Resume continues from there, also after you quit KLYC-Box."))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
                }
                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HB.eyebrow(L("Steam downloads"))
                        ForEach(active) { row($0) }
                        Text(L("Read from Steam's own files every few seconds. Pause and resume in Steam itself."))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
                } else if !looked && !state.busy && state.epicDownloads.downloads.isEmpty {
                    SkeletonDownloadCard()
                } else if !state.busy && state.epicDownloads.downloads.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 34)).foregroundStyle(.tertiary)
                        Text(L("Nothing is downloading or installing right now.")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                if !installed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            HB.eyebrow(L("Installed games and their size"))
                            Spacer(minLength: 8)
                            Text(ByteCountFormatter.string(fromByteCount: installed.reduce(0) { $0 + $1.sizeOnDisk }, countStyle: .file))
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        let biggest = max(installed.first?.sizeOnDisk ?? 1, 1)
                        ForEach(installed) { g in
                            HStack(spacing: 12) {
                                Text(g.name).font(.system(size: 14, weight: .medium)).lineLimit(1).frame(width: 220, alignment: .leading)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.08))
                                        Capsule().fill(HB.amber.opacity(0.85)).frame(width: max(4, geo.size.width * CGFloat(g.sizeOnDisk) / CGFloat(biggest)))
                                    }
                                }.frame(height: 8)
                                Text(ByteCountFormatter.string(fromByteCount: g.sizeOnDisk, countStyle: .file)).font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                            }
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
                }
            }
            .hubPageFrame()
        }
        .background(BottleBackdrop())
        .hbPageRoot()
        .task {
            // The client rewrites its files as it downloads: look again every few seconds while this screen is open.
            while !Task.isCancelled {
                if let bottle = state.steamBottle {
                    let steamapps = bottle.driveC.appending(path: "Program Files (x86)/Steam/steamapps")
                    transfers = await Task.detached { SteamTransfer.scan(steamapps: steamapps) }.value
                    rates.update(transfers, at: Date())
                }
                looked = true
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func row(_ t: SteamTransfer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(label(t)).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: t.progress ?? 0).tint(HB.amber)
            HStack(spacing: 10) {
                // Speed and time left are worked out from how fast Steam's files change: an estimate.
                let pace = [rates.speed[t.appid].flatMap(EpicDownloadText.speed(bytesPerSecond:)),
                            rates.etaSeconds(for: t).flatMap(EpicDownloadText.timeLeft(seconds:))].compactMap { $0 }
                if !pace.isEmpty { Text(pace.joined(separator: " · ")).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                if t.toDownload > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: t.downloaded, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: t.toDownload, countStyle: .file))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func label(_ t: SteamTransfer) -> String {
        switch t.state {
        case .downloading: return t.progress.map { "%\(Int($0 * 100))" } ?? L("Downloading")
        case .paused: return L("Paused")
        case .waiting: return L("Waiting")
        case .installed: return ""
        }
    }
}

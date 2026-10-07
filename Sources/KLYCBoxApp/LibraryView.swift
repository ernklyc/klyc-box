import SwiftUI
import KLYCKit

/// SwiftUI re-exports DeveloperToolsSupport.LibraryItem; this pins the name to ours
/// for the whole app target.
typealias LibraryItem = KLYCKit.LibraryItem

// One Library (Phase 2): the app's primary surface. One uniform cover grid across all
// bottles and sources — store is a corner badge and a filter chip, never a section; the
// bottle is a per-game property on the detail page, never the navigation.

struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    @State private var model: LibraryViewModel
    init(initialSource: LibrarySource? = nil, show: LibraryQuery.Show = .installed) {
        _model = State(initialValue: LibraryViewModel(source: initialSource, show: show))
    }

    private func sortTitle(_ s: LibraryQuery.Sort) -> String {
        switch s { case .name: return L("Name (A to Z)"); case .recent: return L("Last played"); case .size: return L("Size on disk") }
    }

    private func titleBlock(_ count: Int) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(model.pageTitle)
                .font(.system(size: 38, weight: .heavy, design: .rounded)).lineLimit(1).fixedSize()
                .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
            Text(String(format: L("%d games"), count))
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).fixedSize()
        }
    }

    var body: some View {
        // Computed once per draw: the list is used for the hero, the count and the grid.
        let items = model.items(in: state)
        return ZStack {
            if items.isEmpty { BottleBackdrop() } else { HeroBackdrop(item: model.hovered ?? items.first, dim: 0.45, blur: 10) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HubHeaderSlot()
                    // One row when it fits, two when the window is narrow: nothing is squeezed or cut.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 16) {
                            titleBlock(items.count)
                            filterBar
                            Spacer(minLength: 12)
                            HBSearchField(text: $model.query.search, prompt: L("Search your games"))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            titleBlock(items.count)
                            HStack(spacing: 12) {
                                filterBar
                                Spacer(minLength: 8)
                                HBSearchField(text: $model.query.search, prompt: L("Search your games"), width: 190)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            titleBlock(items.count)
                            filterBar
                            HBSearchField(text: $model.query.search, prompt: L("Search your games"), width: 260)
                        }
                    }
                    if items.isEmpty {
                        emptyState.padding(20).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 18)
                    } else {
                        FillGrid(count: items.count, minimum: 160, spacing: 20, rowSpacing: 20, maximum: 240) {
                            ForEach(items) { item in
                                LibraryTile(item: item, entry: entry(for: item), onFocus: { model.hovered = $0 })
                            }
                        }
                    }
                }
                .hubPageFrame()
            }
        }
        .hbPageRoot()
        .navigationDestination(for: LibraryItem.self) { GameDetailView(passedItem: $0) }
    }

    private func entry(for item: LibraryItem) -> GameDBEntry? {
        state.gameDB.entry(for: item)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HBSegment(selection: $model.query.show, options: [(LibraryQuery.Show.installed, L("Installed")), (.all, L("All")), (.ready, L("Verified")), (.favorites, L("Favorites"))])
            Menu {
                Picker(L("Sort"), selection: $model.query.sort) {
                    ForEach(LibraryQuery.Sort.allCases, id: \.self) { Text(sortTitle($0)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sortTitle(model.query.sort), systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14).frame(height: HB.Metric.secondary)
                    .hbGlass(Capsule(), interactive: true)
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.bottles.isEmpty {
                if state.busy {
                    Text(L("KLYC-Box is preparing your Windows environment. Your games will appear here."))
                        .foregroundStyle(.secondary)
                } else if !state.damagedBottles.isEmpty {
                    // A present-but-unreadable environment must never look like a brand-new install:
                    // the games are likely still on disk, so point at recovery, not "prepare one".
                    Text(state.damagedBottles.count == 1
                         ? L("An environment needs attention — KLYC-Box can't read its settings, so its games aren't showing.")
                         : L("Some environments need attention — KLYC-Box can't read their settings, so their games aren't showing."))
                        .foregroundStyle(.secondary)
                    Button(L("Open Troubleshooting")) { state.settingsTab = .troubleshooting; openSettings() }
                        .buttonStyle(HBPrimaryButtonStyle())
                } else {
                    // An engine without an environment: an older install, or a stopped first run.
                    Text(L("One more step: KLYC-Box prepares a Windows environment for your games."))
                        .foregroundStyle(.secondary)
                    Button(L("Prepare it now")) { state.makeDefaultEnvironment() }
                        .buttonStyle(HBPrimaryButtonStyle())
                }
            } else if state.libraryItems.isEmpty {
                GettingStarted()
            } else if model.query.source == .epic && !state.epicSignedIn {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(L("Connect your Epic account")).font(.title3.weight(.semibold))
                    Text(L("Once it is connected, your Epic library shows up here and you can install and play from it."))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button(L("Connect Epic account…")) { state.showEpicSignIn = true }.buttonStyle(HBPrimaryButtonStyle())
                    Text(L("Your Epic sign-in goes to Epic only.")).font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                Text(L("Nothing matches these filters.")).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 24)
    }
}

struct FilterChip: View {
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(on ? HB.amber : HB.card))
                .overlay(Capsule().stroke(on ? HB.amber : HB.cardStroke))
                .foregroundStyle(on ? Color.white : .secondary)
        }
        .buttonStyle(.plain)
    }
}

/// The 2:3 portrait cover tile. Not GameCard: portrait geometry, title below the art,
/// click = detail, hover-play = launch.
struct LibraryTile: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    let entry: GameDBEntry?
    var width: CGFloat? = nil
    var onFocus: ((LibraryItem?) -> Void)? = nil
    @State private var hovering = false
    @State private var coverDropTargeted = false

    private var blocked: Bool { entry?.isBlocked == true }

    /// Under the title: its size, or that it is downloading (with how far), or that it is not installed.
    private var tileSubtitle: String {
        if let d = item.epicAppName.flatMap({ state.epicDownloads.download(for: $0) }) {
            return EpicDownloadText.percent(d.progress).map { d.state == .running ? String(format: L("Downloading %@"), $0) : String(format: L("Paused %@"), $0) }
                ?? (d.state == .running ? L("Starting…") : L("Paused"))
        }
        return item.sizeOnDisk > 0 ? ByteCountFormatter.string(fromByteCount: item.sizeOnDisk, countStyle: .file)
            : (item.installedAnywhere ? " " : L("Not installed"))
    }
    /// Anti-cheat blocks the Windows build only: a native Mac one plays.
    private var playable: Bool { (state.prefersMacBuild(item) || (item.installed && !blocked)) && !state.busy }

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    CoverArt(item: item)
                        .saturation(blocked && !item.installedOnMac ? 0.15 : (item.installedAnywhere ? 1 : 0.45))
                        .brightness(item.installedAnywhere ? 0 : -0.08)
                    if hovering && playable {
                        ZStack {
                            Color.black.opacity(0.25)
                            Button { hovering = false; state.play(item) } label: {
                                ZStack {
                                    Circle().fill(HB.lit).frame(width: 44, height: 44)
                                        .shadow(color: .black.opacity(0.45), radius: 9, y: 3)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(HB.ink)
                                        .offset(x: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity)
                    }
                    SourceBadge(source: item.source, mac: state.macSteamBuild(for: item))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                    if let appid = item.steamAppID, state.session(forAppID: appid) != nil {
                        Text(L("Running"))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(HB.good.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(6)
                    }
                    HStack(spacing: 5) {
                        if state.favorites.contains(item.id) {
                            Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(5).background(Circle().fill(HB.amber))
                        }
                        if !item.installedAnywhere {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
                    StatusPill(kind: state.statusKind(for: item))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(7)
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))   // hits stop where the cover is drawn, see CoverArt
                // An image dropped on the tile becomes the cover, so nobody has to walk a file
                // browser for it. Only images are claimed here, so a dropped
                // Windows program still reaches the window's own handler and runs.
                .onDrop(of: [.image], isTargeted: $coverDropTargeted) { providers in
                    state.acceptCoverDrop(providers, for: item)
                }
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(coverDropTargeted ? HB.amber : (hovering ? Color.white.opacity(0.95) : HB.cardStroke),
                            lineWidth: coverDropTargeted ? 2 : (hovering ? 3 : 1)))
                .scaleEffect(hovering ? 1.05 : 1)
                .shadow(color: .black.opacity(hovering ? 0.4 : 0.2), radius: hovering ? 12 : 5, y: 3)

                Text(state.displayTitle(item))
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(tileSubtitle)
                    .font(.system(size: 11.5)).foregroundStyle(item.epicAppName.flatMap { state.epicDownloads.download(for: $0) } != nil ? HB.amber : Color.secondary)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .onChange(of: hovering) { _, now in onFocus?(now ? item : nil) }
        .animation(HB.Motion.quick, value: hovering)
        // Continuous hover, not onHover: onHover only reports crossing the tile's edge, so a
        // game started from the play button took the screen with the pointer still inside, the
        // exit never came, and the play button stayed on that tile after coming back, while the
        // tile actually under the pointer stayed dark until it was left and re-entered
        //. Leaving the app also clears it.
        .onContinuousHover { phase in
            switch phase {
            case .active: if !hovering { hovering = true }
            case .ended: hovering = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            hovering = false
        }
        .help(Self.tooltip(entry?.notes) ?? item.title)
        // The rename field, on the tile being renamed only. A blank name is a reset.
        .alert(L("Rename"), isPresented: Binding(get: { state.renaming?.id == item.id },
                                                  set: { if !$0 { state.renaming = nil } })) {
            TextField(L("Name"), text: Binding(get: { state.renameText }, set: { state.renameText = $0 }))
            Button(L("Rename")) { state.rename(item, to: state.renameText) }
            Button(L("Cancel"), role: .cancel) { state.renaming = nil }
        } message: {
            Text(String(format: L("The store keeps calling it %@. Leave the field empty to go back to that name."), item.title))
        }
        .contextMenu {
            if let appid = item.steamAppID, let running = state.session(forAppID: appid) {
                Button(L("Stop")) { state.stopSession(running) }
            } else if playable { Button(L("Play")) { state.play(item) } }
            if MacAppStub.existing(for: item.title) != nil {
                Button(L("Remove the Mac app")) { state.removeMacApp(title: item.title) }
            } else if playable, item.installed, PlayLink.target(for: item) != nil {
                Button(L("Make a Mac app…")) { state.makeMacApp(for: item) }
            }
            if playable, item.installed, PlayLink.target(for: item) != nil {
                if MacAppStub.existingDesktopCopy(for: item.title) != nil {
                    Button(L("Remove from the Desktop")) { state.removeDesktopShortcut(for: item) }
                } else {
                    Button(L("Add to the Desktop")) { state.addDesktopShortcut(for: item) }
                }
            }
            Button(state.isFavorite(item) ? L("Remove from favorites") : L("Add to favorites")) { state.toggleFavorite(item) }
            if state.canImprove(item) { Button(L("Improve")) { state.improveAsk = item } }
            Button(L("Choose cover image…")) { state.chooseCover(for: item) }
            if state.coverStore.coverURL(for: item.id) != nil {
                Button(L("Reset cover")) { state.resetCover(for: item) }
            }
            Button(L("Rename…")) { state.beginRename(item) }
            if state.customNames[item.id] != nil {
                Button(L("Reset name")) { state.resetName(for: item) }
            }
            // A program someone added by hand leaves the library from its tile, not only from
            // the environment's programs list. Steam and Epic entries follow
            // their stores' libraries, so they have no such button.
            if item.source == .pin, let bottleName = item.bottleName,
               let bottle = state.bottles.first(where: { $0.name == bottleName }),
               let pin = bottle.settings.pins.first(where: { $0.id == item.pinID }) {
                Divider()
                Button(L("Remove from list"), role: .destructive) { state.removePin(pin, from: bottle) }
            }
            // Removing the game itself, not just the entry: asked for on r/macgaming because
            // there was nowhere to do it.
            if item.installed {
                Divider()
                Button(L("Uninstall…"), role: .destructive) { state.askUninstall(item) }
            }
        }
        .accessibilityLabel("\(item.title), \(item.source.rawValue)\(item.installedOnMac ? ", " + L("Installed in Steam for Mac") : item.installed ? "" : ", " + L("Not installed"))")
    }

    private var verdict: (String, Color)? { verdictLabel(entry?.status) }
}

/// Shared verdict mapping (was embedded in GameCard).
func verdictLabel(_ status: String?) -> (String, Color)? {
    switch status {
    case "verified-local": return (L("Verified"), HB.good)
    case "reported-upstream": return (L("Reported"), Color(red: 0.55, green: 0.70, blue: 0.90))
    case "community": return (L("Community"), HB.warn)
    case let s? where s.hasPrefix("blocked-"): return (L("Blocked"), HB.bad)
    default: return (L("Not tested"), Color.secondary)
    }
}

struct SourceBadge: View {
    let source: LibrarySource
    /// A native Mac build on Steam (MacSteamBuild): an Apple logo in front of the label, and the
    /// whole badge lit when Steam for Mac has it installed.
    var mac: MacSteamBuild? = nil
    private var label: String {
        switch source { case .steam: "STEAM"; case .epic: "EPIC"; case .pin: "EXE" }
    }
    private var lit: Bool { mac == .installed }
    var body: some View {
        HStack(spacing: 3) {
            if mac != nil { Image(systemName: "apple.logo").font(.system(size: 8, weight: .semibold)) }
            Text(label)
        }
            .font(.system(size: 8.5, weight: lit ? .bold : .medium).monospaced())
            .kerning(0.4)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(lit ? .white.opacity(0.92) : .black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(lit ? 0 : 0.18), lineWidth: 0.5))
            .foregroundStyle(lit ? .black : .white.opacity(0.92))
            .help(lit ? L("Installed in Steam for Mac") : mac != nil ? L("Native Mac build on Steam") : "")
    }
}

/// Portrait cover with a fallback chain: tall art → wide art scaled to fill → placeholder.
/// AsyncImage can't chain URLs itself, so the state walks the chain on failure. Steam's
/// library_600x900 404s for some older appids — the fallback is not optional polish.
struct CoverArt: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    @State private var stage = 0

    private var url: URL? {
        switch stage {
        case 0: item.artworkTall ?? item.artworkWide
        case 1: item.artworkTall != nil ? item.artworkWide : nil
        default: nil
        }
    }

    var body: some View {
        // The tile takes the size its parent proposes; the image lives in an overlay, so its
        // own dimensions never take part in layout and the crop is a plain clip. The previous
        // GeometryReader-and-frame form rendered nothing on a macOS 27 beta for any image whose
        // aspect was not exactly 2:3 (#64): a chosen cover, or Steam's wide fallback art.
        Color.clear
            .overlay {
                // A user-chosen cover always wins (coverVersion invalidates after changes).
                if let custom = state.coverStore.coverURL(for: item.id),
                   let image = NSImage(contentsOf: custom) {
                    Image(nsImage: image).resizable().scaledToFill().id(state.coverVersion)
                } else if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder.onAppear { stage += 1 }
                        default:
                            Rectangle().fill(HB.card)
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            // clipped() trims the drawing, not hit testing: a wide cover scaled to fill (Steam's
            // fallback art, Half-Life 2's demo, Heartopia) still caught the pointer over the
            // neighbouring tiles, so the tile to the left showed the next one's play button and
            // its clicks went nowhere (seen on an M4, 2026-10-01). Hits stop at the visible cover.
            .contentShape(Rectangle())
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [HB.card, HB.ground], startPoint: .top, endPoint: .bottom)
            Text(String(item.title.prefix(1)))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.quaternary)
        }
    }
}

extension LibraryTile {
    /// A tooltip is a glance, not the whole entry: the first sentence of the notes, capped.
    static func tooltip(_ notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        let first = notes.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? notes
        let sentence = first.trimmingCharacters(in: .whitespaces) + "."
        return sentence.count <= 160 ? sentence : String(sentence.prefix(157)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

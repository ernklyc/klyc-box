import AVKit
import SwiftUI
import KLYCKit

/// A store page for a game you may not own: trailers, pictures, what players think, what it needs, and how it is likely
/// to run on this Mac, from the compatibility database and from your own sessions.
struct StoreGameView: View {
    @Environment(AppState.self) private var state
    let route: StoreRoute
    @State private var playing: StoreInfo.Trailer?
    /// One player per chosen trailer: building it in the body would restart the video on every redraw.
    @State private var player: AVPlayer?
    @State private var tab = 0
    @State private var platform = 0
    @State private var model = StoreGameModel()
    @State private var aboutOpen = false
    @State private var reviewsPage: WorkshopModsCard.SheetPage?

    private var info: StoreInfo? { state.storeInfo[route.appid] }
    private var owned: LibraryItem? { state.libraryItems.first { $0.steamAppID == route.appid } }

    var body: some View {
        ZStack {
            BottleBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HubHeaderSlot()
                    header
                    if let info {
                        if let t = info.shortDescription { Text(t).font(.callout).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                        media(info)
                        card { macCard }
                        tagsRow
                        card { reviewsCard }
                        if let about = info.about, !about.isEmpty { card { aboutCard(about) } }
                        card { detailsCard(info) }
                        card { requirements(info) }
                        if !model.dlc.isEmpty { card { dlcCard } }
                        card { WorkshopModsCard(appid: route.appid, name: info.name, hasWorkshop: info.hasWorkshop) }
                        if !model.news.isEmpty { card { newsCard } }
                        if !model.similar.isEmpty { similarShelf }
                    } else {
                        VStack(alignment: .leading, spacing: HB.Space.m) {
                            SkeletonBlock(radius: 12).frame(height: 70)
                            SkeletonBlock(radius: 14).frame(maxWidth: .infinity).frame(height: 300)
                            SkeletonBlock(radius: 14).frame(maxWidth: .infinity).frame(height: 110)
                        }
                    }
                }
                .hubPageFrame()
            }
        }
        .hbPageRoot()
        .onDisappear { player?.pause() }
        .sheet(item: $reviewsPage) { WebSheet(title: "\($0.title) · \(route.name)", url: $0.url).hbSheet() }
        .task(id: route.appid) {
            // The page's own facts first: the add-ons and similar games below are found from them.
            if state.storeInfo[route.appid] == nil, let loaded = await SteamStoreInfo.load(route.appid, paths: state.paths) { state.storeInfo[route.appid] = loaded }
            _ = await StoreCategories.load()
            await model.load(appid: route.appid, info: state.storeInfo[route.appid])
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
    }

    // MARK: pieces

    private var cover: some View {
        AsyncImage(url: URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(route.appid)/header.jpg"), transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image { image.resizable().scaledToFit() } else { Color.white.opacity(0.06).aspectRatio(460.0 / 215.0, contentMode: .fit) }
        }
        .frame(maxWidth: 460).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// The picture beside the facts when the window is wide, above them when it is narrow.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { cover.frame(width: 420); facts }
            VStack(alignment: .leading, spacing: HB.Space.m) { cover; facts }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(info?.name ?? route.name).font(.system(size: 32, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
            HStack(spacing: 10) {
                if let price = info?.price { Text(price).font(.system(size: 15, weight: .semibold)) }
                SupportLine(appid: route.appid, native: info?.mac ?? false)
                if let info { ForEach(info.genres.prefix(3), id: \.self) { g in Text(g).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).frame(height: 24).hbGlass(Capsule()) } }
                if let d = info?.releaseDate { Label(d, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 10) {
                if let owned {
                    NavigationLink(value: owned) { Label(L("In your library"), systemImage: "checkmark.circle.fill") }.buttonStyle(HBSecondaryButtonStyle())
                }
                Button {
                    if let url = URL(string: "https://store.steampowered.com/app/\(route.appid)/") { NSWorkspace.shared.open(url) }
                } label: { Label(L("Open in the Steam store"), systemImage: "safari") }
                    .buttonStyle(HBPrimaryButtonStyle())
                    .help(L("Buying and adding to your wishlist happen in the browser."))
            }
        }
    }

    @ViewBuilder private func media(_ info: StoreInfo) -> some View {
        let trailers = info.trailers ?? [], shots = info.screenshots ?? []
        if !trailers.isEmpty || !shots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let player {
                    VideoPlayer(player: player).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HScroll {
                    HStack(spacing: 10) {
                        ForEach(trailers.prefix(4), id: \.stream) { t in
                            Button { playing = t; player?.pause(); player = AVPlayer(url: t.stream); player?.play() } label: {
                                ZStack {
                                    StoreThumb(url: t.thumbnail)
                                    Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(.white.opacity(0.9))
                                }.frame(width: 240, height: 135).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                        ForEach(Array(shots.prefix(10).enumerated()), id: \.offset) { _, url in
                            Button { NSWorkspace.shared.open(url) } label: {
                                StoreThumb(url: url)
                                    .frame(width: 240, height: 135).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// What is known on a Mac, each fact with its source: the store's Mac build flag, the Windows build under Wine by our records,
    /// and what this Mac itself saw. Never invented: a game nobody has tried says so.
    private var macCard: some View {
        let support = GameSupport.resolve(entry: state.gameDB.byAppID[route.appid], local: state.localVerdicts["steam:\(route.appid)"], nativeMac: info?.mac ?? false)
        let local = state.localVerdicts["steam:\(route.appid)"]
        return VStack(alignment: .leading, spacing: 10) {
            HB.eyebrow(L("On your Mac"))
            row("applelogo", support.native ? L("The Steam store lists a Mac build.") : L("No Mac build: only the Windows build, through Wine."), support.native ? HB.good : Color.secondary)
            switch support.wine {
            case .tested: row("checkmark.seal.fill", L("The Windows build was tested and runs under KLYC-Box."), HB.good)
            case .reported: row("person.2.fill", L("Players report that the Windows build runs; this project has not tested it."), Color(red: 0.50, green: 0.70, blue: 1.0))
            case .blocked: row("nosign", support.native ? L("The Windows build is blocked under Wine (use the Mac build).") : L("The Windows build does not run under Wine."), HB.bad)
            case .untested: row("circle.dashed", L("Nobody has reported on the Windows build under KLYC-Box yet."), Color.secondary)
            }
            if let local { row(local.works ? "checkmark.circle.fill" : "xmark.octagon.fill", local.works ? L("Tested on this Mac: it works.") : L("Tested on this Mac: it did not work."), local.works ? HB.good : HB.bad) }
            if let atlas = state.atlas[route.appid] {
                Divider().padding(.vertical, 2)
                HB.eyebrow(L("Atlas"))
                AtlasRows(appid: route.appid, entry: atlas)
            }
            if let src = support.source, !support.seenHere {
                Text(String(format: L("Source: %@"), src) + ((support.date?.isEmpty == false) ? " · " + String(format: L("Last confirmed %@."), support.date ?? "") : ""))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private func row(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HB.eyebrow(L("What players say"))
            if let s = model.summary, s.total > 0 {
                HStack(spacing: 12) {
                    Text("%\(s.percent)").font(.system(size: 26, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(.system(size: 14, weight: .semibold))
                        Text(String(format: L("%d reviews"), s.total)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.reviews.prefix(3)) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: r.positive ? "hand.thumbsup.fill" : "hand.thumbsdown.fill").foregroundStyle(r.positive ? HB.good : HB.amber)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.text).font(.callout).foregroundStyle(.white.opacity(0.8)).lineLimit(4)
                            Text(String(format: L("%d h played"), r.hours)).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                Button {
                    if let url = URL(string: "https://steamcommunity.com/app/\(route.appid)/reviews/") { reviewsPage = .init(title: L("Reviews"), url: url) }
                } label: { Label(L("Read all reviews"), systemImage: "text.bubble") }
                    .buttonStyle(HBCompactButtonStyle())
            } else if !model.reviewsLoaded {
                // Not here yet (or the store did not answer): a placeholder, not a verdict of "no reviews".
                VStack(alignment: .leading, spacing: 8) { SkeletonBlock(radius: 6).frame(width: 160, height: 26); SkeletonBlock(radius: 5).frame(height: 12); SkeletonBlock(radius: 5).frame(width: 240, height: 12) }
            } else {
                Text(L("No reviews yet.")).foregroundStyle(.secondary)
            }
        }
    }

    private func requirements(_ info: StoreInfo) -> some View {
        let reqs = platform == 0 ? info.pc : info.macRequirements
        let text = tab == 0 ? reqs.minimum : reqs.recommended
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HBSegment(selection: $platform, options: [(0, "Windows"), (1, "Mac")])
                HBSegment(selection: $tab, options: [(0, L("Minimum")), (1, L("Recommended"))])
                Spacer(minLength: 0)
            }
            if let text {
                Text(text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                let free = (try? state.paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
                ForEach(SpecCheck.compare(text, ramBytes: ProcessInfo.processInfo.physicalMemory, freeDiskBytes: free, labels: (L("Memory"), L("Disk space"))), id: \.label) { c in
                    HStack(spacing: 8) {
                        Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(c.ok ? HB.good : HB.amber)
                        Text("\(c.label): \(c.have) · \(String(format: L("needs %@"), c.need))").font(.callout)
                    }
                }
            } else {
                Text(L("The store lists no requirements.")).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: more of the page

    private var tagsRow: some View {
        let names = Dictionary(uniqueKeysWithValues: StoreCategories.all.map { ($0.id, $0.name) })
        return FlowLayout {
            ForEach(model.tags, id: \.self) { id in
                if let name = names[id] {
                    NavigationLink(value: StoreResultsRoute(filters: StoreFilters(tag: id), title: name)) {
                        Text(name).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(Color.white.opacity(0.09)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func aboutCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HB.eyebrow(L("About this game"))
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.82)).lineLimit(aboutOpen ? nil : 6).fixedSize(horizontal: false, vertical: true)
            if text.count > 420 { Button(aboutOpen ? L("Show less") : L("Show more")) { withAnimation(HB.Motion.standard) { aboutOpen.toggle() } }.buttonStyle(HBTextButtonStyle()).font(.caption) }
        }
    }

    private func detailsCard(_ info: StoreInfo) -> some View {
        func row(_ title: String, _ value: String?) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                Text(value ?? "").font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HB.eyebrow(L("Details"))
            if !info.developers.isEmpty { row(L("Developer"), info.developers.joined(separator: ", ")) }
            if let p = info.publishers, !p.isEmpty { row(L("Publisher"), p.joined(separator: ", ")) }
            if let d = info.releaseDate { row(L("Release date"), d) }
            if let langs = info.languages, !langs.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Languages")).font(.callout).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(info.hasTurkish ? L("Turkish is supported") : L("No Turkish"), systemImage: info.hasTurkish ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.callout.weight(.semibold)).foregroundStyle(info.hasTurkish ? HB.good : Color.secondary)
                        Text(langs.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let n = info.achievementsTotal { row(L("Achievements"), String(n)) }
            if let c = info.controllerSupport { row(L("Controller"), c == "full" ? L("Full support") : L("Partial support")) }
            if let r = info.recommendations { row(L("Recommended by"), String(format: L("%d players"), r)) }
            if let m = info.metacritic { row("Metacritic", String(m)) }
            if let site = info.website { HStack { Text(L("Website")).font(.callout).foregroundStyle(.secondary).frame(width: 130, alignment: .leading); Link(site.host ?? site.absoluteString, destination: site).font(.callout); Spacer(minLength: 0) } }
        }
    }

    private var dlcCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HB.eyebrow(L("Add-ons"))
            ForEach(model.dlc) { d in
                HStack(spacing: 10) {
                    Text(d.name).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    if d.onSale, let o = d.originalText { Text(o).strikethrough().font(.caption).foregroundStyle(.secondary) }
                    if let f = d.finalText { Text(f).font(.callout.weight(.medium)) }
                }
            }
            Text(L("Add-ons are bought on Steam.")).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var newsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("Latest news"))
            ForEach(model.news.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        Spacer(minLength: 8)
                        Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !item.text.isEmpty { Text(item.text).font(.callout).foregroundStyle(.white.opacity(0.75)).lineLimit(3) }
                    if let url = item.url { Button(L("Read")) { NSWorkspace.shared.open(url) }.buttonStyle(HBTextButtonStyle()).font(.caption) }
                }
            }
        }
    }

    private var similarShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("Similar games"))
            StoreGrid(cards: model.similar)
        }
    }
}

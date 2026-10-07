import SwiftUI
import KLYCKit

/// A Steam game's page of facts: description, platforms, requirements checked against this Mac, who plays it now,
/// and the Steam hours.
struct SteamInfoPanel: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    @State private var tab = 0   // 0 minimum, 1 recommended
    @State private var platform = 0   // 0 Windows, 1 Mac

    var body: some View {
        if let appid = item.steamAppID {
            let info = state.storeInfo[appid]
            VStack(alignment: .leading, spacing: 16) {
                HB.eyebrow(L("About this game"))
                if let info {
                    if let text = info.shortDescription { Text(text).font(.callout).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
                    facts(info)
                    playing(appid)
                    requirements(info)
                    WorkshopModsCard(appid: appid, name: info.name, hasWorkshop: info.hasWorkshop)
                } else {
                    VStack(alignment: .leading, spacing: 10) { SkeletonBlock(radius: 5).frame(height: 14); SkeletonBlock(radius: 5).frame(width: 260, height: 14); SkeletonBlock(radius: 9).frame(width: 180, height: 24) }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16)
            .task(id: appid) { state.loadStoreInfo(appid); state.loadAchievements(appid); state.loadNews(appid) }

            if let ach = state.achievementsByApp[appid] { achievements(ach).padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16) }
            if let news = state.steamNews[appid], !news.isEmpty { newsCard(news).padding(18).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 16) }
        }
    }

    private func achievements(_ a: SteamAchievements) -> some View {
        let done = a.unlockedCount, total = a.items.count
        let recent = a.items.filter(\.unlocked).sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }.prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            HB.eyebrow(L("Achievements"))
            HStack(spacing: 12) {
                Text("\(done) / \(total)").font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(HB.amber.opacity(0.85)).frame(width: max(6, geo.size.width * CGFloat(done) / CGFloat(max(total, 1))))
                    }
                }.frame(height: 8)
            }
            ForEach(Array(recent), id: \.id) { item in
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundStyle(HB.amber)
                    Text(item.name).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    if let d = item.unlockedAt { Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text(L("Read from Steam's own files on this Mac; what Steam has synced so far."))
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func newsCard(_ items: [SteamNewsItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HB.eyebrow(L("Latest news"))
            ForEach(items.prefix(3)) { item in
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

    private func facts(_ info: StoreInfo) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips(info); Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) { chips(info) }
        }
    }

    @ViewBuilder private func chips(_ info: StoreInfo) -> some View {
        platformChip("Windows", on: info.windows, symbol: "pc")
        platformChip("Mac", on: info.mac, symbol: "applelogo")
        platformChip("Linux", on: info.linux, symbol: "terminal")
        ForEach(info.genres.prefix(3), id: \.self) { g in Text(g).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).frame(height: 24).hbGlass(Capsule()) }
        if let date = info.releaseDate { Label(date, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
        if let score = info.metacritic { Label(String(score), systemImage: "star.fill").font(.caption).foregroundStyle(.secondary).help("Metacritic") }
        if let price = info.price { Text(price).font(.caption).foregroundStyle(.secondary) }
    }

    private func platformChip(_ name: String, on: Bool, symbol: String) -> some View {
        Label(name, systemImage: symbol).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(height: 24)
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.35))
            .background(Capsule().fill(on ? HB.amber.opacity(0.35) : Color.white.opacity(0.05)))
    }

    @ViewBuilder private func playing(_ appid: Int) -> some View {
        let friends = state.friendsPlaying(appid: appid)
        if !friends.isEmpty {
            Label(String(format: L("Playing now: %@"), friends.map(\.name).joined(separator: ", ")), systemImage: "person.2.fill")
                .font(.callout).foregroundStyle(HB.good)
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
                let checks = SpecCheck.compare(text, ramBytes: ProcessInfo.processInfo.physicalMemory, freeDiskBytes: freeDisk(),
                                               labels: (L("Memory"), L("Disk space")))
                if !checks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HB.eyebrow(L("Your Mac"))
                        ForEach(checks, id: \.label) { c in
                            HStack(spacing: 8) {
                                Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(c.ok ? HB.good : HB.amber)
                                Text("\(c.label): \(c.have) · \(String(format: L("needs %@"), c.need))").font(.callout)
                            }
                        }
                        Text(L("The graphics card is not compared: a Windows card name says nothing about an Apple chip. See the results of other Macs above."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(platform == 1 ? L("The store lists no Mac requirements for this game.") : L("The store lists no requirements.")).foregroundStyle(.secondary)
            }
        }
    }

    private func freeDisk() -> Int64 {
        let url = state.paths.home
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
    }
}

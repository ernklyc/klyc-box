import SwiftUI
import KLYCKit

/// What is known about a game on a Mac, as plain chips under its picture: whether the store lists a Mac build, and how the Windows
/// build fares under Wine by our records. Every game gets one, "not tested" included: silence would look like a verdict.
/// Dark solid chips with an icon and a word each, so nothing depends on telling two colours apart.
struct SupportLine: View {
    @Environment(AppState.self) private var state
    let appid: Int
    /// The store lists a Mac build (certain: it is the store's own flag).
    let native: Bool
    var compact = false

    var support: GameSupport {
        GameSupport.resolve(entry: state.gameDB.byAppID[appid], local: state.localVerdicts["steam:\(appid)"], nativeMac: native)
    }

    var body: some View {
        let s = support
        HStack(spacing: 6) {
            if s.native { chip("applelogo", L("Mac build"), .white.opacity(0.9), L("The Steam store lists a Mac build of this game.")) }
            wineChip(s)
            // Only where the page has room, and not beside "Does not run", which already says why.
            if !compact, s.wine != .blocked, let names = anticheatNames {
                chip("shield.lefthalf.filled", L("Anti-cheat"), HB.amber,
                     String(format: L("Uses %@. Anti-cheats like this often refuse to start under Wine on a Mac, and nobody has tested this game here."), names)
                        + "\n" + L("Source: Are We Anti-Cheat Yet?"))
            }
        }
    }

    private var anticheatNames: String? {
        let names = state.gameDB.anticheatNotice(appid: appid)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    @ViewBuilder private func wineChip(_ s: GameSupport) -> some View {
        switch s.wine {
        case .tested: chip("checkmark.seal.fill", L("Tested"), HB.good, help(L("Tested: it runs on a Mac under KLYC-Box."), s))
        case .reported: chip("person.2.fill", L("Player reports"), Color(red: 0.50, green: 0.70, blue: 1.0), help(L("Players report that the Windows build runs; not tested by this project."), s))
        case .blocked:
            let why = s.blockReason == "publisher" ? L("its publisher") : (s.blockReason == "anticheat" ? L("its anti-cheat") : L("a failed test here"))
            chip("nosign", s.native ? L("Windows build blocked") : L("Does not run"), HB.bad,
                 help(String(format: L("The Windows build does not run under Wine: %@ stops it."), why), s))
        case .untested: untestedChip()
        }
    }

    /// Nobody tested it, but the Atlas may still know something: players on other setups, an anti-cheat block, or a prediction.
    @ViewBuilder private func untestedChip() -> some View {
        let purple = Color(red: 0.72, green: 0.58, blue: 1.0)
        let entry = state.atlas[appid]
        switch (entry?.tier, entry?.p) {
        case (.predicted?, "likely"?): chip("sparkles", L("Likely to run"), purple, L("A prediction, not a test: it will probably run."))
        case (.predicted?, "maybe"?): chip("sparkles", L("May run"), purple, L("A prediction, not a test: unclear whether it runs."))
        case (.predicted?, "unlikely"?): chip("sparkles", L("Unlikely to run"), purple, L("A prediction, not a test: a slim chance it runs."))
        case (.reported?, _): chip("person.2.fill", L("Player reports"), Color(red: 0.50, green: 0.70, blue: 1.0), L("Reported by players."))
        case (.blocked?, _): chip("nosign", L("Does not run"), HB.bad, L("It does not run on a Mac: its anti-cheat or its publisher stops it."))
        default: chip("circle.dashed", L("Not tested"), Color.white.opacity(0.62), L("Nobody has reported on this game under KLYC-Box yet."))
        }
    }

    private func help(_ text: String, _ s: GameSupport) -> String {
        var out = text
        if s.seenHere { out += "\n" + L("Your own result on this Mac.") }
        else if let src = s.source { out += "\n" + String(format: L("Source: %@"), src) }
        if let d = s.date, !d.isEmpty { out += "\n" + String(format: L("Last confirmed %@."), d) }
        return out
    }

    private func chip(_ symbol: String, _ text: String, _ tint: Color, _ tooltip: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: compact ? 10 : 11, weight: .bold)).foregroundStyle(tint)
            Text(text).font(.system(size: compact ? 11 : 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
        }
        .padding(.horizontal, 8).frame(height: compact ? 20 : 22)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(tint.opacity(0.75), lineWidth: 1))
        .fixedSize()
        .help(tooltip)
    }
}

import SwiftUI
import KLYCKit

/// Settings → About: what KLYC-Box is, where its guide and source live, and whose work it stands on (the list is `Credits`).
struct AboutPane: View {
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    var body: some View {
        ScrollView { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: HB.Space.xl) {
            header
            Text(L("KLYC-Box runs many Windows games and apps on a Mac. The guide on our site shows which games are tested, reported by players, or likely to run, and the app reads the same data."))
                .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            links
            VStack(alignment: .leading, spacing: HB.Space.m) {
                Text(L("Built on the work of")).font(.system(size: 17, weight: .bold, design: .rounded))
                ForEach(Credits.entries, id: \.name) { entry in credit(entry) }
            }
            VStack(alignment: .leading, spacing: HB.Space.s) {
                Text(L(Credits.ownership)).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(L(Credits.affiliation)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(L("Thank you to everyone above, and to every person who reported a problem or tested a game.")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(HB.Space.m).frame(maxWidth: .infinity, alignment: .leading).background(flat)
        }
        .padding(.vertical, 20).padding(.leading, 20).padding(.trailing, HB.Metric.margin)
    }

    /// A flat card: the credits are a long list, and a glass effect on each one made the page heavy.
    private var flat: some View {
        RoundedRectangle(cornerRadius: HB.Metric.radius).fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: HB.Metric.radius).stroke(Color.white.opacity(0.08)))
    }

    private var header: some View {
        HStack(spacing: HB.Space.l) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 84, height: 84)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("KLYC-Box").font(.system(size: 28, weight: .heavy, design: .rounded))
                Text(String(format: L("Version %@"), version)).font(.callout).foregroundStyle(.secondary)
                Text(L("Windows games and apps on your Mac. Free and open source.")).font(.callout).foregroundStyle(HB.amber)
            }
        }
    }

    private var links: some View {
        FlowLayout {
            link(L("Website and game guide"), "safari", Credits.guideSite)
            link(L("Source code, GPL-3.0"), "chevron.left.forwardslash.chevron.right", Credits.sourceSite)
            link(L("My other work and the ways to reach me"), "person", Credits.authorSite)
            if let privacy = AtlasSite.privacyPage() { link(L("Privacy details"), "lock", privacy) }
            Button { NSWorkspace.shared.open(BugReport.url(version: version)) } label: { Label(L("Report a Problem…"), systemImage: "exclamationmark.bubble") }
                .buttonStyle(HBSecondaryButtonStyle())
        }
    }

    private func link(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: { Label(title, systemImage: symbol) }.buttonStyle(HBSecondaryButtonStyle())
    }

    private func credit(_ e: CreditEntry) -> some View {
        Button { NSWorkspace.shared.open(e.url) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(e.name).font(.system(size: 14, weight: .semibold))
                    Text(e.license).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(L(e.role)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(HB.Space.m).frame(maxWidth: .infinity, alignment: .leading).background(flat)
        }
        .buttonStyle(.plain)
    }
}

/// The language row of General settings: a choice that takes effect after a restart (the strings are read at use, but many screens
/// keep what they built), with a button to do it now.
struct LanguageRow: View {
    @AppStorage(AppLanguage.defaultsKey) private var choice = AppLanguage.auto.rawValue
    @State private var shown = AppLanguage.active

    private var changed: Bool { AppLanguage.code() != shown }

    var body: some View {
        VStack(alignment: .leading, spacing: HB.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: HB.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Language")).font(.system(size: 14, weight: .semibold))
                    Text(L("The language of the whole app. Restart KLYC-Box to apply a change.")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Picker("", selection: $choice) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 190)
            }
            if changed {
                HStack { Spacer(); Button(L("Restart now")) { Self.relaunch() }.buttonStyle(HBPrimaryButtonStyle()) }
            }
        }
        .padding(HB.Space.m).hbCard(radius: HB.Metric.radius)
    }

    /// Starts a new copy of the app a moment after this one has quit, so the language is read fresh.
    @MainActor static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open -n \"$1\"", "sh", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

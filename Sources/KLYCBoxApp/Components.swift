import SwiftUI
import KLYCKit

// MARK: - Design system: the pieces every screen is built from

/// A game's status as a small pill: same height, same border, never wraps.
struct StatusPill: View {
    enum Kind { case ready, reported, community, untested, blocked, problems }
    let kind: Kind

    static func kind(forStatus status: String?) -> Kind {
        switch status {
        case "verified-local": return .ready
        case "reported-upstream": return .reported
        case "community": return .community
        case let s? where s.hasPrefix("blocked-"): return .blocked
        default: return .untested
        }
    }

    private var color: Color {
        switch kind {
        case .ready: return Color(red: 0.44, green: 0.86, blue: 0.60)
        case .reported, .community: return Color(red: 0.72, green: 0.68, blue: 0.70)
        case .untested: return Color(red: 0.94, green: 0.73, blue: 0.35)
        case .blocked: return Color(red: 1.0, green: 0.58, blue: 0.52)
        case .problems: return Color(red: 1.0, green: 0.70, blue: 0.45)
        }
    }
    private var symbol: String {
        switch kind {
        case .ready: return "checkmark.circle.fill"
        case .reported: return "doc.text.fill"
        case .community: return "person.2.fill"
        case .untested: return "testtube.2"
        case .blocked: return "nosign"
        case .problems: return "exclamationmark.triangle.fill"
        }
    }
    private var label: String {
        switch kind {
        case .ready: return L("Verified")
        case .reported: return L("Reported")
        case .community: return L("Community")
        case .untested: return L("Untested")
        case .blocked: return L("Won't run")
        case .problems: return L("Has problems")
        }
    }

    /// What the pill means, since the word alone does not say it is about running, not installing.
    private var explanation: String {
        switch kind {
        case .ready: return L("Verified to run on a Mac, by this project's own test or by your own result. It says nothing about whether the game is installed.")
        case .reported: return L("Named as working in the graphics layer's release notes; not verified by this project yet.")
        case .community: return L("Players report that it runs; not verified by this project yet.")
        case .untested: return L("Nobody has tested this game here yet.")
        case .blocked: return L("It does not run on a Mac: its anti-cheat or its publisher stops it.")
        case .problems: return L("You marked this game as having problems on this Mac.")
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .bold))
            Text(label).font(.system(size: 11, weight: .semibold))
        }
        .help(explanation)
        .lineLimit(1).fixedSize()
        .foregroundStyle(color)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.32), lineWidth: 1))
    }
}

/// The main action of a screen: a soft white capsule with dark text.
struct HBPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1).fixedSize()
            .foregroundStyle(HB.ink)
            .padding(.horizontal, 20).frame(height: HB.Metric.primary)
            .background(Capsule().fill(HB.lit.opacity(configuration.isPressed ? 0.82 : 0.96)))
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Every other button: a plain Liquid Glass capsule.
struct HBSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .lineLimit(1).fixedSize()
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, 16).frame(height: HB.Metric.secondary)
            .hbGlass(Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}

extension View {
    /// A flat card: a faint fill and one hairline, the same everywhere.
    func hbCard(radius: CGFloat = 12) -> some View {
        self.hbGlass(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

/// A small card with a label, a value and a line of detail: Status, Setting, Performance.
struct InfoCard: View {
    let symbol: String
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = .secondary
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).kerning(1.1).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 16, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .topLeading)   // cards side by side share the tallest one's height
        .hbCard()
    }
}

// MARK: - First-run "where are your games"

struct GettingStarted: View {
    @Environment(AppState.self) private var state

    /// Where your games are is a question anyone can answer (UX plan §3.2); Steam is not
    /// installed unasked, and a GOG or standalone user never waits for its first boot.
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            VStack(spacing: 6) {
                Text(L("Where are your games?")).font(.title.weight(.semibold))
                Text(L("Pick one to start. You can add the others any time.")).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: HB.Space.m) {
                sourceCard(symbol: "gamecontroller.fill", accent: true, title: L("Steam"),
                           text: L("Install Steam and sign in. Your Steam library shows up here. Its first start takes 15 to 25 minutes."),
                           button: state.defaultBottle.map(state.steamInstalled) == true ? L("Open Steam") : L("Install Steam")) { state.installSteam() }
                sourceCard(symbol: "bag.fill", accent: false, title: L("Epic Games"),
                           text: L("Connect your Epic account. Your games install straight into KLYC-Box."),
                           button: L("Connect Epic")) { state.showEpicSignIn = true }
                sourceCard(symbol: "folder.fill", accent: false, title: L("A Windows program I have"),
                           text: L("An installer or game from your Mac. Or drop it onto this window."),
                           button: L("Choose a file…")) { state.chooseProgramToRun() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    func sourceCard(symbol: String, accent: Bool, title: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title3)
                .frame(width: 42, height: 42)
                .background(Circle().fill(accent ? HB.lit : Color.white.opacity(0.08)))
                .foregroundStyle(accent ? HB.ink : Color.secondary)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if accent {
                Button(button, action: action).buttonStyle(HBPrimaryButtonStyle()).disabled(state.busy)
            } else {
                Button(button, action: action).buttonStyle(HBSecondaryButtonStyle()).disabled(state.busy)
            }
        }
        .padding(18)
        .frame(width: 250, height: 230, alignment: .topLeading)
        .hbCard(radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent ? HB.amber.opacity(0.5) : HB.cardStroke))
    }
}

/// A segmented control in the app's style: a glass capsule, the chosen segment lit white.
struct HBSegment<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { withAnimation(HB.Motion.quick) { selection = option.0 } } label: {
                    // The width is the semibold width for every option, chosen or not: choosing one must not push its neighbours sideways.
                    Text(option.1).font(.system(size: 13, weight: .semibold)).opacity(0)
                        .overlay(Text(option.1)
                            .font(.system(size: 13, weight: selection == option.0 ? .semibold : .regular))
                            .foregroundStyle(selection == option.0 ? HB.ink : Color.white.opacity(0.7)))
                        .padding(.horizontal, 16).frame(height: 32)
                        .background(Capsule().fill(selection == option.0 ? HB.lit.opacity(0.95) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .hbGlass(Capsule())
    }
}

// MARK: - Key art

/// The game's own wide art, full bleed, darkened where text sits. This is what Liquid Glass refracts.
struct HeroBackdrop: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem?
    /// Extra black over the art, for screens with more text than the home screen has.
    var dim: Double = 0
    /// Blur over the art, for screens where covers and text sit on top of it.
    var blur: CGFloat = 0

    var body: some View {
        ZStack {
            HB.ground
            if let item { HeroArt(item: item).blur(radius: blur).id(item.id).transition(.opacity) }
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55), .black.opacity(0.92)],
                           startPoint: UnitPoint(x: 0.5, y: 0.25), endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.70), .black.opacity(0.0)],
                           startPoint: .leading, endPoint: UnitPoint(x: 0.62, y: 0.5))
            RadialGradient(colors: [HB.amber.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 760)
        }
        .overlay(Color.black.opacity(dim))
        .animation(HB.Motion.slow, value: item?.id)
        .ignoresSafeArea()
    }
}

struct HeroArt: View {
    let item: LibraryItem
    /// A very slow push-in while the art is on screen; it restarts when the game changes.
    @State private var zoomed = false

    private var heroURL: URL? {
        item.steamAppID.flatMap { URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\($0)/library_hero.jpg") }
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let heroURL {
                    AsyncImage(url: heroURL) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() } else { fallback }
                    }
                } else { fallback }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .scaleEffect(zoomed ? 1.06 : 1.0)
            .clipped()
            .onAppear { withAnimation(.easeOut(duration: 16)) { zoomed = true } }
        }
    }

    @ViewBuilder private var fallback: some View {
        AsyncImage(url: item.artworkWide ?? item.artworkTall) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill().blur(radius: 6) } else { Color.clear }
        }
    }
}

/// The toolbar's section switcher: a glass capsule with the chosen section lit.
struct HBTabs: View {
    @Environment(AppState.self) private var state
    @Binding var selection: AppSection
    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases.filter { $0 != .settings }) { s in
                Button { UISound.play(.select); selection = s } label: {
                    HStack(spacing: 6) {
                        Text(s.title).lineLimit(1).fixedSize()
                        // Something is downloading, installing or being improved: say so where it can be found.
                        if s == .downloads, state.busy { Circle().fill(HB.amber).frame(width: 7, height: 7) }
                    }
                        .font(.system(size: 13, weight: selection == s ? .semibold : .regular))
                        .foregroundStyle(selection == s ? HB.ink : Color.secondary)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(selection == s ? HB.lit.opacity(0.95) : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
    }
}

extension View {
    /// Lets key art run under the window toolbar (macOS 15 and later).
    @ViewBuilder func hbToolbarClear() -> some View {
        if #available(macOS 15.0, *) { self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar) } else { self }
    }
}

/// Small glass capsule for buttons inside panels, settings and sheets.
struct HBCompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1).fixedSize()
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, 12).frame(height: HB.Metric.compact)
            .hbGlass(Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Group boxes become glass cards.
struct HBGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hbCard(radius: 16)
    }
}

extension View {
    /// Everything a sheet needs to look like the rest of the app.
    func hbSheet() -> some View {
        self
            .background(BottleBackdrop())
            .preferredColorScheme(.dark)
            .buttonStyle(HBCompactButtonStyle())
            .groupBoxStyle(HBGroupBoxStyle())
            .scrollContentBackground(.hidden)
            .tint(HB.amber)
            .hbToasts()   // a sheet covers the window's own, so confirmations from inside it need their own
    }
    /// Panels inside a screen: compact glass buttons and glass group boxes.
    func hbPanel() -> some View {
        self.buttonStyle(HBCompactButtonStyle()).groupBoxStyle(HBGroupBoxStyle()).scrollContentBackground(.hidden).tint(HB.amber)
    }
}

/// A glass search field that sits in a screen's own header row.
struct HBSearchField: View {
    @Binding var text: String
    var prompt: String
    var width: CGFloat = 250
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.65))
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13.5)).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.55)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(width: width, height: 38)
        .hbGlass(Capsule(), interactive: true)
        .overlay(Capsule().stroke(HB.amber.opacity(focused ? 0.8 : 0), lineWidth: 1.5))
        .animation(HB.Motion.quick, value: focused)
    }
}

extension View {
    /// macOS 26 fades scrolled content into a soft gray band under the toolbar; the key art should stay clean.
    @ViewBuilder func hbScrollEdgeClear() -> some View {
        if #available(macOS 26.0, *) { self.scrollEdgeEffectHidden(true, for: .top) } else { self }
    }
}

import Foundation

/// The sentences on a game's page (UX plan §3.5). Facts stated, gaps named, nothing computed
/// that was not measured: "verified on an M4 Pro" and "your Mac is an M1 Pro", never
/// "verified on a Mac like yours".
public enum GamePageCopy {
    public struct Verdict: Equatable {
        public var headline: String
        public var detail: String?
    }

    /// The verdict sentence for an entry (nil: no row at all), given the reader's chip.
    public static func verdict(_ entry: GameDBEntry?, myChip: String, today: Date = Date()) -> Verdict {
        let mine = shortChip(myChip)
        guard let entry else {
            return Verdict(headline: String(format: L("Nobody has tested this on an %@ yet."), mine),
                           detail: L("Nothing in the compatibility database for it yet. You would be the first to report it."))
        }
        switch entry.status {
        case "blocked-anticheat":
            let name = entry.anticheat?.names.first ?? L("its anti-cheat")
            return Verdict(headline: String(format: L("Can't run: %@."), name),
                           detail: entry.anticheat?.note ?? L("Its anti-cheat does not run on macOS."))
        case "blocked-publisher":
            return Verdict(headline: L("Can't run: its publisher blocks macOS."),
                           detail: L("The game stops itself when it finds macOS, whatever the engine or graphics mode."))
        case "verified-local":
            let chip = entry.verified?.chip.map(shortChip)
            var head = chip.map { String(format: L("Verified on an %@."), $0) } ?? L("Verified on this project's own Mac.")
            if chip == mine { head = String(format: L("Verified on an %@, the same chip as yours."), mine) }
            var parts: [String] = []
            if let fps = entry.verified?.fps, let phrase = fpsPhrase(fps) {
                parts.append(phrase)
            }
            if let os = entry.verified?.macos { parts.append(String(format: L("on macOS %@"), os)) }
            var detail = parts.isEmpty ? "" : sentenceCase(parts.joined(separator: " "))
            if let when = freshness(entry.lastVerified, today: today) {
                detail += detail.isEmpty ? String(format: L("Last confirmed %@."), when) : String(format: L(", last confirmed %@."), when)
            } else if !detail.isEmpty { detail += "." }
            if let chip, chip != mine { detail += (detail.isEmpty ? "" : " ") + String(format: L("Your Mac is an %@."), mine) }
            return Verdict(headline: head, detail: detail.isEmpty ? nil : detail)
        case "reported-upstream":
            return Verdict(headline: L("Reported working upstream."),
                           detail: String(format: L("Named in the renderer's release notes as working; not verified here yet. Your Mac is an %@."), mine))
        default:
            return Verdict(headline: L("Reported by players."),
                           detail: String(format: L("Not verified by this project yet. Your Mac is an %@."), mine))
        }
    }

    /// The card for a game with a native Mac build on Steam. The Windows build stays available,
    /// as a secondary action: it can still be the one someone wants (a port that lags behind,
    /// an Intel-only one, mods).
    public struct MacBuild: Equatable {
        public var headline: String
        public var detail: String
        /// The row's note: the build's own requirements ("macOS 12 and M1 or later").
        public var requirements: String?
        public var yourMac: String
        public var source: String
    }

    public static func macBuild(_ build: MacSteamBuild?, entry: GameDBEntry?, myChip: String, macOS: String) -> MacBuild? {
        guard let build else { return nil }
        let installed = build == .installed
        let source = switch build {
        case .installed: L("Steam for Mac lists it as installed.")
        case .inDatabase: L("From the compatibility database.")
        case .onStore: L("Steam's store page lists macOS for it.")
        }
        return MacBuild(
            headline: installed ? L("Installed in Steam for Mac.") : L("There is a native Mac build on Steam."),
            detail: installed
                ? L("Play starts the Mac build through Steam for Mac, with no Windows layer in between.")
                : L("It will beat running the Windows version through any compatibility layer, and your Steam purchase already includes it."),
            requirements: entry?.nativeMac?.available == true ? entry?.nativeMac?.note : nil,
            yourMac: String(format: L("Your Mac is an %@ on macOS %@."), shortChip(myChip), macOS),
            source: source)
    }

    /// One line of "when you press Play, KLYC-Box will".
    public struct WillDo: Equatable {
        public var text: String
        public var cost: String?
        public var done: Bool
        public init(text: String, cost: String? = nil, done: Bool = false) { self.text = text; self.cost = cost; self.done = done }
    }

    /// What Play applies, in order, from the row and the fix recipe. `applied` means the recipe
    /// already ran in this environment, so its steps read as done.
    public static func willDo(_ entry: GameDBEntry?, recipe: Recipe?, applied: Bool,
                              bottleRenderer: Renderer, explicit: Bool = false, gameOverride: Renderer? = nil,
                              osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> [WillDo] {
        var items: [WillDo] = []
        if entry?.nativeVulkan == true {
            items.append(WillDo(text: L("Let it draw with Vulkan directly; the graphics mode does not apply to this game")))
        } else if let gameOverride {
            items.append(WillDo(text: String(format: L("Use %@ for this game (set by you); the environment stays on %@"), plainName(gameOverride), plainName(bottleRenderer))))
        } else if explicit {
            if let wanted = entry?.effectiveRenderer(osMajor: osMajor), wanted != bottleRenderer {
                items.append(WillDo(text: String(format: L("Use %@, your environment's setting. The database asks for %@, and an environment's own setting wins"), plainName(bottleRenderer), plainName(wanted))))
            } else {
                items.append(WillDo(text: String(format: L("Use %@, the environment's setting (set by you)"), plainName(bottleRenderer))))
            }
        } else if let wanted = entry?.effectiveRenderer(osMajor: osMajor) {
            items.append(WillDo(text: wanted == bottleRenderer
                                ? String(format: L("Use %@, the way it was verified"), plainName(wanted))
                                : String(format: L("Use %@ for this game, the way it was verified, instead of the environment's %@"), plainName(wanted), plainName(bottleRenderer))))
        } else {
            items.append(WillDo(text: String(format: L("Use %@, the environment's setting; no verdict names a better one"), plainName(bottleRenderer))))
        }
        if let args = entry?.effectiveLaunchArgs(osMajor: osMajor), !args.isEmpty {
            items.append(WillDo(text: String(format: L("Start it with %@"), args.joined(separator: " "))))
        }
        if let recipe, recipe.isOptIn {
            // Play does not touch an opt-in fix; the page says so rather than listing steps
            // Play will not take.
            items.append(WillDo(text: applied
                                ? String(format: L("Keep the %@ fix you applied under Advanced"), recipe.title)
                                : String(format: L("Leave the optional %@ fix alone; it is under Advanced for when the notes say your Mac needs it"), recipe.title),
                                done: applied))
        } else if let recipe {
            for step in recipe.steps {
                guard let text = describe(step) else { continue }
                items.append(WillDo(text: text, cost: applied ? nil : step.slowHint, done: applied))
            }
        }
        return items
    }

    /// The row's renderer when only the environment's explicit setting keeps it from applying and
    /// no per-game choice exists yet. The game page offers it for this game alone, so the reader
    /// is never left with a plan that names two graphics modes (2026-09-11 walkthrough).
    public static func rowRendererHeldBack(_ entry: GameDBEntry?, bottleRenderer: Renderer, explicit: Bool, gameOverride: Renderer?,
                                           osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> Renderer? {
        guard explicit, gameOverride == nil, entry?.nativeVulkan != true,
              let wanted = entry?.effectiveRenderer(osMajor: osMajor), wanted != bottleRenderer else { return nil }
        return wanted
    }

    /// The row's fps field is a figure followed by where it was read: "about 34 in the prologue
    /// ride at 1280x720". The sentence keeps both, puts "frames per second" after the figure, and
    /// stops at the first full stop so the verdict stays one sentence. A field that starts with
    /// no figure ("menu renders, DXVK") is used as it is; a paragraph stitched in by mistake is
    /// cut the same way (2026-09-11, Assetto Corsa).
    public static func fpsPhrase(_ fps: String) -> String? {
        var t = fps.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stop = t.range(of: ". ") { t = String(t[..<stop.lowerBound]) }
        if t.hasSuffix(".") { t.removeLast() }
        guard !t.isEmpty else { return nil }
        let figure = "^(?i:about )?[0-9]+(?:\\.[0-9]+)?(?:\\s*(?:-|–|to)\\s*[0-9]+(?:\\.[0-9]+)?)?"
        guard let r = t.range(of: figure, options: .regularExpression) else { return t }
        let rest = String(t[r.upperBound...])
        if rest.lowercased().hasPrefix(" fps") { return t }
        return String(t[r]) + " " + L("frames per second") + rest
    }

    // MARK: helpers

    public static func plainName(_ r: Renderer) -> String {
        switch r {
        case .dxmt: return L("DXMT (DirectX 11 on Metal)")
        case .d3dmetal: return L("Apple's DirectX 12 support")
        case .dxvk: return L("DXVK (Vulkan on Metal)")
        case .wined3d: return L("Wine's own Direct3D")
        case .vkd3d: return L("vkd3d-proton (DirectX 12 through Vulkan)")
        }
    }

    /// "Apple M1 Pro" -> "M1 Pro"; anything else unchanged.
    public static func shortChip(_ chip: String) -> String {
        let t = chip.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("Apple ") ? String(t.dropFirst(6)) : t
    }

    /// "today", "yesterday", "12 days ago", or "on 2026-08-25" past two months.
    static func freshness(_ ymd: String?, today: Date) -> String? {
        guard let ymd else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: ymd) else { return nil }
        let days = Int(today.timeIntervalSince(d) / 86_400)
        switch days {
        case ..<1: return L("today")
        case 1: return L("yesterday")
        case 2...60: return String(format: L("%d days ago"), days)
        default: return String(format: L("on %@"), ymd)
        }
    }

    static func sentenceCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    static func describe(_ step: Recipe.Step) -> String? {
        switch step {
        case let .installer(_, _, _, label, _, _): return String(format: L("Install %@"), label)
        case let .winetricks(verbs, _): return String(format: L("Install %@"), verbs.joined(separator: ", "))
        case let .registry(_, name, _, _): return String(format: L("Set the Windows registry value %@"), name)
        case let .environment(name, _): return String(format: L("Set %@ for this game"), name)
        case let .renderer(r): return String(format: L("Switch the environment's graphics mode to %@"), plainName(r))
        case let .sync(m): return String(format: L("Set the environment's sync mode to %@"), m.rawValue)
        case let .winver(v): return String(format: L("Report Windows %@ to the game"), v.rawValue)
        case let .file(path, _): return String(format: L("Write %@"), URL(fileURLWithPath: path).lastPathComponent)
        case let .copy(from, _, _): return String(format: L("Give the game its own %@ from the engine"), URL(fileURLWithPath: from).lastPathComponent)
        case .pin: return nil
        case let .note(text): return text
        case let .dllOverride(v): return String(format: L("Set the Windows library override %@"), v)
        case let .dxvkConfig(exe, _): return String(format: L("Configure DXVK for %@"), exe)
        }
    }
}

extension GamePageCopy {
    /// The consequence sentence of the D3DMetal ask, from the row: "will not start" only when
    /// no other renderer is recorded as working, "runs faster with it" when one is.
    public static func d3dMetalAsk(title: String, entry: GameDBEntry?) -> String {
        // Asked because the environment (or a pinned program) is set to D3DMetal, not because
        // the row needs it (#61): say where the setting came from and that the default runs.
        guard entry?.effectiveRenderer() == .d3dmetal else {
            return "The environment \(title) runs in is set to D3DMetal, which needs Apple's licence accepted for its engine. Turning it on means accepting that licence, which allows non-commercial use; nothing downloads and nothing is sent to Apple. Playing with DXMT, KLYC-Box's default, works for most games."
        }
        let consequence = otherWorkingRenderer(entry).map {
            "Without it, \(title) still runs on \(plainName($0)), which was recorded as working, but slower."
        } ?? "The database records no other graphics mode as working for \(title), so without it KLYC-Box has nothing else to try."
        return "KLYC-Box already includes it. Turning it on means accepting Apple's licence, which allows non-commercial use. \(consequence) Nothing to download and nothing sent to Apple."
    }

    /// A graphics mode other than D3DMetal that the row recorded as working, if any.
    public static func otherWorkingRenderer(_ entry: GameDBEntry?) -> Renderer? {
        guard let results = entry?.rendererResults else { return nil }
        for key in ["dxmt", "vkd3d", "dxvk", "wined3d"] where results[key]?.verdict == "works" {
            if let r = Renderer(rawValue: key) { return r }
        }
        return nil
    }
}

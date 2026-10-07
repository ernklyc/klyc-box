import Foundation

/// What a game's launch log says about why it closed, in terms a person can act on.
///
/// Every finding is a line the log actually contains; nothing is guessed from the game's name.
/// A finding names the one thing that usually fixes it (install a runtime, try another graphics
/// mode) or says plainly that nothing can (kernel anti-cheat). Wine's own noise (the
/// `err:sync`, `err:ole`, `err:hid` lines every session prints) never counts.
public struct CrashFinding: Equatable, Sendable, Identifiable {
    public enum Fix: Equatable, Sendable {
        /// Install this dependency recipe (`vcrun2022`, `dotnet48`) into the environment.
        case installRecipe(String)
        /// Play once with another graphics mode.
        case tryOtherRenderer
        /// Stop the environment's processes so the next Play starts fresh.
        case restartEnvironment
        /// Nothing the app can do; the headline and meaning say why.
        case none
    }

    public enum Kind: String, Equatable, Sendable {
        case missingRuntime, missingDotNet, missingDirectXFiles, missingMedia, missingLibrary
        case antiCheat, graphics, outOfMemory, crash, syncMismatch
    }

    public var kind: Kind
    /// The log's own detail (a DLL name, an anti-cheat's name), for the headline's blanks.
    public var detail: String?
    public var fix: Fix

    public var id: String { kind.rawValue + (detail ?? "") }

    public init(kind: Kind, detail: String? = nil, fix: Fix) {
        self.kind = kind; self.detail = detail; self.fix = fix
    }
}

public enum CrashDiagnosis {
    /// Reads at most the last `tailBytes` of a log: launch logs are capped at 256 MB and the
    /// reason a game closed is at the end.
    public static func tail(of url: URL, bytes tailBytes: Int = 4 * 1024 * 1024) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Findings for a log, most useful first. Pure: callers hand in the log's tail.
    public static func diagnose(log: String) -> [CrashFinding] {
        var found: [CrashFinding] = []
        func add(_ f: CrashFinding) { if !found.contains(where: { $0.id == f.id }) { found.append(f) } }

        for raw in log.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            // Cheap exits first: most lines are Wine chatter.
            if line.contains("import_dll") || line.contains("could not load") {
                if let dll = missingLibrary(in: line) { add(classify(dll: dll)) }
                continue
            }
            if line.contains("mscoree") && (line.contains("err:") || line.contains("not found")) {
                add(CrashFinding(kind: .missingDotNet, fix: .installRecipe("dotnet48"))); continue
            }
            if let name = antiCheat(in: line) { add(CrashFinding(kind: .antiCheat, detail: name, fix: .none)); continue }
            if line.contains("msync shared memory") || line.contains("msync_init") {
                add(CrashFinding(kind: .syncMismatch, fix: .restartEnvironment)); continue
            }
            if line.contains("VK_ERROR_DEVICE_LOST") || line.contains("VK_ERROR_INITIALIZATION_FAILED")
                || line.contains("Failed to create D3D") || line.contains("Failed to create Vulkan")
                || line.contains("failed to create device") || line.contains("DXGI_ERROR_DEVICE_REMOVED") {
                add(CrashFinding(kind: .graphics, fix: .tryOtherRenderer)); continue
            }
            if line.contains("Out of memory") || line.contains("c0000017") || line.contains("not enough virtual memory") {
                add(CrashFinding(kind: .outOfMemory, fix: .none)); continue
            }
            if line.contains("Unhandled exception") || line.contains("Unhandled page fault") || line.contains("unhandled exception") {
                add(CrashFinding(kind: .crash, fix: .tryOtherRenderer))
            }
        }
        // A named cause outranks the generic "it crashed".
        return found.sorted { rank($0.kind) < rank($1.kind) }
    }

    private static func rank(_ kind: CrashFinding.Kind) -> Int {
        switch kind {
        case .antiCheat: return 0
        case .missingRuntime, .missingDotNet, .missingDirectXFiles, .missingMedia, .missingLibrary: return 1
        case .syncMismatch: return 2
        case .graphics, .outOfMemory: return 3
        case .crash: return 4
        }
    }

    /// `err:module:import_dll Library X.dll (which is needed by L"C:\\...\\game.exe") not found`.
    /// Steam's own helper tools miss libraries on every start and are harmless (the log of any
    /// session has `gldriverquery.exe` missing SDL2.dll), so a library needed by something in
    /// Steam's `bin` folder is not a finding.
    static func missingLibrary(in line: String) -> String? {
        guard let r = line.range(of: "Library ") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.range(of: " (which is needed by") else { return nil }
        // Wine's log escapes backslashes ("Steam\\\\bin"); fold them so one spelling is checked.
        let needer = rest[end.upperBound...].replacingOccurrences(of: "\\\\", with: "\\").lowercased()
        if needer.contains("\\steam\\bin\\") || needer.contains("\\steam\\steamapps\\common\\steamworks") { return nil }
        guard needer.contains("not found") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    /// Which family a missing library belongs to, and the fix that brings it.
    static func classify(dll: String) -> CrashFinding {
        let name = dll.lowercased()
        if name.hasPrefix("msvcp") || name.hasPrefix("vcruntime") || name.hasPrefix("concrt") || name.hasPrefix("ucrtbase") || name.hasPrefix("api-ms-win-crt") || name.hasPrefix("vccorlib") || name.hasPrefix("msvcr") {
            return CrashFinding(kind: .missingRuntime, detail: dll, fix: .installRecipe("vcrun2022"))
        }
        if name.hasPrefix("mscoree") || name.hasPrefix("clr") || name.hasPrefix("mscorlib") {
            return CrashFinding(kind: .missingDotNet, detail: dll, fix: .installRecipe("dotnet48"))
        }
        if name.hasPrefix("d3dx") || name.hasPrefix("d3dcompiler") || name.hasPrefix("xinput") || name.hasPrefix("xaudio") || name.hasPrefix("x3daudio") || name.hasPrefix("xapofx") {
            return CrashFinding(kind: .missingDirectXFiles, detail: dll, fix: .none)
        }
        if name.hasPrefix("mf") || name.hasPrefix("wmvcore") || name.hasPrefix("wmp") || name.hasPrefix("evr") {
            return CrashFinding(kind: .missingMedia, detail: dll, fix: .none)
        }
        return CrashFinding(kind: .missingLibrary, detail: dll, fix: .none)
    }

    /// The anti-cheat a line names, when it is one that does not run under Wine on a Mac.
    static func antiCheat(in line: String) -> String? {
        let l = line.lowercased()
        // A path or a version string naming the product is not a failure; the line has to say
        // something went wrong.
        guard ["err:", "fail", "unable", "error", "could not", "not found", "denied", "blocked"].contains(where: { l.contains($0) }) else { return nil }
        if l.contains("easyanticheat") || l.contains("easy anti-cheat") || l.contains("eac_launcher") { return "Easy Anti-Cheat" }
        if l.contains("beservice") || l.contains("battleye") { return "BattlEye" }
        if l.contains("eaanticheat") || l.contains("ea anticheat") { return "EA Javelin" }
        if l.contains("vgc.exe") || l.contains("riot vanguard") { return "Vanguard" }
        return nil
    }
}

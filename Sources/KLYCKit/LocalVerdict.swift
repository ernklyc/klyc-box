import Foundation

/// What the player found out about one game on this Mac: it worked or it did not, and optionally the frame rate they saw.
/// Kept on this machine and shown as "verified on your Mac"; sharing it is the player's choice (a report on the project page).
public struct LocalVerdict: Codable, Sendable, Equatable {
    public var works: Bool
    /// The frame rate the player read off the screen (the Metal overlay, for example). Never computed here.
    public var fps: Int?
    public var renderer: String?
    public var engine: String
    public var chip: String
    public var macos: String
    public var minutes: Int?
    public var date: Date
    /// The game's name, so an export can create a database entry for a game the database does not know yet.
    public var title: String?
    /// True when KLYC-Box worked it out itself from a long, normal session; the player typed nothing.
    public var auto: Bool?
    /// True when the frame rate was read from the Metal HUD log, not typed by the player.
    public var fpsMeasured: Bool?
    public init(works: Bool, fps: Int? = nil, renderer: String? = nil, engine: String, chip: String, macos: String,
                minutes: Int? = nil, date: Date = Date(), title: String? = nil, auto: Bool? = nil, fpsMeasured: Bool? = nil) {
        self.fpsMeasured = fpsMeasured; self.auto = auto; self.title = title; self.works = works; self.fps = fps; self.renderer = renderer; self.engine = engine
        self.chip = chip; self.macos = macos; self.minutes = minutes; self.date = date
    }

    /// "M4, macOS 27.0.1": the machine in words.
    public var machine: String { "\(GamePageCopy.shortChip(chip)), macOS \(macos)" }
}

/// When a finished session counts as proof that a game works on this Mac, with nobody asked.
public enum AutoVerdict {
    /// The game ran for at least ten minutes and then ended by itself or was quit normally. A crash, a launcher that
    /// closes at once or a short test is not enough: those still ask, or say nothing.
    public static let minimumSeconds = 600

    public static func works(reason: String, seconds: Int) -> Bool {
        reason == "ended" && seconds >= minimumSeconds
    }

    /// An automatic result never replaces what the player said themselves.
    public static func mayReplace(existing: LocalVerdict?) -> Bool { existing == nil || existing?.auto == true }
}

public struct LocalVerdictStore: Sendable {
    public let paths: KLYCPaths
    public init(paths: KLYCPaths = KLYCPaths()) { self.paths = paths }

    var file: URL { paths.home.appending(path: "verdicts.json", directoryHint: .notDirectory) }

    public func all() -> [String: LocalVerdict] {
        guard let data = try? Data(contentsOf: file),
              let map = try? JSONDecoder.klycbox.decode([String: LocalVerdict].self, from: data) else { return [:] }
        return map
    }

    public func set(_ verdict: LocalVerdict?, for id: String) {
        var map = all()
        map[id] = verdict
        try? paths.ensure()
        if let data = try? JSONEncoder.klycbox.encode(map) { try? data.write(to: file, options: .atomic) }
    }

    /// Readable JSON for sharing or for `Scripts/ingest-verdicts.py`.
    public func exportJSON() -> Data? {
        let encoder = JSONEncoder.klycbox
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(all())
    }
}

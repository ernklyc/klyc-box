import Foundation

/// What "Improve" found for one game on this Mac: which graphics mode started it and stayed up, and how it
/// went for each mode that was tried. Measured here, on this Mac, never copied from anywhere.
public struct TuningResult: Codable, Sendable, Equatable {
    public struct Attempt: Codable, Sendable, Equatable {
        public var renderer: Renderer
        public var verdict: VerifyOutcome.Verdict
        public var secondsAlive: Int
        public init(renderer: Renderer, verdict: VerifyOutcome.Verdict, secondsAlive: Int) {
            self.renderer = renderer; self.verdict = verdict; self.secondsAlive = secondsAlive
        }
    }
    /// The mode that was picked, nil when none of them started the game cleanly.
    public var best: Renderer?
    public var attempts: [Attempt]
    public var date: Date
    public var engine: String
    public init(best: Renderer?, attempts: [Attempt], date: Date = Date(), engine: String) {
        self.best = best; self.attempts = attempts; self.date = date; self.engine = engine
    }

    /// Picks the mode that did best: a game that rendered beats one that showed black, which beats one
    /// that crashed; longer alive and the order given (the engine's preference) break ties.
    public static func pick(_ attempts: [Attempt]) -> Renderer? {
        func score(_ a: Attempt) -> Int {
            switch a.verdict { case .renders: return 3; case .blackScreen: return 1; case .crashed, .neverStarted: return 0 }
        }
        let ranked = attempts.enumerated().sorted { l, r in
            let (a, b) = (l.element, r.element)
            if score(a) != score(b) { return score(a) > score(b) }
            if a.secondsAlive != b.secondsAlive { return a.secondsAlive > b.secondsAlive }
            return l.offset < r.offset
        }
        guard let top = ranked.first?.element, score(top) == 3 else { return nil }   // only a mode that rendered is worth saving
        return top.renderer
    }
}

public struct TuningStore: Sendable {
    public let paths: KLYCPaths
    public init(paths: KLYCPaths = KLYCPaths()) { self.paths = paths }

    var file: URL { paths.home.appending(path: "tuning.json", directoryHint: .notDirectory) }

    public func all() -> [String: TuningResult] {
        guard let data = try? Data(contentsOf: file),
              let map = try? JSONDecoder.klycbox.decode([String: TuningResult].self, from: data) else { return [:] }
        return map
    }

    public func save(_ result: TuningResult, for id: String) {
        var map = all()
        map[id] = result
        guard let data = try? JSONEncoder.klycbox.encode(map) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// All results as readable JSON, for sharing with whoever keeps a compatibility database.
    public func exportJSON() -> Data? {
        let encoder = JSONEncoder.klycbox
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(all())
    }

    public func remove(_ id: String) {
        var map = all(); map[id] = nil
        if let data = try? JSONEncoder.klycbox.encode(map) { try? data.write(to: file, options: .atomic) }
    }
}

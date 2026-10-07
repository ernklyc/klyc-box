import Foundation

/// Reads the frame rate out of Apple's Metal performance HUD log. With MTL_HUD_ENABLED and MTL_HUD_LOG_ENABLED both on,
/// the process prints one line a second: "<time> <name>[<pid>:<tid>] metal-HUD: <frames so far>,<…>". The frame rate is the
/// change in that counter over the time between two lines; nothing is estimated from anything else.
public enum HUDLog {
    public struct Sample: Equatable, Sendable { public let pid: Int; public let time: Date; public let frames: Int }

    public struct Summary: Equatable, Sendable {
        /// Typical frame rate over the run (the median of the per-second rates).
        public let median: Int
        /// The slowest second.
        public let lowest: Int
        public let seconds: Int
    }

    private static let line = try! NSRegularExpression(pattern: #"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}) \S+\[(\d+):[0-9a-fA-F]+\] metal-HUD: (\d+),"#)

    static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }

    public static func samples(in text: String) -> [Sample] {
        let f = formatter()
        var out: [Sample] = []
        for raw in text.split(separator: "\n") where raw.contains("metal-HUD:") {
            let s = String(raw), range = NSRange(s.startIndex..., in: s)
            guard let m = line.firstMatch(in: s, range: range), m.numberOfRanges == 4,
                  let tR = Range(m.range(at: 1), in: s), let pR = Range(m.range(at: 2), in: s), let fR = Range(m.range(at: 3), in: s),
                  let time = f.date(from: String(s[tR])), let pid = Int(s[pR]), let frames = Int(s[fR]) else { continue }
            out.append(Sample(pid: pid, time: time, frames: frames))
        }
        return out
    }

    /// The frame rate of the process that drew the most (the game, not a launcher window), between `from` and `to`.
    public static func summary(in text: String, from: Date = .distantPast, to: Date = .distantFuture) -> Summary? {
        let all = samples(in: text).filter { $0.time >= from && $0.time <= to }
        let byPID = Dictionary(grouping: all, by: \.pid)
        guard let game = byPID.max(by: { $0.value.count < $1.value.count })?.value, game.count >= 3 else { return nil }
        var rates: [Double] = []
        for (a, b) in zip(game, game.dropFirst()) {
            let dt = b.time.timeIntervalSince(a.time)
            guard dt >= 0.5, dt <= 5, b.frames >= a.frames else { continue }   // a counter that went back is another run
            rates.append(Double(b.frames - a.frames) / dt)
        }
        guard rates.count >= 3 else { return nil }
        let sorted = rates.sorted()
        let median = sorted[sorted.count / 2]
        return Summary(median: Int(median.rounded()), lowest: Int((sorted.first ?? 0).rounded()), seconds: rates.count)
    }

    /// The tail of a log file (the last `bytes`), so a long session's log is never read whole.
    public static func tail(of url: URL, bytes: Int = 4 << 20) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }
}

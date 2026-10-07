import Foundation

/// What Legendary says about a running install, read from its log lines. Legendary prints a block
/// every second or so while it downloads:
///
///     = Progress: 3.56% (11/309), Running for 00:00:22, ETA: 00:10:07
///      - Downloaded: 33.52 MiB, Written: 43.42 MiB
///      + Download  - 1.51 MiB/s (raw) / 2.44 MiB/s (decompressed)
///      + Disk      - 1.95 MiB/s (write) / 0.00 MiB/s (read)
///
/// and, before it starts, `Download size: 14.21 GiB (...)` and `Install size: 24.0 GiB`. Each
/// field is filled only from a line that carries it, so a line that does not parse leaves the
/// last known value alone instead of blanking the display.
public struct EpicDownloadProgress: Equatable, Sendable {
    /// 0...100.
    public var percent: Double?
    public var elapsedSeconds: Int?
    public var etaSeconds: Int?
    public var downloadedBytes: Int64?
    public var writtenBytes: Int64?
    /// Bytes per second off the network.
    public var downloadSpeed: Double?
    public var diskSpeed: Double?
    public var downloadSize: Int64?
    public var installSize: Int64?

    public init() {}

    /// A fraction for a progress bar, nil before the first progress line.
    public var fraction: Double? { percent.map { min(max($0 / 100, 0), 1) } }

    /// Reads one line; true when it changed something.
    @discardableResult
    public mutating func apply(line: String) -> Bool {
        let before = self
        if let m = line.firstMatch(of: #/Progress:\s*(?<p>[\d.]+)%.*?Running for\s*(?<r>[\d:]+).*?ETA:\s*(?<e>[\d:]+)/#) {
            percent = Double(m.p)
            elapsedSeconds = Self.seconds(fromClock: String(m.r))
            etaSeconds = Self.seconds(fromClock: String(m.e))
        } else if let m = line.firstMatch(of: #/Progress:\s*(?<p>[\d.]+)%/#) {
            percent = Double(m.p)
        }
        if let m = line.firstMatch(of: #/Downloaded:\s*(?<d>[\d.]+\s*[KMGT]?i?B)(?:,\s*Written:\s*(?<w>[\d.]+\s*[KMGT]?i?B))?/#) {
            downloadedBytes = Self.bytes(from: String(m.d))
            if let w = m.w { writtenBytes = Self.bytes(from: String(w)) }
        }
        if line.contains("Download"), let m = line.firstMatch(of: #/\+\s*Download\s*-\s*(?<s>[\d.]+\s*[KMGT]?i?B)\/s/#) {
            downloadSpeed = Self.bytes(from: String(m.s)).map(Double.init)
        }
        if line.contains("Disk"), let m = line.firstMatch(of: #/\+\s*Disk\s*-\s*(?<s>[\d.]+\s*[KMGT]?i?B)\/s/#) {
            diskSpeed = Self.bytes(from: String(m.s)).map(Double.init)
        }
        if let m = line.firstMatch(of: #/Download size:\s*(?<s>[\d.]+\s*[KMGT]?i?B)/#) { downloadSize = Self.bytes(from: String(m.s)) }
        if let m = line.firstMatch(of: #/Install size:\s*(?<s>[\d.]+\s*[KMGT]?i?B)/#) { installSize = Self.bytes(from: String(m.s)) }
        return self != before
    }

    /// `00:10:07` -> 607. `HH:MM:SS` or `MM:SS`.
    static func seconds(fromClock text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// `33.52 MiB` -> bytes (binary units, as Legendary prints them).
    static func bytes(from text: String) -> Int64? {
        let parts = text.split(separator: " ").map(String.init)
        let number: String, unit: String
        if parts.count == 2 { number = parts[0]; unit = parts[1] }
        else if let i = text.firstIndex(where: { $0.isLetter }) { number = String(text[..<i]); unit = String(text[i...]) }
        else { return nil }
        guard let value = Double(number) else { return nil }
        let scale: Double
        switch unit {
        case "B": scale = 1
        case "KiB", "KB": scale = 1024
        case "MiB", "MB": scale = 1024 * 1024
        case "GiB", "GB": scale = 1024 * 1024 * 1024
        case "TiB", "TB": scale = 1024 * 1024 * 1024 * 1024
        default: return nil
        }
        return Int64(value * scale)
    }

    /// Whether a log line is one of the once-a-second progress lines, which the activity log
    /// does not need to repeat (they would push everything else out of it).
    public static func isProgressNoise(_ line: String) -> Bool {
        line.contains("= Progress:") || line.contains("- Downloaded:") || line.contains("- Cache usage:")
            || line.contains("+ Download") || line.contains("+ Disk")
    }
}

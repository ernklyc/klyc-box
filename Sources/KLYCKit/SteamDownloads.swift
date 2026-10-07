import Foundation

/// A game Steam is downloading, updating or has paused, and what it holds on disk, from `steamapps/appmanifest_*.acf`.
/// The client writes these files as it goes, so reading them every few seconds shows its real progress.
public struct SteamTransfer: Sendable, Equatable, Identifiable {
    public enum State: Sendable { case downloading, paused, waiting, installed }
    public var appid: Int
    public var name: String
    public var flags: Int
    public var downloaded: Int64
    public var toDownload: Int64
    public var staged: Int64
    public var toStage: Int64
    public var sizeOnDisk: Int64
    public var id: Int { appid }

    /// StateFlags: 4 installed, 2 update required, 256 running, 512 paused, 1024 started.
    public var state: State {
        if flags & 512 != 0 { return .paused }
        if flags & (256 | 1024) != 0 { return .downloading }
        if flags & 4 != 0 && flags & 2 == 0 { return .installed }
        return .waiting
    }

    /// Download and unpacking together, 0...1. Nil when Steam has not said how much there is.
    public var progress: Double? {
        let total = toDownload + toStage
        return total > 0 ? min(1, Double(downloaded + staged) / Double(total)) : nil
    }

    public static func parse(_ text: String) -> SteamTransfer? {
        var fields: [String: String] = [:]
        for m in text.matches(of: #/"([A-Za-z]+)"\s+"([^"]*)"/#) where fields[String(m.1)] == nil { fields[String(m.1)] = String(m.2) }
        guard let appid = fields["appid"].flatMap(Int.init), let name = fields["name"] else { return nil }
        func n(_ k: String) -> Int64 { fields[k].flatMap(Int64.init) ?? 0 }
        return SteamTransfer(appid: appid, name: name, flags: Int(n("StateFlags")), downloaded: n("BytesDownloaded"), toDownload: n("BytesToDownload"),
                             staged: n("BytesStaged"), toStage: n("BytesToStage"), sizeOnDisk: n("SizeOnDisk"))
    }

    public static func scan(steamapps: URL) -> [SteamTransfer] {
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap(parse)
            .filter { $0.appid != 228980 }
    }
}

/// Download speed and time left for Steam's transfers. Steam writes only how much it has done, not
/// how fast, so the speed is the change between two looks at its files, smoothed so the number
/// does not jump with every look. An estimate from the same files the progress bar reads, shown
/// as one.
public struct SteamTransferRates: Sendable {
    private var last: [Int: (bytes: Int64, at: Date)] = [:]
    /// Bytes per second, for transfers that are downloading.
    public private(set) var speed: [Int: Double] = [:]

    public init() {}

    /// Folds in a new look. A transfer that is not downloading has no speed; one that has just
    /// appeared has none until the next look.
    public mutating func update(_ transfers: [SteamTransfer], at now: Date) {
        var next: [Int: (bytes: Int64, at: Date)] = [:]
        for t in transfers where t.state == .downloading {
            let bytes = t.downloaded + t.staged
            next[t.appid] = (bytes, now)
            guard let before = last[t.appid] else { continue }
            let seconds = now.timeIntervalSince(before.at)
            guard seconds >= 0.5 else { next[t.appid] = before; continue }
            let instant = max(0, Double(bytes - before.bytes) / seconds)
            let previous = speed[t.appid]
            speed[t.appid] = previous.map { 0.6 * $0 + 0.4 * instant } ?? instant
        }
        speed = speed.filter { next[$0.key] != nil }
        last = next
    }

    /// Seconds left at the current speed; nil when it is too slow or unknown to say.
    public func etaSeconds(for t: SteamTransfer) -> Int? {
        guard t.state == .downloading, let s = speed[t.appid], s > 4096 else { return nil }
        let remaining = (t.toDownload + t.toStage) - (t.downloaded + t.staged)
        return remaining > 0 ? Int(Double(remaining) / s) : nil
    }
}

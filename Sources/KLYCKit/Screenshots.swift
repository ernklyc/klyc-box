import Foundation

/// The screenshots Steam took for a game inside its environment (the overlay's F12), newest first.
public enum ScreenshotFinder {
    public static func find(driveC: URL, steamAppID: Int, limit: Int = 24) -> [URL] {
        let fm = FileManager.default
        let userdata = driveC.appending(path: "Program Files (x86)/Steam/userdata")
        var all: [(URL, Date)] = []
        for account in (try? fm.contentsOfDirectory(atPath: userdata.path)) ?? [] {
            let dir = userdata.appending(path: "\(account)/760/remote/\(steamAppID)/screenshots")
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                all.append((url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
        }
        return all.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

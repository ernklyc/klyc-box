import Foundation

/// After a crash, macOS leaves a report (`KLYC-Box-<date>.ips`) in ~/Library/Logs/DiagnosticReports. Nothing reads it for us (Apple
/// forwards reports only to the team that signed the app, and an ad-hoc build has none), and KLYC-Box uploads nothing by itself.
/// So the next launch can OFFER to open a pre-filled GitHub issue: this type turns the report into a short summary that carries
/// no file paths, no game names and no account data: the crash type, the versions, and the function names on the crashing thread.
/// The person sees the whole text in the browser and decides whether to submit.
public enum CrashReport {
    public struct Summary: Equatable, Sendable {
        public var appVersion: String
        public var os: String
        public var model: String
        public var exception: String
        public var frames: [String]
        public var time: String

        /// The issue's log field.
        public var text: String {
            var out = "KLYC-Box \(appVersion), \(os), \(model)\nCrash: \(exception)\nTime: \(time)\n\nCrashing thread (top frames):\n"
            out += frames.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")
            return out
        }
    }

    public static let bundleID = "com.klyc.klycbox"
    static let maxFrames = 14

    /// Pure: the text of an `.ips` file (a one-line JSON header, then a JSON body) → a path-free summary. nil when it is not
    /// KLYC-Box's report or cannot be read.
    public static func summary(ips: String) -> Summary? {
        guard let split = ips.firstIndex(of: "\n") else { return nil }
        func object(_ s: Substring) -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
        }
        guard let header = object(ips[..<split]), let body = object(ips[ips.index(after: split)...]) else { return nil }
        let id = (header["bundleID"] as? String) ?? ((body["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String)
        guard id == bundleID else { return nil }

        let info = body["bundleInfo"] as? [String: Any]
        let version = (info?["CFBundleShortVersionString"] as? String) ?? (header["app_version"] as? String) ?? "?"
        let osTrain = ((body["osVersion"] as? [String: Any])?["train"] as? String) ?? (header["os_version"] as? String) ?? "?"
        let ex = body["exception"] as? [String: Any]
        let exception = [ex?["type"] as? String, (ex?["signal"] as? String).map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")

        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = (body["faultingThread"] as? Int).flatMap { threads.indices.contains($0) ? threads[$0] : nil }
            ?? threads.first { ($0["triggered"] as? Bool) == true }
        var frames: [String] = []
        for f in (faulting?["frames"] as? [[String: Any]] ?? []).prefix(maxFrames) {
            var line = (f["symbol"] as? String) ?? "?"
            // Our own frames carry a source file: keep only its name and line, never a path.
            if let file = f["sourceFile"] as? String { line += " (\((file as NSString).lastPathComponent)\((f["sourceLine"] as? Int).map { ":\($0)" } ?? ""))" }
            frames.append(line)
        }
        guard !frames.isEmpty else { return nil }
        return Summary(appVersion: version, os: osTrain, model: (body["modelCode"] as? String) ?? "?",
                       exception: exception.isEmpty ? "unknown" : exception,
                       frames: frames, time: (body["captureTime"] as? String) ?? (header["timestamp"] as? String) ?? "?")
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// The newest KLYC-Box report written after `date`, if any.
    public static func newest(after date: Date, in directory: URL = defaultDirectory) -> Summary? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return nil }
        let candidates = names.filter { $0.hasPrefix("KLYC-Box") && $0.hasSuffix(".ips") }.compactMap { name -> (URL, Date)? in
            let url = directory.appending(path: name)
            guard let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, modified > date else { return nil }
            return (url, modified)
        }.sorted { $0.1 > $1.1 }
        for (url, _) in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8), let s = summary(ips: text) { return s }
        }
        return nil
    }

    /// The pre-filled GitHub issue (template bug.yml: fields what, chip, version, log).
    public static func issueURL(_ s: Summary, chip: String, macos: String) -> URL {
        var comps = URLComponents(string: "https://github.com/ernklyc/klyc-box/issues/new")!
        comps.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            URLQueryItem(name: "title", value: "Crash: \(s.exception) in \(s.frames.first ?? "?")"),
            URLQueryItem(name: "what", value: "KLYC-Box closed unexpectedly. What I was doing just before: "),
            URLQueryItem(name: "chip", value: "\(chip), macOS \(macos)"),
            URLQueryItem(name: "version", value: s.appVersion),
            URLQueryItem(name: "log", value: s.text),
        ]
        return comps.url!
    }
}

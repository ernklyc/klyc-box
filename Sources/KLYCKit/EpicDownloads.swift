import Foundation
import Observation

/// A running Legendary install that can be asked to stop. Legendary saves where it got to when it
/// is interrupted and picks up from there the next time the same install is started, which is
/// what "pause" and "resume" mean here.
public protocol EpicInstallProcess: AnyObject, Sendable {
    /// Asks it to stop the way Ctrl-C does, so it saves its place first.
    func interrupt()
}

/// The real thing: Legendary as a child process, its output lines handed on, its end reported once.
public final class LegendaryProcess: EpicInstallProcess, @unchecked Sendable {
    private let process = Process()

    public init(binary: URL, arguments: [String], environment: [String: String],
                onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws {
        process.executableURL = binary
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let reader = pipe.fileHandleForReading
        try process.run()
        Thread.detachNewThread { [process] in
            var buffer = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                // Legendary rewrites its progress with carriage returns on a terminal; split on both.
                while let i = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let line = String(decoding: buffer[..<i], as: UTF8.self)
                    buffer.removeSubrange(...i)
                    if !line.isEmpty { onLine(line) }
                }
            }
            if !buffer.isEmpty { onLine(String(decoding: buffer, as: UTF8.self)) }
            process.waitUntilExit()
            onExit(process.terminationStatus)
        }
    }

    public func interrupt() { if process.isRunning { process.interrupt() } }
}

/// One game's install, as the screens show it.
public struct EpicDownload: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        /// Asked to stop; waiting for Legendary to finish saving its place.
        case pausing
        case paused
        /// Ended with an error; the last lines it printed say why.
        case failed(String)
    }

    public var appName: String
    public var title: String
    /// The environment the game installs into, so a resume after a restart goes to the same one.
    public var bottleName: String?
    public var state: State
    public var progress: EpicDownloadProgress
    public var id: String { appName }
    public var startedAt: Date

    public init(appName: String, title: String, bottleName: String? = nil, state: State = .running,
                progress: EpicDownloadProgress = EpicDownloadProgress(), startedAt: Date = Date()) {
        self.appName = appName; self.title = title; self.bottleName = bottleName
        self.state = state; self.progress = progress; self.startedAt = startedAt
    }
}

/// Runs, pauses, resumes and cancels Epic installs, and keeps what the screens need to show:
/// percentage, speed, time left, state. The way a process is started is injected, so the rules
/// are tested without Legendary.
@Observable @MainActor
public final class EpicDownloadCenter {
    public typealias Starter = @Sendable (_ appName: String,
                                          _ onLine: @escaping @Sendable (String) -> Void,
                                          _ onExit: @escaping @Sendable (Int32) -> Void) throws -> EpicInstallProcess

    public private(set) var downloads: [EpicDownload] = []
    /// Told whenever what should survive a restart changes: the list, a state, and progress at
    /// most every few seconds. The app writes it to disk.
    @ObservationIgnored public var onPersist: (([SavedEpicDownload]) -> Void)?
    /// Told when one is cancelled (stopped and forgotten), so it is not brought back on the next start.
    @ObservationIgnored public var onCancelled: ((_ appName: String) -> Void)?
    @ObservationIgnored private var lastPersist = Date.distantPast
    /// Told when an install ends for good: true when the game is installed.
    @ObservationIgnored public var onFinished: ((_ appName: String, _ title: String, _ succeeded: Bool) -> Void)?
    /// Every output line that is not once-a-second progress, for the activity log.
    @ObservationIgnored public var onLog: ((_ line: String) -> Void)?

    @ObservationIgnored private var processes: [String: EpicInstallProcess] = [:]
    @ObservationIgnored private var starters: [String: Starter] = [:]
    @ObservationIgnored private var recentLines: [String: [String]] = [:]
    /// What a run that ended with status 0 looked like, so it can be put back if the game turns out
    /// not to be installed after all (`reinstate`).
    @ObservationIgnored private var ended: [String: EpicDownload] = [:]
    /// Which ending was asked for, so a process that exits after an interrupt is a pause, not a failure.
    @ObservationIgnored private var wanted: [String: Wish] = [:]
    private enum Wish { case pause, cancel }

    public init() {}

    public func download(for appName: String) -> EpicDownload? { downloads.first { $0.appName == appName } }
    public var isActive: Bool { downloads.contains { $0.state == .running || $0.state == .pausing } }

    /// Starts (or, for a paused or failed one, restarts) the install. A second start of one that is
    /// already running does nothing.
    public func start(appName: String, title: String, bottleName: String? = nil, starter: @escaping Starter) throws {
        if let existing = download(for: appName), existing.state == .running || existing.state == .pausing { return }
        starters[appName] = starter
        recentLines[appName] = []
        wanted[appName] = nil
        if let i = downloads.firstIndex(where: { $0.appName == appName }) {
            downloads[i].state = .running
        } else {
            downloads.append(EpicDownload(appName: appName, title: title, bottleName: bottleName))
        }
        persist()
        do {
            let box = ExitBox()
            let process = try starter(appName,
                { [weak self] line in Task { @MainActor in self?.receive(line, for: appName) } },
                { [weak self] status in Task { @MainActor in self?.exited(appName, status: status, box: box) } })
            processes[appName] = process
        } catch {
            downloads.removeAll { $0.appName == appName }
            throw error
        }
    }

    public func pause(_ appName: String) {
        guard let i = downloads.firstIndex(where: { $0.appName == appName }), downloads[i].state == .running else { return }
        wanted[appName] = .pause
        downloads[i].state = .pausing
        processes[appName]?.interrupt()
    }

    public func resume(_ appName: String) throws {
        guard let d = download(for: appName), d.state == .paused || { if case .failed = d.state { return true } else { return false } }(),
              let starter = starters[appName] else { return }
        try start(appName: appName, title: d.title, bottleName: d.bottleName, starter: starter)
    }

    /// Puts back what an earlier run left: installs that were running or paused when the app
    /// quit come up paused, with the last progress shown, ready to resume. One already in the
    /// list is left alone.
    public func restore(_ saved: [SavedEpicDownload], starter: @escaping (SavedEpicDownload) -> Starter) {
        for s in saved where download(for: s.appName) == nil {
            var progress = EpicDownloadProgress()
            progress.percent = s.percent; progress.downloadedBytes = s.downloadedBytes; progress.downloadSize = s.downloadSize
            downloads.append(EpicDownload(appName: s.appName, title: s.title, bottleName: s.bottleName, state: .paused, progress: progress))
            starters[s.appName] = starter(s)
        }
    }

    /// Puts back a run that ended with status 0 but did not leave the game installed: Legendary
    /// ended without finishing (it can, for example, when another run of the same install is
    /// going). It comes back paused, with what it had, ready to resume.
    public func reinstate(_ appName: String) {
        guard var e = ended[appName], download(for: appName) == nil else { return }
        e.state = .paused
        downloads.append(e)
        persist()
    }

    /// What should survive a restart: every install still on the list (a running one comes back paused).
    public var snapshot: [SavedEpicDownload] {
        downloads.map { SavedEpicDownload(appName: $0.appName, title: $0.title, bottleName: $0.bottleName,
                                          percent: $0.progress.percent, downloadedBytes: $0.progress.downloadedBytes,
                                          downloadSize: $0.progress.downloadSize) }
    }

    private func persist(force: Bool = true) {
        if !force, Date().timeIntervalSince(lastPersist) < 8 { return }
        lastPersist = Date()
        onPersist?(snapshot)
    }

    /// Stops it and takes it off the list. What was downloaded stays where Legendary keeps it, so
    /// installing the same game again continues from there.
    public func cancel(_ appName: String) {
        guard let d = download(for: appName) else { return }
        switch d.state {
        case .running, .pausing:
            wanted[appName] = .cancel
            processes[appName]?.interrupt()
        case .paused, .failed:
            downloads.removeAll { $0.appName == appName }
            onCancelled?(appName)
            persist()
        }
    }

    /// For quitting the app: every running install is told to save its place.
    /// Takes off the list the paused or failed installs of games that turned out to be installed
    /// (a resume file nobody deleted, or an install that finished some other way).
    public func discard(installed: Set<String>) {
        let before = downloads.count
        downloads.removeAll { installed.contains($0.appName) && ($0.state == .paused || { if case .failed = $0.state { return true } else { return false } }($0)) }
        if downloads.count != before { persist() }
    }

    public func pauseAll() { for d in downloads where d.state == .running { pause(d.appName) } }

    private func receive(_ line: String, for appName: String) {
        guard let i = downloads.firstIndex(where: { $0.appName == appName }) else { return }
        var p = downloads[i].progress
        if p.apply(line: line) { downloads[i].progress = p; persist(force: false) }
        var recent = recentLines[appName] ?? []
        if !EpicDownloadProgress.isProgressNoise(line) {
            recent.append(line); if recent.count > 8 { recent.removeFirst() }
            onLog?(line)
        }
        recentLines[appName] = recent
    }

    private func exited(_ appName: String, status: Int32, box: ExitBox) {
        guard !box.done else { return }
        box.done = true
        processes[appName] = nil
        guard let i = downloads.firstIndex(where: { $0.appName == appName }) else { return }
        let title = downloads[i].title
        switch (status, wanted[appName]) {
        case (_, .cancel?):
            downloads.remove(at: i)
            onCancelled?(appName)
        case (_, .pause?):
            downloads[i].state = .paused
        case (0, _):
            ended[appName] = downloads[i]
            downloads.remove(at: i)
            onLog?("[epic] \(title): Legendary ended with status 0")
            onFinished?(appName, title, true)
        default:
            onLog?("[epic] \(title): Legendary ended with status \(status)")
            downloads[i].state = .failed((recentLines[appName] ?? []).suffix(3).joined(separator: "\n"))
            onFinished?(appName, title, false)
        }
        wanted[appName] = nil
        persist()
    }

    private final class ExitBox: @unchecked Sendable { var done = false }
}

public extension EpicStore {
    /// Starts the install as a child process the center can control. The game goes into the
    /// bottle's drive_c/Games, as `install` does.
    func startInstall(_ appName: String, into bottle: Bottle,
                      onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws -> EpicInstallProcess {
        let base = bottle.driveC.appending(path: "Games", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return try LegendaryProcess(binary: binary, arguments: Self.installArguments(appName: appName, basePath: base.path),
                                    environment: environment, onLine: onLine, onExit: onExit)
    }
}

/// One install as it is written to disk between runs.
public struct SavedEpicDownload: Codable, Equatable, Sendable {
    public var appName: String
    public var title: String
    public var bottleName: String?
    public var percent: Double?
    public var downloadedBytes: Int64?
    public var downloadSize: Int64?

    public init(appName: String, title: String, bottleName: String? = nil, percent: Double? = nil, downloadedBytes: Int64? = nil, downloadSize: Int64? = nil) {
        self.appName = appName; self.title = title; self.bottleName = bottleName
        self.percent = percent; self.downloadedBytes = downloadedBytes; self.downloadSize = downloadSize
    }
}

/// What is kept between runs: the installs still on the list, and the ones that were cancelled
/// (their resume data stays on disk, but they must not come back as paused downloads).
public struct EpicDownloadFile: Codable, Equatable, Sendable {
    public var downloads: [SavedEpicDownload] = []
    public var dismissed: [String] = []
    public init(downloads: [SavedEpicDownload] = [], dismissed: [String] = []) { self.downloads = downloads; self.dismissed = dismissed }
}

public enum EpicDownloadStore {
    public static func load(from file: URL) -> EpicDownloadFile {
        guard let data = try? Data(contentsOf: file) else { return EpicDownloadFile() }
        return (try? JSONDecoder().decode(EpicDownloadFile.self, from: data)) ?? EpicDownloadFile()
    }

    public static func save(_ content: EpicDownloadFile, to file: URL) {
        if content.downloads.isEmpty && content.dismissed.isEmpty { try? FileManager.default.removeItem(at: file); return }
        guard let data = try? JSONEncoder().encode(content) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// A game's title from Legendary's own copy of its catalog entry (`metadata/<app>.json`), read
    /// from disk without asking Epic: it is there as soon as the app starts, while the library
    /// list takes a network round trip.
    public static func title(forApp appName: String, metadata: URL) -> String? {
        let file = metadata.appending(path: "\(appName).json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["app_title"] as? String, !title.isEmpty else { return nil }
        return title
    }

    /// The installs to bring back as paused: what was saved plus anything Legendary has resume data
    /// for (an install started by an older version, which saved nothing), minus the cancelled and
    /// the ones already installed. `titles` names a game Legendary knows by app name.
    public static func pending(file: EpicDownloadFile, resumable: [String], installed: Set<String>, titles: [String: String]) -> [SavedEpicDownload] {
        var out = file.downloads.filter { resumable.contains($0.appName) }
        for app in resumable where !out.contains(where: { $0.appName == app }) {
            if let title = titles[app] { out.append(SavedEpicDownload(appName: app, title: title)) }
        }
        return out.filter { !installed.contains($0.appName) && !file.dismissed.contains($0.appName) }
    }

    /// Games Legendary has resume data for, from the `<appname>.resume` files it keeps. It deletes
    /// the file when an install finishes, so a file means an install that did not.
    public static func resumableApps(in tmp: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        return names.filter { $0.hasSuffix(".resume") }.map { String($0.dropLast(".resume".count)) }.sorted()
    }
}

public extension EpicStore {
    /// The Legendary installs of this game that are running right now, top-level processes only
    /// (Legendary starts a second one under itself). Read from `ps` output; pure so it is tested
    /// without processes. Each entry is the process id and its parent's.
    static func runningInstalls(psOutput: String, appName: String) -> [(pid: pid_t, parent: pid_t)] {
        let found: [(pid: pid_t, parent: pid_t)] = psOutput.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = pid_t(parts[0]), let parent = pid_t(parts[1]) else { return nil }
            let command = String(parts[2])
            // The app name ends at a space or at the end of the line: "abc" is not "abc123".
            let marker = "/legendary install \(appName)"
            guard command.contains(marker + " ") || command.hasSuffix(marker) else { return nil }
            return (pid, parent)
        }
        let ids = Set(found.map(\.pid))
        return found.filter { !ids.contains($0.parent) }
    }

    func runningInstalls(appName: String) -> [(pid: pid_t, parent: pid_t)] {
        let out = (try? Shell.capture("/bin/ps", ["-axo", "pid=,ppid=,command="])) ?? ""
        return Self.runningInstalls(psOutput: out, appName: appName)
    }
}

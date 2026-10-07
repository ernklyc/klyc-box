import XCTest
@testable import KLYCKit

private final class FakeInstall: EpicInstallProcess, @unchecked Sendable {
    let onLine: @Sendable (String) -> Void
    let onExit: @Sendable (Int32) -> Void
    private(set) var interrupts = 0
    init(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) { self.onLine = onLine; self.onExit = onExit }
    func interrupt() { interrupts += 1 }
}

/// Collects the fake processes a starter made; the starter is Sendable, so this is too.
private final class Made: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [FakeInstall] = []
    func add(_ p: FakeInstall) { lock.lock(); all.append(p); lock.unlock() }
    var list: [FakeInstall] { lock.lock(); defer { lock.unlock() }; return all }
}

@MainActor
final class EpicDownloadCenterTests: XCTestCase {
    private let made = Made()
    private var processes: [FakeInstall] { made.list }
    private var starter: EpicDownloadCenter.Starter {
        let made = self.made
        return { _, onLine, onExit in
            let p = FakeInstall(onLine: onLine, onExit: onExit)
            made.add(p)
            return p
        }
    }

    /// Lets the main-actor hops the center makes run.
    private func settle() async { try? await Task.sleep(for: .milliseconds(50)) }

    func testProgressLinesFillTheDownload() async throws {
        let c = EpicDownloadCenter()
        try c.start(appName: "g", title: "Guardians", starter: starter)
        processes[0].onLine("[DLManager] INFO: = Progress: 12.50% (5/40), Running for 00:00:30, ETA: 00:03:30")
        processes[0].onLine("[DLManager] INFO:  + Download\t- 4.00 MiB/s (raw) / 6.00 MiB/s (decompressed)")
        await settle()
        let d = try XCTUnwrap(c.download(for: "g"))
        XCTAssertEqual(d.state, .running)
        XCTAssertEqual(d.progress.percent, 12.5)
        XCTAssertEqual(d.progress.etaSeconds, 210)
        XCTAssertEqual(try XCTUnwrap(d.progress.downloadSpeed), 4 * 1024 * 1024, accuracy: 10)
        XCTAssertTrue(c.isActive)
    }

    func testPauseInterruptsAndTheExitThatFollowsIsAPauseNotAFailure() async throws {
        let c = EpicDownloadCenter()
        var finished: [(String, Bool)] = []
        c.onFinished = { name, _, ok in finished.append((name, ok)) }
        try c.start(appName: "g", title: "Guardians", starter: starter)
        c.pause("g")
        XCTAssertEqual(c.download(for: "g")?.state, .pausing)
        XCTAssertEqual(processes[0].interrupts, 1)
        processes[0].onExit(130)
        await settle()
        XCTAssertEqual(c.download(for: "g")?.state, .paused)
        XCTAssertTrue(finished.isEmpty, "a pause is not the end of the install")
        XCTAssertFalse(c.isActive)
    }

    func testResumeStartsLegendaryAgainAndKeepsWhatWasShown() async throws {
        let c = EpicDownloadCenter()
        try c.start(appName: "g", title: "Guardians", starter: starter)
        processes[0].onLine("= Progress: 40.00% (4/10), Running for 00:01:00, ETA: 00:01:30")
        await settle()
        c.pause("g"); processes[0].onExit(130); await settle()
        try c.resume("g")
        XCTAssertEqual(processes.count, 2, "a new Legendary run, which continues from its saved place")
        XCTAssertEqual(c.download(for: "g")?.state, .running)
        XCTAssertEqual(c.download(for: "g")?.progress.percent, 40, "the last known percentage stays until new lines arrive")
    }

    func testSuccessRemovesItAndTellsTheApp() async throws {
        let c = EpicDownloadCenter()
        var finished: [(String, String, Bool)] = []
        c.onFinished = { finished.append(($0, $1, $2)) }
        try c.start(appName: "g", title: "Guardians", starter: starter)
        processes[0].onExit(0); await settle()
        XCTAssertNil(c.download(for: "g"))
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished.first?.1, "Guardians")
        XCTAssertEqual(finished.first?.2, true)
    }

    func testAStatusZeroRunThatLeftNothingInstalledCanBePutBack() async throws {
        let c = EpicDownloadCenter()
        let logs = LineBox()
        c.onLog = { logs.add($0) }
        try c.start(appName: "g", title: "Guardians", bottleName: "Games", starter: starter)
        processes[0].onLine("= Progress: 24.92% (4/10), Running for 00:01:00, ETA: 00:03:00")
        processes[0].onExit(0); await settle()
        XCTAssertNil(c.download(for: "g"), "a clean exit takes it off the list")
        XCTAssertTrue(logs.lines.contains { $0.contains("status 0") }, "the end is written to the activity log, for finding out why")
        c.reinstate("g")
        let d = try XCTUnwrap(c.download(for: "g"))
        XCTAssertEqual(d.state, .paused)
        XCTAssertEqual(d.progress.percent, 24.92)
        XCTAssertEqual(d.bottleName, "Games")
        try c.resume("g")
        XCTAssertEqual(processes.count, 2, "resuming starts Legendary again")
        c.reinstate("g")   // already on the list: nothing doubles
        XCTAssertEqual(c.downloads.count, 1)
    }

    func testAFailureKeepsTheLastLinesAndCanBeRetried() async throws {
        let c = EpicDownloadCenter()
        var results: [Bool] = []
        c.onFinished = { _, _, ok in results.append(ok) }
        try c.start(appName: "g", title: "Guardians", starter: starter)
        processes[0].onLine("= Progress: 10.00% (1/10), Running for 00:00:10, ETA: 00:01:30")   // noise, not kept
        processes[0].onLine("[cli] ERROR: could not reach the server")
        processes[0].onExit(1); await settle()
        guard case .failed(let why)? = c.download(for: "g")?.state else { return XCTFail("expected a failure") }
        XCTAssertTrue(why.contains("could not reach the server"))
        XCTAssertFalse(why.contains("Progress"), "once-a-second progress lines are not the reason")
        XCTAssertEqual(results, [false])
        try c.resume("g")
        XCTAssertEqual(c.download(for: "g")?.state, .running)
    }

    func testCancelStopsItAndForgetsIt() async throws {
        let c = EpicDownloadCenter()
        var finished = 0
        c.onFinished = { _, _, _ in finished += 1 }
        try c.start(appName: "g", title: "Guardians", starter: starter)
        c.cancel("g")
        XCTAssertEqual(processes[0].interrupts, 1)
        processes[0].onExit(130); await settle()
        XCTAssertNil(c.download(for: "g"))
        XCTAssertEqual(finished, 0, "a cancel is not a finished install")
    }

    func testCancelWhilePausedJustRemovesIt() async throws {
        let c = EpicDownloadCenter()
        try c.start(appName: "g", title: "Guardians", starter: starter)
        c.pause("g"); processes[0].onExit(130); await settle()
        c.cancel("g")
        XCTAssertNil(c.download(for: "g"))
    }

    func testStartingARunningInstallAgainDoesNothing() throws {
        let c = EpicDownloadCenter()
        try c.start(appName: "g", title: "Guardians", starter: starter)
        try c.start(appName: "g", title: "Guardians", starter: starter)
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(c.downloads.count, 1)
    }

    func testPauseAllPausesEveryRunningInstall() async throws {
        let c = EpicDownloadCenter()
        try c.start(appName: "a", title: "A", starter: starter)
        try c.start(appName: "b", title: "B", starter: starter)
        c.pauseAll()
        XCTAssertEqual(processes.map(\.interrupts), [1, 1])
    }

    func testAStarterThatThrowsLeavesNothingBehind() {
        struct Boom: Error {}
        let c = EpicDownloadCenter()
        XCTAssertThrowsError(try c.start(appName: "g", title: "G", starter: { _, _, _ in throw Boom() }))
        XCTAssertTrue(c.downloads.isEmpty)
    }
}

/// A real child process standing in for Legendary: prints progress, and on Ctrl-C says so and exits 130.
final class LegendaryProcessTests: XCTestCase {
    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [String] = []
        private var status: Int32?
        func add(_ l: String) { lock.lock(); all.append(l); lock.unlock() }
        func end(_ s: Int32) { lock.lock(); status = s; lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return all }
        var exit: Int32? { lock.lock(); defer { lock.unlock() }; return status }
    }

    private func wait(for condition: () -> Bool, seconds: Double = 5) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testInterruptStopsTheProcessLikeCtrlC() async throws {
        let seen = Lines()
        let script = #"trap 'echo "KeyboardInterrupt, saving"; exit 130' INT; echo "= Progress: 5.00% (1/20), Running for 00:00:01, ETA: 00:00:19"; while true; do sleep 0.05; done"#
        let p = try LegendaryProcess(binary: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: [:],
                                     onLine: { seen.add($0) }, onExit: { seen.end($0) })
        await wait { seen.lines.contains { $0.contains("Progress") } }
        XCTAssertTrue(seen.lines.contains { $0.contains("5.00%") }, "lines arrive while it runs")
        p.interrupt()
        await wait { seen.exit != nil }
        XCTAssertEqual(seen.exit, 130)
        XCTAssertTrue(seen.lines.contains { $0.contains("saving") })
    }

    func testCarriageReturnsSplitLinesAndANormalExitIsReported() async throws {
        let seen = Lines()
        let p = try LegendaryProcess(binary: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", #"printf 'one\rtwo\nthree'"#], environment: [:],
                                     onLine: { seen.add($0) }, onExit: { seen.end($0) })
        await wait { seen.exit != nil }
        XCTAssertEqual(seen.exit, 0)
        XCTAssertEqual(seen.lines, ["one", "two", "three"])
        p.interrupt()   // after it ended: harmless
    }
}

@MainActor
final class EpicDownloadRestoreTests: XCTestCase {
    func testPendingTakesWhatWasSavedAndWhatLegendaryHasResumeDataFor() {
        let saved = EpicDownloadFile(downloads: [SavedEpicDownload(appName: "a", title: "A", percent: 40)], dismissed: [])
        let pending = EpicDownloadStore.pending(file: saved, resumable: ["a", "old"], installed: [], titles: ["old": "From an older version"])
        XCTAssertEqual(pending.map(\.appName), ["a", "old"])
        XCTAssertEqual(pending.first?.percent, 40, "saved progress is kept")
        XCTAssertEqual(pending.last?.title, "From an older version")
    }

    func testPendingDropsInstalledCancelledAndOrphanedOnes() {
        let saved = EpicDownloadFile(downloads: [SavedEpicDownload(appName: "done", title: "Done"),
                                                 SavedEpicDownload(appName: "gone", title: "No resume file any more"),
                                                 SavedEpicDownload(appName: "nope", title: "Cancelled")],
                                     dismissed: ["nope", "cancelled-old"])
        let pending = EpicDownloadStore.pending(file: saved, resumable: ["done", "nope", "cancelled-old", "unknown"],
                                                installed: ["done"], titles: ["cancelled-old": "Cancelled, older", "unknown": ""])
        XCTAssertEqual(pending.map(\.appName), ["unknown"], "installed, cancelled and file-less ones are not brought back; a title-less one is named by its titles entry")
    }

    func testRestoredDownloadsComeUpPausedAndCanBeResumed() throws {
        let c = EpicDownloadCenter()
        let started = StartCount()
        c.restore([SavedEpicDownload(appName: "g", title: "Guardians", bottleName: "Games", percent: 62.5, downloadedBytes: 100, downloadSize: 200)]) { _ in
            { _, onLine, onExit in started.bump(); return FakeInstall(onLine: onLine, onExit: onExit) }
        }
        let d = try XCTUnwrap(c.download(for: "g"))
        XCTAssertEqual(d.state, .paused)
        XCTAssertEqual(d.progress.percent, 62.5)
        XCTAssertEqual(d.bottleName, "Games")
        XCTAssertFalse(c.isActive)
        try c.resume("g")
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(c.download(for: "g")?.state, .running)
        // Restoring again does not duplicate or disturb a live one.
        c.restore([SavedEpicDownload(appName: "g", title: "Guardians")]) { _ in { _, _, _ in throw NSError(domain: "x", code: 1) } }
        XCTAssertEqual(c.downloads.count, 1)
    }

    func testPersistingFollowsTheListAndThrottlesProgress() async throws {
        let c = EpicDownloadCenter()
        let calls = StartCount()
        c.onPersist = { _ in calls.bump() }
        let made = FakeBox()
        try c.start(appName: "g", title: "G", bottleName: "Games") { _, onLine, onExit in
            let p = FakeInstall(onLine: onLine, onExit: onExit); made.set(p); return p
        }
        XCTAssertEqual(calls.count, 1, "starting is saved")
        let p = try XCTUnwrap(made.value)
        for i in 1...30 { p.onLine("= Progress: \(i).00% (1/10), Running for 00:00:01, ETA: 00:00:10") }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertLessThanOrEqual(calls.count, 2, "thirty progress lines in a moment are not thirty writes")
        XCTAssertEqual(c.snapshot.first?.bottleName, "Games")
        XCTAssertEqual(c.snapshot.first?.percent, 30)
        c.pause("g"); p.onExit(130)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertGreaterThanOrEqual(calls.count, 2, "the pause is saved")
    }

    func testCancelTellsTheAppSoItIsNotBroughtBack() async throws {
        // Cancelled while running: told once the process has exited.
        let c = EpicDownloadCenter()
        let cancelled = NameBox()
        c.onCancelled = { cancelled.set($0) }
        let made = FakeBox()
        try c.start(appName: "g", title: "G") { _, onLine, onExit in
            let p = FakeInstall(onLine: onLine, onExit: onExit); made.set(p); return p
        }
        c.cancel("g")
        XCTAssertNil(cancelled.value, "not yet: it is still stopping")
        made.value?.onExit(130)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(cancelled.value, "g")
        XCTAssertNil(c.download(for: "g"))

        // Cancelled while paused: told at once.
        let c2 = EpicDownloadCenter()
        let cancelled2 = NameBox()
        c2.onCancelled = { cancelled2.set($0) }
        let made2 = FakeBox()
        try c2.start(appName: "h", title: "H") { _, onLine, onExit in
            let p = FakeInstall(onLine: onLine, onExit: onExit); made2.set(p); return p
        }
        c2.pause("h"); made2.value?.onExit(130)
        try await Task.sleep(for: .milliseconds(80))
        c2.cancel("h")
        XCTAssertEqual(cancelled2.value, "h")
        XCTAssertNil(c2.download(for: "h"))
    }

    func testFileRoundTripAndEmptyDeletesIt() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "epicdl-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "epic-downloads.json")
        XCTAssertEqual(EpicDownloadStore.load(from: file), EpicDownloadFile(), "no file is an empty list")
        let content = EpicDownloadFile(downloads: [SavedEpicDownload(appName: "g", title: "G", bottleName: "Games", percent: 5)], dismissed: ["x"])
        EpicDownloadStore.save(content, to: file)
        XCTAssertEqual(EpicDownloadStore.load(from: file), content)
        EpicDownloadStore.save(EpicDownloadFile(), to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try Data("not json".utf8).write(to: dir.appending(path: "bad.json"))
        XCTAssertEqual(EpicDownloadStore.load(from: dir.appending(path: "bad.json")), EpicDownloadFile())
    }

    func testResumableAppsComeFromTheResumeFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tmp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appending(path: "63a665.resume"))
        try Data().write(to: dir.appending(path: "other.txt"))
        XCTAssertEqual(EpicDownloadStore.resumableApps(in: dir), ["63a665"])
        XCTAssertEqual(EpicDownloadStore.resumableApps(in: dir.appending(path: "missing")), [])
    }
}

private final class StartCount: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}
private final class FakeBox: @unchecked Sendable {
    private let lock = NSLock(); private var p: FakeInstall?
    func set(_ v: FakeInstall) { lock.lock(); p = v; lock.unlock() }
    var value: FakeInstall? { lock.lock(); defer { lock.unlock() }; return p }
}
private final class NameBox: @unchecked Sendable {
    private let lock = NSLock(); private var s: String?
    func set(_ v: String) { lock.lock(); s = v; lock.unlock() }
    var value: String? { lock.lock(); defer { lock.unlock() }; return s }
}

@MainActor
final class EpicOfflineTitleTests: XCTestCase {
    func testTheTitleComesFromLegendarysOwnCopyOfTheCatalog() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "meta-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"app_name":"abc","app_title":"Marvel's Guardians of the Galaxy","metadata":{}}"#.write(to: dir.appending(path: "abc.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appending(path: "bad.json"), atomically: true, encoding: .utf8)
        try #"{"app_title":""}"#.write(to: dir.appending(path: "empty.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(EpicDownloadStore.title(forApp: "abc", metadata: dir), "Marvel's Guardians of the Galaxy")
        XCTAssertNil(EpicDownloadStore.title(forApp: "bad", metadata: dir))
        XCTAssertNil(EpicDownloadStore.title(forApp: "empty", metadata: dir))
        XCTAssertNil(EpicDownloadStore.title(forApp: "missing", metadata: dir))
    }

    func testInstalledLeftoversAreDiscardedButARunningInstallIsNot() throws {
        let c = EpicDownloadCenter()
        c.restore([SavedEpicDownload(appName: "old", title: "Old"), SavedEpicDownload(appName: "keep", title: "Keep")]) { _ in { _, _, _ in throw NSError(domain: "x", code: 1) } }
        try c.start(appName: "live", title: "Live") { _, onLine, onExit in FakeInstall(onLine: onLine, onExit: onExit) }
        c.discard(installed: ["old", "live"])
        XCTAssertEqual(c.downloads.map(\.appName).sorted(), ["keep", "live"], "a running install is never discarded; a paused leftover of an installed game is")
    }
}


final class RunningInstallsTests: XCTestCase {
    private let ps = """
      4844  4690 /Users/me/KLYC-Data/tools/legendary install 63a665 --platform Windows --base-path /x
      4845  4844 /Users/me/KLYC-Data/tools/legendary install 63a665 --platform Windows --base-path /x
     99375     1 /Users/me/KLYC-Data/tools/legendary install 63a665 --platform Windows --base-path /x
     99377 99375 /Users/me/KLYC-Data/tools/legendary install 63a665 --platform Windows --base-path /x
       777     1 /Users/me/KLYC-Data/tools/legendary install other --platform Windows
       800     1 /usr/bin/vim legendary install 63a665.txt
      3001     1 /Users/me/KLYC-Data/tools/legendary -O -B -S -I -c from multiprocessing.resource_tracker import main;main(7)
    """

    func testTopLevelInstallsOfThatGameOnly() {
        let found = EpicStore.runningInstalls(psOutput: ps, appName: "63a665")
        XCTAssertEqual(found.map(\.pid).sorted(), [4844, 99375], "the helper processes under each are not listed, other games and other programs are ignored")
        XCTAssertEqual(found.first { $0.pid == 99375 }?.parent, 1, "an orphan has parent 1")
    }

    func testNothingRunningGivesNothing() {
        XCTAssertTrue(EpicStore.runningInstalls(psOutput: "", appName: "g").isEmpty)
        XCTAssertTrue(EpicStore.runningInstalls(psOutput: ps, appName: "missing").isEmpty)
    }

    func testAnAppNameThatIsAPrefixOfAnotherIsNotConfused() {
        let out = "  10     1 /t/legendary install abc123 --platform Windows\n"
        XCTAssertTrue(EpicStore.runningInstalls(psOutput: out, appName: "abc").isEmpty, "abc is not abc123")
        XCTAssertEqual(EpicStore.runningInstalls(psOutput: out, appName: "abc123").map(\.pid), [10])
        XCTAssertEqual(EpicStore.runningInstalls(psOutput: "  11     1 /t/legendary install abc\n", appName: "abc").map(\.pid), [11], "an install with no arguments after the name")
    }
}


private final class LineBox: @unchecked Sendable {
    private let lock = NSLock(); private var all: [String] = []
    func add(_ l: String) { lock.lock(); all.append(l); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return all }
}

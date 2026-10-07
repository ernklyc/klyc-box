import XCTest
@testable import KLYCKit

final class TaskManagerTests: XCTestCase {
    private func reading(_ pid: pid_t, _ name: String, system: Bool = false, mem: UInt64 = 1, cpu: UInt64 = 0) -> ProcessReading {
        ProcessReading(pid: pid, name: name, isSystem: system, memoryBytes: mem, cpuNanos: cpu, startedAt: nil)
    }

    func testDisplayNameTakesTheFileNameFromWindowsAndUnixPaths() {
        XCTAssertEqual(ProcessSampler.displayName(arguments: ["C:\\windows\\system32\\services.exe"], fallback: "wine"), "services.exe")
        XCTAssertEqual(ProcessSampler.displayName(arguments: ["/Applications/x/Steam.exe", "-silent"], fallback: "wine"), "Steam.exe")
        XCTAssertEqual(ProcessSampler.displayName(arguments: [], fallback: "wine-preloader"), "wine-preloader")
        XCTAssertEqual(ProcessSampler.displayName(arguments: [""], fallback: "x"), "x")
    }

    func testCPUPercentIsTheShareOfTheInterval() {
        // 1 s of CPU in 2 s of wall time is 50 % of one core; four cores busy reads up to 400.
        XCTAssertEqual(ProcessSampler.cpuPercent(previous: 0, current: 1_000_000_000, seconds: 2), 50, accuracy: 0.001)
        XCTAssertEqual(ProcessSampler.cpuPercent(previous: 0, current: 8_000_000_000, seconds: 2), 400, accuracy: 0.001)
        XCTAssertEqual(ProcessSampler.cpuPercent(previous: 5, current: 1, seconds: 2), 0, "a restarted pid never reads negative or huge")
        XCTAssertEqual(ProcessSampler.cpuPercent(previous: 0, current: 5, seconds: 0), 0)
    }

    func testUptimeSplitsIntoUnits() {
        let start = Date(timeIntervalSince1970: 1000)
        let u = ProcessSampler.uptime(from: start, to: start.addingTimeInterval(3 * 3600 + 5 * 60 + 9))
        XCTAssertEqual([u.hours, u.minutes, u.seconds], [3, 5, 9])
        XCTAssertEqual(ProcessSampler.uptime(from: start, to: start.addingTimeInterval(-5)).seconds, 0)
    }

    @MainActor func testFirstReadingHasNoCPUThenTheDeltaShows() {
        let model = TaskManagerModel(sampler: { [] }, ownSampler: { nil }, stopper: { _ in })
        let t0 = Date(timeIntervalSince1970: 100)
        model.ingest([reading(1, "game.exe", cpu: 0)], at: t0)
        XCTAssertEqual(model.rows.first?.cpuPercent, 0)
        model.ingest([reading(1, "game.exe", cpu: 2_000_000_000)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(model.rows.first?.cpuPercent ?? 0, 100, accuracy: 0.001)
    }

    @MainActor func testProgramsComeFirstHeaviestFirstThenPlumbingByName() {
        let model = TaskManagerModel(sampler: { [] }, ownSampler: { nil }, stopper: { _ in })
        model.ingest([
            reading(1, "services.exe", system: true, mem: 900),
            reading(2, "small.exe", mem: 10),
            reading(3, "big.exe", mem: 500),
            reading(4, "explorer.exe", system: true, mem: 1),
        ])
        XCTAssertEqual(model.rows.map(\.name), ["big.exe", "small.exe", "explorer.exe", "services.exe"])
        XCTAssertEqual(model.programs.count, 2)
        XCTAssertEqual(model.system.count, 2)
        XCTAssertEqual(model.totalMemory, 1411)
    }

    @MainActor func testOwnReadingIsKeptApartFromTheList() {
        let model = TaskManagerModel(sampler: { [] }, ownSampler: { nil }, stopper: { _ in })
        model.ingest([], own: reading(99, "KLYC-Box", mem: 123))
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.app?.memoryBytes, 123)
    }

    @MainActor func testStoppingMarksTheRowUntilItDisappears() {
        let stopped = Locked<[pid_t]>([])
        let model = TaskManagerModel(sampler: { [] }, ownSampler: { nil }, stopper: { pids in stopped.mutate { $0 += pids } })
        model.ingest([reading(7, "a.exe"), reading(8, "b.exe")])
        model.stop(pids: [7])
        XCTAssertTrue(model.stopping.contains(7))
        model.ingest([reading(8, "b.exe")])
        XCTAssertTrue(model.stopping.isEmpty, "a process that is gone is no longer 'stopping'")
        let exp = expectation(description: "stopper ran")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(stopped.value, [7])
    }

    func testReadingOurOwnProcessWorks() throws {
        let me = try XCTUnwrap(ProcessSampler.ownReading())
        XCTAssertEqual(me.pid, getpid())
        XCTAssertGreaterThan(me.memoryBytes, 0)
        XCTAssertFalse(me.name.isEmpty)
        XCTAssertNotNil(me.startedAt)
    }
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}

final class GameMemoryTests: XCTestCase {
    private let gb: UInt64 = 1_073_741_824

    func testLevelsFollowTheShareOfPhysicalMemory() {
        XCTAssertEqual(GameMemory.level(gameBytes: 4 * gb, physicalBytes: 16 * gb), .fine)
        XCTAssertEqual(GameMemory.level(gameBytes: 10 * gb, physicalBytes: 16 * gb), .high)       // 62 %
        XCTAssertEqual(GameMemory.level(gameBytes: 13 * gb, physicalBytes: 16 * gb), .critical)   // 81 %
    }

    func testTheBoundariesBelongToTheHigherLevel() {
        XCTAssertEqual(GameMemory.level(gameBytes: 60, physicalBytes: 100), .high)
        XCTAssertEqual(GameMemory.level(gameBytes: 59, physicalBytes: 100), .fine)
        XCTAssertEqual(GameMemory.level(gameBytes: 80, physicalBytes: 100), .critical)
    }

    func testUnknownPhysicalMemoryNeverWarns() {
        XCTAssertEqual(GameMemory.level(gameBytes: 100 * gb, physicalBytes: 0), .fine)
        XCTAssertEqual(GameMemory.percent(gameBytes: 5, physicalBytes: 0), 0)
        XCTAssertEqual(GameMemory.percent(gameBytes: 8 * gb, physicalBytes: 16 * gb), 50)
    }
}

final class ThermalAdviceTests: XCTestCase {
    func testOnlySeriousAndCriticalAreWorthASentence() {
        XCTAssertEqual(ThermalAdvice.level(.nominal), .fine)
        XCTAssertEqual(ThermalAdvice.level(.fair), .fine, "a Mac under load is normally fair")
        XCTAssertEqual(ThermalAdvice.level(.serious), .warm)
        XCTAssertEqual(ThermalAdvice.level(.critical), .hot)
    }
}

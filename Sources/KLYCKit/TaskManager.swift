import Foundation
import Darwin
import Observation

// MARK: - Readings

/// One look at one process: what the kernel reports right now. CPU is a running total, so a
/// percentage needs two readings (`TaskManagerModel` keeps the previous one).
public struct ProcessReading: Hashable, Sendable {
    public var pid: pid_t
    public var name: String
    /// Wine's own plumbing (server, services, explorer) rather than a program someone started.
    public var isSystem: Bool
    /// Physical memory footprint, the number Activity Monitor shows as "Memory".
    public var memoryBytes: UInt64
    /// User + system CPU time since the process began, in nanoseconds.
    public var cpuNanos: UInt64
    public var startedAt: Date?

    public init(pid: pid_t, name: String, isSystem: Bool, memoryBytes: UInt64, cpuNanos: UInt64, startedAt: Date?) {
        self.pid = pid; self.name = name; self.isSystem = isSystem
        self.memoryBytes = memoryBytes; self.cpuNanos = cpuNanos; self.startedAt = startedAt
    }
}

public enum ProcessSampler {
    /// The name a person would recognise: the program's file name, whether Wine reports it as a
    /// Windows path (`C:\windows\system32\services.exe`) or a Unix one. Pure.
    public static func displayName(arguments: [String], fallback: String) -> String {
        guard let first = arguments.first, !first.isEmpty else { return fallback }
        let base = first.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? first
        return base.isEmpty ? fallback : base
    }

    /// CPU use over an interval, in percent of one core (a game on four cores reads up to 400).
    /// Pure; a process that restarted (total went backwards) reads 0, not a huge number.
    public static func cpuPercent(previous: UInt64, current: UInt64, seconds: Double) -> Double {
        guard seconds > 0, current >= previous else { return 0 }
        return Double(current - previous) / 1_000_000_000 / seconds * 100
    }

    /// A short, human uptime: "45 sn", "12 dk", "3 sa 05 dk". Callers localise the units.
    public static func uptime(from start: Date, to now: Date) -> (hours: Int, minutes: Int, seconds: Int) {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    /// Reads one process we are allowed to see. Nil when it is gone or off limits.
    public static func reading(of pid: pid_t, isSystem: Bool) -> ProcessReading? {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard ok == 0 else { return nil }

        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        var started: Date?
        var comm = ""
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize {
            started = Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec))
            comm = withUnsafePointer(to: &bsd.pbi_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
        }
        let args = ProcessTable.commandLineAndEnvironment(of: pid)?.arguments ?? []
        let mach = usage.ri_user_time &+ usage.ri_system_time
        return ProcessReading(
            pid: pid,
            name: displayName(arguments: args, fallback: comm.isEmpty ? "pid \(pid)" : comm),
            isSystem: isSystem,
            memoryBytes: usage.ri_phys_footprint,
            cpuNanos: mach &* timebase.numer / timebase.denom,
            startedAt: started)
    }

    /// Every process of the prefix, programs and plumbing, never this app.
    public static func readings(ofPrefix prefix: URL) -> [ProcessReading] {
        ProcessTable.processes(ofPrefix: prefix).compactMap {
            reading(of: $0, isSystem: ProcessTable.isPlumbing($0, prefix: prefix))
        }
    }

    /// This app, for the "what does KLYC-Box itself cost" line.
    public static func ownReading() -> ProcessReading? {
        reading(of: getpid(), isSystem: false)
    }
}

// MARK: - The model

/// A process as the list shows it: a reading plus the CPU share worked out from the one before.
public struct ProcessRow: Identifiable, Hashable, Sendable {
    public var id: pid_t { reading.pid }
    public var reading: ProcessReading
    public var cpuPercent: Double
    public var pid: pid_t { reading.pid }
    public var name: String { reading.name }
    public var isSystem: Bool { reading.isSystem }
    public var memoryBytes: UInt64 { reading.memoryBytes }
}

/// Task manager of one environment: refreshes while its screen is visible, shows programs first
/// and Wine's plumbing below, and ends processes. The reads and the stop are injected, so the
/// tests run without real processes.
@Observable @MainActor
public final class TaskManagerModel {
    public typealias Sampler = @Sendable () -> [ProcessReading]
    public typealias Stopper = @Sendable ([pid_t]) -> Void

    public private(set) var rows: [ProcessRow] = []
    public private(set) var app: ProcessRow?
    public private(set) var lastUpdate: Date?
    public private(set) var stopping: Set<pid_t> = []

    private let sampler: Sampler
    private let ownSampler: @Sendable () -> ProcessReading?
    private let stopper: Stopper
    private var previous: [pid_t: ProcessReading] = [:]
    private var previousAt: Date?
    private var previousApp: ProcessReading?

    public init(sampler: @escaping Sampler,
                ownSampler: @escaping @Sendable () -> ProcessReading? = { ProcessSampler.ownReading() },
                stopper: @escaping Stopper = { ProcessTable.terminate($0) }) {
        self.sampler = sampler
        self.ownSampler = ownSampler
        self.stopper = stopper
    }

    public var programs: [ProcessRow] { rows.filter { !$0.isSystem } }
    public var system: [ProcessRow] { rows.filter { $0.isSystem } }
    public var totalMemory: UInt64 { rows.reduce(0) { $0 + $1.memoryBytes } }
    public var totalCPU: Double { rows.reduce(0) { $0 + $1.cpuPercent } }

    /// Folds a new set of readings in. Programs sort by memory, the heaviest first; plumbing by
    /// name, so it does not jump around.
    public func ingest(_ readings: [ProcessReading], own: ProcessReading? = nil, at now: Date = Date()) {
        let seconds = previousAt.map { now.timeIntervalSince($0) } ?? 0
        let built = readings.map { r in
            ProcessRow(reading: r, cpuPercent: previous[r.pid].map {
                ProcessSampler.cpuPercent(previous: $0.cpuNanos, current: r.cpuNanos, seconds: seconds)
            } ?? 0)
        }
        rows = built.sorted {
            if $0.isSystem != $1.isSystem { return !$0.isSystem }
            return $0.isSystem ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                               : $0.memoryBytes > $1.memoryBytes
        }
        if let own {
            app = ProcessRow(reading: own, cpuPercent: previousApp.map {
                ProcessSampler.cpuPercent(previous: $0.cpuNanos, current: own.cpuNanos, seconds: seconds)
            } ?? 0)
            previousApp = own
        }
        previous = Dictionary(uniqueKeysWithValues: readings.map { ($0.pid, $0) })
        previousAt = now
        lastUpdate = now
        stopping.formIntersection(Set(readings.map(\.pid)))
    }

    public func refresh() async {
        let sampler = self.sampler, ownSampler = self.ownSampler
        let (readings, own) = await Task.detached(priority: .utility) { (sampler(), ownSampler()) }.value
        guard !Task.isCancelled else { return }
        ingest(readings, own: own)
    }

    /// Refreshes every `interval` seconds until cancelled (the screen's `.task` ends with it).
    public func run(every interval: Duration = .seconds(2)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }

    /// Ends one program, off the main thread; its row says "stopping" until it disappears.
    public func stop(_ row: ProcessRow) {
        stop(pids: [row.pid])
    }

    public func stop(pids: [pid_t]) {
        stopping.formUnion(pids)
        let stopper = self.stopper
        Task.detached(priority: .userInitiated) { stopper(pids) }
    }
}

// MARK: - A running game's memory

/// How much of the Mac's memory a game holds. The share is of physical memory, the number a
/// player knows ("16 GB"); Apple Silicon shares it with the GPU, so a game near the top makes
/// the Mac swap and stutter before it fails.
public enum GameMemory {
    public enum Level: Equatable, Sendable { case fine, high, critical }

    public static let highShare = 0.6
    public static let criticalShare = 0.8

    public static func level(gameBytes: UInt64, physicalBytes: UInt64) -> Level {
        guard physicalBytes > 0 else { return .fine }
        let share = Double(gameBytes) / Double(physicalBytes)
        if share >= criticalShare { return .critical }
        return share >= highShare ? .high : .fine
    }

    public static func percent(gameBytes: UInt64, physicalBytes: UInt64) -> Int {
        physicalBytes > 0 ? Int((Double(gameBytes) / Double(physicalBytes) * 100).rounded()) : 0
    }
}

// MARK: - The Mac's temperature while a game runs

/// What the system's thermal state means for a running game. `serious` is where macOS starts
/// holding the chip back (the game's frame rate drops without the game doing anything wrong);
/// `critical` is where it holds back hard. `fair` is the normal state of a Mac under load and
/// says nothing a player needs.
public enum ThermalAdvice {
    public enum Level: Equatable, Sendable { case fine, warm, hot }

    public static func level(_ state: ProcessInfo.ThermalState) -> Level {
        switch state {
        case .nominal, .fair: return .fine
        case .serious: return .warm
        case .critical: return .hot
        @unknown default: return .fine
        }
    }
}

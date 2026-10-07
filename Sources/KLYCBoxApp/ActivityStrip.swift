import SwiftUI
import KLYCKit

/// One place for everything that takes time (UX plan §3.3): the busy operation with its bytes,
/// stated range and elapsed time, a finished operation with its next step, and every running
/// game. Always at the bottom of the window, never modal, never a bare spinner. Details opens
/// the log sheet.
struct ActivityStrip: View {
    @Environment(AppState.self) private var state
    @State private var fpsText = ""
    @State private var askingFPS = false

    var body: some View {
        if state.busy || state.doneState != nil || state.postPlay != nil || !state.runningSessions.isEmpty || !steamBottles.isEmpty || !state.epicDownloads.downloads.isEmpty {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 0) {
                    if state.busy {
                        busyRow
                    } else if let done = state.doneState {
                        doneRow(done)
                    }
                    ForEach(state.epicDownloads.downloads) { EpicDownloadRow(download: $0, compact: true) }
                    if let record = state.postPlay { postPlayRow(record) }
                    ForEach(state.runningSessions) { session in
                        sessionRow(session)
                    }
                    ForEach(steamBottles, id: \.name) { bottle in
                        steamRow(bottle)
                    }
                }
            }
            .hbGlass(Rectangle())
            .transition(.opacity)
        }
    }

    /// Bottles whose Steam client runs, in sidebar order.
    private var steamBottles: [Bottle] { state.bottles.filter { state.steamClients.contains($0.name) } }

    // MARK: Rows

    private var busyRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.busyTitle).font(.callout.weight(.medium)).lineLimit(1)
                    if !state.stage.isEmpty || !state.stageHint.isEmpty {
                        Text([state.stage, state.stageHint].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(measurements(at: ctx.date))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                if let stop = state.busyStop {
                    Button(stop.label) { state.stopBusy() }.controlSize(.small)
                }
                Button(L("Details")) { state.showLog = true }.controlSize(.small).buttonStyle(HBTextButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            // A determinate bar when bytes are known; nothing invented when they are not.
            if let p = state.busyProgress, let fraction = ActivityText.fraction(received: p.received, total: p.total) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(0.08))
                        Rectangle().fill(HB.amber).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    /// Bytes and rate when a download runs, elapsed always, the stated range when there is one.
    private func measurements(at now: Date) -> String {
        var parts: [String] = []
        if let p = state.busyProgress, p.received > 0 {
            parts.append(ActivityText.transfer(received: p.received, total: p.total, rate: state.transferRate))
        }
        if let started = state.busyStartedAt {
            let e = ActivityText.elapsed(since: started, now: now)
            if e.asSeconds, e.amount == 0 {
                parts.append(L("just started"))
            } else {
                parts.append(String(format: e.asSeconds ? L("%d sec") : L("%d min"), e.amount))
            }
        }
        if let expected = state.busyExpected { parts.append(expected) }
        if state.busyProgress == nil, let last = state.lastOutputAt, now.timeIntervalSince(last) >= 90, state.stageHint.isEmpty {
            parts.append(L("quiet"))
        }
        return parts.joined(separator: " · ")
    }

    private func doneRow(_ done: AppState.DoneState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(HB.good)
            Text(done.title).font(.callout.weight(.medium)).lineLimit(1)
            Spacer(minLength: 12)
            if let cta = done.ctaTitle {
                Button(cta) { state.doneState = nil; done.cta?() }
                    .buttonStyle(HBCompactButtonStyle())
            }
            Button(L("Details")) { state.showLog = true }.controlSize(.small).buttonStyle(HBTextButtonStyle())
            Button(L("Dismiss")) { state.doneState = nil }.controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// A Steam client with no window of its own in the app: Show brings its window forward,
    /// Quit ends it (hidden while a known game runs in that bottle, since it would go too).
    private func steamRow(_ bottle: Bottle) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.secondary).frame(width: 8, height: 8).padding(.horizontal, 4)
            Text(state.bottles.count > 1 ? String(format: L("Steam is running in %@"), bottle.name) : L("Steam is running"))
                .font(.callout.weight(.medium)).lineLimit(1)
            Spacer(minLength: 12)
            Button(L("Show")) { state.showSteam(in: bottle) }.controlSize(.small).disabled(state.busy)
            if !state.sessionRuns(in: bottle) {
                Button(L("Quit")) { state.quitSteam(in: bottle) }.controlSize(.small).disabled(state.busy)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// Asked after play, never before (UX plan §3.5). Both answers open a prefilled form in the
    /// browser: a compatibility report for the database, or a problem report with the log.
    private func postPlayRow(_ record: SessionRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            if askingFPS {
                Text(L("How many frames per second did you see? (optional)")).font(.callout.weight(.medium)).lineLimit(1)
                TextField("60", text: $fpsText).textFieldStyle(.roundedBorder).frame(width: 64)
                    .onSubmit { savePlayedFine(record) }
                Spacer(minLength: 12)
                Button(L("Save")) { savePlayedFine(record) }.buttonStyle(HBCompactButtonStyle())
                Button(L("Skip")) { fpsText = ""; savePlayedFine(record) }.buttonStyle(HBTextButtonStyle()).controlSize(.small)
            } else {
                Text(String(format: L("How did %@ go?"), record.title)).font(.callout.weight(.medium)).lineLimit(1)
                Text(String(format: L("%d min"), record.seconds / 60)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button(L("It played fine")) { askingFPS = true }.buttonStyle(HBCompactButtonStyle())
                // A bad session first gets the one thing that most often fixes it, another mode for this
                // game; the answer is kept either way.
                Button(L("Had problems")) {
                    state.recordVerdict(from: record, works: false, fps: nil)
                    state.offerRendererTrial(for: record)
                }.buttonStyle(HBCompactButtonStyle())
                Button(L("Not now")) { state.postPlay = nil }.controlSize(.small).buttonStyle(HBTextButtonStyle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func savePlayedFine(_ record: SessionRecord) {
        state.recordVerdict(from: record, works: true, fps: Int(fpsText.trimmingCharacters(in: .whitespaces)))
        fpsText = ""; askingFPS = false
    }

    /// Opt-in install statistics (UX plan 0.7): asked once, after the first game, and the text
    /// is shown before anything leaves the Mac. Aggregate counts, no game names.

    private func sessionRow(_ session: GameSession) -> some View {
        HStack(spacing: 10) {
            Circle().fill(HB.good).frame(width: 8, height: 8).padding(.horizontal, 4)
            Text(String(format: L("%@ is running"), session.title)).font(.callout.weight(.medium)).lineLimit(1)
            Spacer(minLength: 12)
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                Text(ActivityText.minutes(since: session.started, now: ctx.date).map { String(format: L("%d min"), $0) } ?? L("just started"))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            SessionUsage(session: session)
            Button(L("Stop")) { state.stopSession(session) }.controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// What the running game costs right now: its memory and processor, read by `AppState` from
/// the game's own processes for as long as the session runs, and a plain warning when it holds
/// most of the Mac's memory. One click opens the task manager for the details.
private struct SessionUsage: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    let session: GameSession
    @State private var thermal = ThermalAdvice.level(ProcessInfo.processInfo.thermalState)

    private var physical: UInt64 { ProcessInfo.processInfo.physicalMemory }

    var body: some View {
        // The Mac's temperature matters whether or not the readings have arrived yet.
        Group {
            if thermal != .fine {
                Image(systemName: "thermometer.high").foregroundStyle(thermal == .hot ? HB.bad : HB.amber)
                    .help(thermal == .hot
                          ? L("This Mac is very hot and is slowing the game down. Cap the frame rate in the game's Play options, or let the Mac cool.")
                          : L("This Mac is running hot and may slow the game down. Capping the frame rate in the game's Play options keeps it cooler."))
            }
            usage
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermal = ThermalAdvice.level(ProcessInfo.processInfo.thermalState)
        }
    }

    @ViewBuilder private var usage: some View {
        if let model = state.sessionUsage[session.id], model.lastUpdate != nil, !model.rows.isEmpty {
            let bytes = model.totalMemory
            let level = GameMemory.level(gameBytes: bytes, physicalBytes: physical)
            HStack(spacing: 8) {
                if level != .fine {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(level == .critical ? HB.bad : HB.amber)
                        .help(level == .critical
                              ? L("The game holds most of this Mac's memory. Close other apps; if it freezes, Stop it.")
                              : L("The game holds a lot of this Mac's memory. Closing other apps can help."))
                }
                Text("\(TaskManagerPane.memory(bytes)) · \(TaskManagerPane.percent(model.totalCPU))")
                    .font(.caption.monospacedDigit()).foregroundStyle(level == .fine ? Color.secondary : (level == .critical ? HB.bad : HB.amber))
                Button { state.settingsTab = .tasks; openSettings() } label: { Image(systemName: "gauge.with.dots.needle.50percent") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Task manager"))
            }
        }
    }
}

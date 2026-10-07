import SwiftUI
import KLYCKit

/// Settings → Task manager: what runs in the environment (programs first, Wine's own plumbing
/// below), what each costs, and a Stop for each program. Refreshes every two seconds while the
/// page is open and not at all otherwise.
struct TaskManagerPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TaskManagerModel?

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: HB.Space.m) { content() }
            .padding(HB.Space.l).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: HB.Metric.radius)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HB.Space.l) {
                if let model, let bottle = state.defaultBottle {
                    summaryCard(model, bottle: bottle)
                    processCard(model, title: L("Programs"), rows: model.programs, canStop: true,
                                empty: L("Nothing is running in this environment."))
                    if !model.system.isEmpty {
                        processCard(model, title: L("Windows system"), rows: model.system, canStop: false, empty: "")
                    }
                    Text(L("Updates every two seconds while this page is open. Wine's own background processes are listed below the programs; they are started and stopped with the environment, so they have no Stop button."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if state.defaultBottle == nil {
                    card { Text(L("Nothing is running in this environment.")).foregroundStyle(.secondary) }
                }
            }
            .padding(.vertical, 20).padding(.leading, 20).padding(.trailing, HB.Metric.margin)
        }
        // One loop per visible page: it ends with the page, and pauses while the window is behind.
        .task(id: "\(state.defaultBottle?.name ?? "-")\(scenePhase == .active)") {
            guard let bottle = state.defaultBottle else { model = nil; return }
            let prefix = bottle.url
            let m = model ?? TaskManagerModel(sampler: { ProcessSampler.readings(ofPrefix: prefix) })
            model = m
            guard scenePhase == .active else { return }
            await m.run()
        }
    }

    // MARK: Cards

    private func summaryCard(_ model: TaskManagerModel, bottle: Bottle) -> some View {
        card {
            HStack(alignment: .top, spacing: HB.Space.l) {
                stat("\(L("Environment")): \(bottle.name)",
                     value: Self.memory(model.totalMemory),
                     detail: "\(L("Programs")): \(model.programs.count) · \(Self.percent(model.totalCPU))")
                if let app = model.app {
                    Divider().frame(height: 44)
                    stat(L("This app"), value: Self.memory(app.memoryBytes), detail: Self.percent(app.cpuPercent))
                }
                Spacer(minLength: 0)
                Button(L("Stop all processes")) { state.killBottle(bottle) }
                    .buttonStyle(HBCompactButtonStyle())
                    .disabled(state.busy || model.rows.isEmpty)
                    .help(L("Stops every process of the environment, programs and system alike. The next Play starts fresh."))
            }
        }
    }

    private func stat(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private func processCard(_ model: TaskManagerModel, title: String, rows: [ProcessRow], canStop: Bool, empty: String) -> some View {
        card {
            Text(title).font(.headline)
            if rows.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    header
                    ForEach(rows) { row in
                        Divider().opacity(0.4)
                        processRow(row, model: model, canStop: canStop)
                    }
                }
                .animation(HB.Motion.quick, value: rows.map(\.pid))
            }
        }
    }

    private var header: some View {
        HStack(spacing: HB.Space.m) {
            Text(L("Name")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("CPU")).frame(width: 64, alignment: .trailing).help(L("A core at full speed is 100 %. A game on four cores can read 400 %."))
            Text(L("Memory")).frame(width: 78, alignment: .trailing)
            Text(L("Uptime")).frame(width: 78, alignment: .trailing)
            Color.clear.frame(width: 84, height: 1)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .padding(.bottom, HB.Space.s)
    }

    private func processRow(_ row: ProcessRow, model: TaskManagerModel, canStop: Bool) -> some View {
        let stopping = model.stopping.contains(row.pid)
        return HStack(spacing: HB.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(verbatim: "pid \(String(row.pid))").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.percent(row.cpuPercent)).frame(width: 64, alignment: .trailing)
                .foregroundStyle(row.cpuPercent >= 50 ? HB.amber : Color.primary)
            Text(Self.memory(row.memoryBytes)).frame(width: 78, alignment: .trailing)
            Text(row.reading.startedAt.map { Self.uptime($0, now: model.lastUpdate ?? Date()) } ?? "—")
                .frame(width: 78, alignment: .trailing).foregroundStyle(.secondary)
            Group {
                if canStop {
                    Button(stopping ? L("Stopping…") : L("Stop")) { model.stop(row) }
                        .buttonStyle(HBCompactButtonStyle()).disabled(stopping)
                } else {
                    Color.clear
                }
            }
            .frame(width: 84, alignment: .trailing)
        }
        .font(.system(size: 12.5)).monospacedDigit()
        .frame(minHeight: HB.Metric.row)
        .opacity(stopping ? 0.5 : 1)
    }

    // MARK: Formatting

    static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f %%", value)
    }

    static func uptime(_ start: Date, now: Date) -> String {
        let u = ProcessSampler.uptime(from: start, to: now)
        if u.hours > 0 { return String(format: L("%d h %02d min"), u.hours, u.minutes) }
        if u.minutes > 0 { return String(format: L("%d min"), u.minutes) }
        return String(format: L("%d sec"), u.seconds)
    }
}

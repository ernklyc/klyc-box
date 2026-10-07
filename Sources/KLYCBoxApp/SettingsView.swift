import SwiftUI
import KLYCKit

/// Settings: a list of categories on the left, the chosen one on the right. Used inside the main
/// window and, with the same content, in the Settings window (⌘,).
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    private static let items: [(tab: SettingsTab, title: String, symbol: String)] = [
        (.general, "General", "slider.horizontal.3"),
        (.environments, "Environments", "cylinder.split.1x2"),
        (.engine, "Engine", "gearshape.2"),
        (.tasks, "Task manager", "gauge.with.dots.needle.50percent"),
        (.troubleshooting, "Troubleshooting", "wrench.and.screwdriver"),
        (.about, "About", "info.circle"),
    ]

    var body: some View {
        @Bindable var state = state
        ZStack {
            BottleBackdrop()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Settings")).font(.system(size: 30, weight: .heavy, design: .rounded)).padding(.bottom, 14).padding(.horizontal, 14)
                        ForEach(Self.items, id: \.tab) { item in
                            Button { state.settingsTab = item.tab } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)).frame(width: 22)
                                    Text(L(item.title)).font(.system(size: 13.5, weight: state.settingsTab == item.tab ? .semibold : .regular))
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(state.settingsTab == item.tab ? HB.ink : Color.white.opacity(0.65))
                                .padding(.horizontal, 14).frame(height: HB.Metric.row)
                                .background(Capsule().fill(state.settingsTab == item.tab ? HB.lit.opacity(0.95) : Color.clear))
                                .animation(HB.Motion.quick, value: state.settingsTab)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, HB.Metric.margin).padding(.trailing, 18).padding(.top, 24)
                    .frame(width: 260)
                    VStack(alignment: .leading, spacing: 0) {
                        if state.settingsTab != .general && state.settingsTab != .about {
                            Label(L("These are expert settings. You don't need to touch any of them to play."), systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.white.opacity(0.7)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 24).padding(.top, 24)
                        }
                        Group {
                            switch state.settingsTab {
                            case .general: GeneralPane()
                            case .environments: EnvironmentsPane()
                            case .engine: EnginePane()
                            case .tasks: TaskManagerPane()
                            case .troubleshooting: TroubleshootingPane()
                            case .about: AboutPane()
                            }
                        }
                        // Another category fades in over the last one, the same way tabs everywhere do.
                        .id(state.settingsTab).transition(.opacity)
                        .animation(HB.Motion.standard, value: state.settingsTab)
                    }
                    .frame(maxWidth: .infinity)
                }
                // The strip lives on the main window; a compact echo here so a repair or a new
                // environment started from Settings is not silent (review #14).
                if state.busy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(state.busyTitle).font(.callout).lineLimit(1)
                        if !state.stage.isEmpty { Text(state.stage).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        if let stop = state.busyStop { Button(stop.label) { state.stopBusy() } }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .hbGlass(Rectangle())
                } else if let done = state.doneState {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(HB.good)
                        Text(done.title).font(.callout).lineLimit(1)
                        Spacer()
                        Button(L("Dismiss")) { state.doneState = nil }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .hbGlass(Rectangle())
                }
            }
            .hbPanel()
            .hbPage()
            .hbToasts()
            // Issue #58: this window must never be the only one back after a relaunch. Restoration
            // is off for it, and if it does appear without the main window (a restored session,
            // or the main window closed earlier), open the main window.
            .background(WindowAccessor { window in window.isRestorable = false })
            .onAppear {
                // KLYC_SETTINGS_TAB=environments|engine|troubleshooting opens that category first (handy for screenshots).
                switch ProcessInfo.processInfo.environment["KLYC_SETTINGS_TAB"] {
                case "environments"?: state.settingsTab = .environments
                case "engine"?: state.settingsTab = .engine
                case "tasks"?: state.settingsTab = .tasks
                case "troubleshooting"?: state.settingsTab = .troubleshooting
                case "about"?: state.settingsTab = .about
                default: break
                }
                MainWindow.opener = { openWindow(id: "main") }
                MainWindow.ensureOpen()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showGPTKLicense) { GPTKLicenseSheet().hbSheet() }
    }
}

/// One environment by default, more only when two games need settings that conflict.
struct EnvironmentsPane: View {
    @Environment(AppState.self) private var state
    @State private var selectedName: String?
    @State private var openName: String?
    /// The environment whose settings sheet is open from here: engine, overrides, variables and
    /// dependencies were five clicks away behind the full page (2026-09-11 walkthrough).
    @State private var settingsName: String?
    @State private var pendingDelete: String?
    @State private var showCreate = false

    private var selected: Bottle? {
        state.bottles.first { $0.name == selectedName } ?? state.defaultBottle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HB.Space.l) {
                Text(L("KLYC-Box keeps your games in one Windows environment and looks after it. A second one is only for a game whose settings conflict with the others."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                environmentsCard
                if let bottle = selected { selectedCard(bottle) }
                locationCard
            }
            .padding(.vertical, 20).padding(.leading, 20).padding(.trailing, HB.Metric.margin)
        }
        .sheet(isPresented: .init(get: { openName != nil }, set: { if !$0 { openName = nil } })) {
            if let bottle = state.bottles.first(where: { $0.name == openName }) {
                NavigationStack {
                    BottleView(bottle: bottle)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { openName = nil } } }
                }
                .frame(minWidth: 780, minHeight: 560)
                .hbSheet()
            }
        }
        .sheet(isPresented: .init(get: { settingsName != nil }, set: { if !$0 { settingsName = nil } })) {
            if let bottle = state.bottles.first(where: { $0.name == settingsName }) {
                BottleSettingsSheet(bottle: bottle).hbSheet()
            }
        }
        .sheet(isPresented: $showCreate) { CreateBottleSheet().hbSheet() }
        .confirmationDialog("Delete environment \"\(pendingDelete ?? "")\"? This removes its Windows drive and everything installed in it, games included.",
                            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(L("Delete"), role: .destructive) { if let n = pendingDelete { state.deleteBottle(n) }; pendingDelete = nil }
            Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: cards

    /// The list of environments, with the one action that adds to it.
    private var environmentsCard: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            HStack {
                HB.eyebrow(L("Environments"))
                Spacer(minLength: HB.Space.m)
                Button(L("New environment…")) { showCreate = true }.buttonStyle(HBCompactButtonStyle()).disabled(state.busy)
            }
            VStack(spacing: HB.Space.s) {
                ForEach(state.bottles, id: \.name) { environmentCard($0) }
                ForEach(state.damagedBottles) { damaged in
                    HStack(spacing: HB.Space.m) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(damaged.name).font(.headline)
                            Text(damaged.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Delete…"), role: .destructive) { pendingDelete = damaged.name }.buttonStyle(HBCompactButtonStyle())
                    }
                    .padding(HB.Space.m)
                    .hbGlass(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(HB.Space.l).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: HB.Metric.radius)
    }

    /// The chosen environment: its settings and the things to do with it, all in one card.
    private func selectedCard(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            HStack {
                HB.eyebrow(bottle.name)
                Spacer(minLength: HB.Space.m)
                Button(L("Repair")) { state.repairBottle(bottle) }.buttonStyle(HBCompactButtonStyle()).disabled(state.busy)
                Button(L("Settings…")) { settingsName = bottle.name }.buttonStyle(HBCompactButtonStyle())
                    .help(L("Graphics, compatibility, engine, DLL overrides, environment variables and dependencies for this environment."))
                Button(L("Full page…")) { openName = bottle.name }.buttonStyle(HBCompactButtonStyle())
            }
            details(bottle)
            Text(L("Repair re-runs the Windows first boot. Games and Steam stay where they are."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(HB.Space.l).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: HB.Metric.radius)
    }

    /// Where it all lives (#24, #68): games are big and internal disks are small.
    private var locationCard: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            HB.eyebrow(L("Data location"))
            HStack(spacing: HB.Space.s) {
                Image(systemName: "externaldrive").foregroundStyle(.secondary)
                Text(state.paths.home.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).help(state.paths.home.path)
                Spacer(minLength: HB.Space.m)
                Button(L("Change…")) { state.chooseHome() }.buttonStyle(HBCompactButtonStyle()).disabled(state.busy)
                if KLYCPaths.configuredHome() != nil {
                    Button(L("Default")) { state.useDefaultHome() }.buttonStyle(HBCompactButtonStyle()).disabled(state.busy)
                        .help(L("Back to ~/Library/Application Support/KLYC-Box, with the data"))
                }
            }
        }
        .padding(HB.Space.l).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: HB.Metric.radius)
    }

    private func sizeText(_ bottle: Bottle) -> String {
        let bytes = state.libraryItems.filter { $0.bottleName == bottle.name }.reduce(Int64(0)) { $0 + $1.sizeOnDisk }
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : ""
    }

    private func environmentCard(_ bottle: Bottle) -> some View {
        let isSelected = selected?.name == bottle.name
        let titles = state.libraryItems.filter { $0.bottleName == bottle.name }.count
        return Button {
            selectedName = bottle.name
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cylinder.split.1x2").foregroundStyle(isSelected ? HB.amber : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(bottle.name).font(.headline)
                        if bottle.name == state.defaultBottle?.name {
                            Text(L("DEFAULT")).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(HB.good.opacity(0.2))).foregroundStyle(HB.good)
                        }
                        if state.deletingBottles.contains(bottle.name) {
                            Text(L("deleting…")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text([state.engine(for: bottle)?.displayName ?? bottle.settings.engineID,
                          String(format: L("%d titles"), titles),
                          sizeText(bottle)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hbGlass(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? HB.amber.opacity(0.6) : HB.cardStroke))
        .contextMenu {
            Button(L("Full page…")) { openName = bottle.name }
            Button(L("Stop all processes")) { state.killBottle(bottle) }
            Button(L("Duplicate")) { state.duplicateBottle(bottle) }
            Button(L("Repair (re-run the Windows first boot)")) { state.repairBottle(bottle) }
            Divider()
            Button(L("Delete…"), role: .destructive) { pendingDelete = bottle.name }
                .disabled(state.deletingBottles.contains(bottle.name))
        }
    }

    private func details(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(L("Graphics mode")) { GraphicsModePicker(bottle: bottle) }
            Divider().padding(.vertical, 8)
            row(L("Windows components")) { WindowsComponentsRow(bottle: bottle) }
            Divider().padding(.vertical, 8)
            row(L("Files")) {
                HStack(spacing: HB.Space.m) {
                    Button(L("Show the Windows drive")) { NSWorkspace.shared.open(bottle.driveC) }
                        .buttonStyle(HBTextButtonStyle())
                    Button(L("Uninstall Windows programs…")) { state.openUninstaller(in: bottle) }
                        .buttonStyle(HBTextButtonStyle())
                        .help(L("Opens Windows' Add/Remove Programs for this environment, for programs you installed into it."))
                }
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: HB.Space.m) {
            Text(label).font(.callout).frame(width: 150, alignment: .leading).padding(.top, 2)
            content()
            Spacer(minLength: 0)
        }
    }
}

struct EnginePane: View {
    @Environment(AppState.self) private var state
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            Text(L("The engine is the Wine build and graphics layers KLYC-Box runs games with. KLYC-Box picks it; an update never moves an environment to a different Wine build on its own."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let engine = state.defaultEngine {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(engine.displayName).font(.headline)
                        Text(engine.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(String(format: L("Graphics layers: %@"), ["dxmt", "dxvk", "d3dmetal"].filter { engine.rendererDir($0) != nil }.map { GamePageCopy.plainName(Renderer(rawValue: $0) ?? .dxvk) }.joined(separator: ", ")))
                            .font(.caption).foregroundStyle(.secondary)
                        if engine.ships("d3dmetal"), engine.rendererDir("d3dmetal") == nil {
                            Button(L("Read Apple's licence and turn on DirectX 12 support…")) {
                                state.licenseEngine = engine; state.loadGPTKLicense(); showLicense = true
                            }.buttonStyle(HBTextButtonStyle()).font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let update = state.engineUpdate {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("A newer engine is available")).font(.headline)
                            Text(update.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("Update engine")) { state.updateEngine() }.disabled(state.busy)
                    }
                }
            }
            if state.engines.count > 1 {
                Text(String(format: L("Installed engines: %@. An environment's engine is chosen on its own page."), state.engines.map(\.id).joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 20).padding(.leading, 20).padding(.trailing, HB.Metric.margin)
        .sheet(isPresented: $showLicense) { GPTKLicenseSheet().hbSheet() }
    }
}

struct TroubleshootingPane: View {
    @Environment(AppState.self) private var state
    @State private var showLog = false

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: HB.Space.m) { content() }
            .padding(HB.Space.l).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: HB.Metric.radius)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HB.Space.l) {
                card {
                    Text(L("When a game misbehaves, the log of its last launch is what a report needs. Nothing here is sent anywhere without you."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: HB.Space.s) {
                        Button(L("Show the logs folder")) { NSWorkspace.shared.open(state.paths.logs) }.buttonStyle(HBCompactButtonStyle())
                        Button(L("Report a problem…")) {
                            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                            Task.detached {
                                let url = BugReport.url(version: version)
                                await MainActor.run { NSWorkspace.shared.open(url) }
                            }
                        }.buttonStyle(HBCompactButtonStyle())
                        Button(L("Show the last background task")) { showLog = true }.buttonStyle(HBCompactButtonStyle())
                    }
                }
                if let b = state.defaultBottle {
                    card {
                        Text(String(format: L("If Steam or a game is stuck, stop the environment's processes; the next Play starts fresh. Environment: %@."), b.name))
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L("Stop all processes")) { state.killBottle(b) }.buttonStyle(HBCompactButtonStyle()).disabled(state.busy)
                    }
                }
            }
            .padding(.vertical, 20).padding(.leading, 20).padding(.trailing, HB.Metric.margin)
        }
        .sheet(isPresented: $showLog) { LogSheet().hbSheet() }
    }
}

/// Things that are about how the app feels, not about Windows.
struct GeneralPane: View {
    @Environment(AppState.self) private var state
    @AppStorage(UISound.defaultsKey) private var sounds = true
    @AppStorage("menuBarItem") private var menuBarItem = true

    var body: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            if let version = UpdateStatus.shared.availableVersion, updatesEnabled {
                HStack(spacing: HB.Space.m) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(HB.amber)
                    Text(String(format: L("Version %@ is available"), version)).font(.callout.weight(.semibold))
                    Spacer(minLength: 8)
                    Button(L("Update")) { (NSApp.delegate as? AppDelegate)?.updaterController.updater.checkForUpdates() }
                        .buttonStyle(HBCompactButtonStyle())
                }
                .padding(HB.Space.m).hbCard(radius: HB.Metric.radius)
            }
            LanguageRow()
            HBToggleRow(title: L("Menu bar item"),
                        caption: L("A small icon in the menu bar: start the game you played last and change your Steam status without opening the window."),
                        isOn: $menuBarItem)
            HBToggleRow(title: L("Interface sounds"),
                        caption: L("Soft sounds when you move along the shelf, pick something or start a game. KLYC-Box makes them itself."),
                        isOn: $sounds)
                .onChange(of: sounds) { _, on in if on { UISound.play(.select) } }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Improve results")).font(.headline)
                    Text(String(format: L("%d games have been tested on this Mac."), state.tuning.count))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button(L("Export…")) { exportTuning() }.disabled(state.tuning.isEmpty)
                        Button(L("Forget all"), role: .destructive) { state.clearTuning() }.disabled(state.tuning.isEmpty)
                    }
                    Divider().padding(.vertical, 4)
                    Text(L("Your results")).font(.headline)
                    Text(String(format: L("%d games marked on this Mac."), state.localVerdicts.count)).font(.caption).foregroundStyle(.secondary)
                    Button(L("Export your results…")) { exportVerdicts() }.disabled(state.localVerdicts.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(.vertical, 20).padding(.leading, 20).padding(.trailing, HB.Metric.margin)
    }

    private func exportVerdicts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "klycbox-my-results.json"
        if panel.runModal() == .OK, let url = panel.url, let data = LocalVerdictStore(paths: state.paths).exportJSON() { try? data.write(to: url) }
    }

    private func exportTuning() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "klycbox-improve-results.json"
        if panel.runModal() == .OK, let url = panel.url, let data = TuningStore(paths: state.paths).exportJSON() { try? data.write(to: url) }
    }
}

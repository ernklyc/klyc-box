import SwiftUI
import KLYCKit

/// Options that belong to one game: launch arguments and the performance overlay.
struct PlayOptionsPanel: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    @State private var arguments = ""
    @State private var loaded = false
    @State private var cacheBytes: UInt64?
    @State private var cacheCleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            HB.eyebrow(L("Play options"))
            HStack(spacing: 10) {
                Text(L("Launch options")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                TextField("-windowed -dx11", text: $arguments)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12).frame(height: 36)
                    .hbGlass(RoundedRectangle(cornerRadius: 10))
                    .onSubmit { state.setLaunchArguments(arguments, for: item) }
                Button(L("Save")) { state.setLaunchArguments(arguments, for: item) }.buttonStyle(HBCompactButtonStyle())
            }
            Text(L("Added to every launch of this game. Put arguments in quotes if they contain spaces."))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(L("Frame rate cap")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Picker("", selection: Binding(get: { state.fpsCap(for: item) ?? -1 }, set: { state.setFPSCap($0 < 0 ? nil : $0, for: item) })) {
                    Text(L("Same as the environment")).tag(-1)
                    ForEach(BottleSettings.fpsCapChoices(displayHz: NSScreen.main?.maximumFramesPerSecond, current: state.fpsCap(for: item)), id: \.self) { n in
                        Text(n == 0 ? L("Uncapped") : "\(n) fps").tag(n)
                    }
                }
                .labelsHidden().frame(maxWidth: 240)
                Spacer(minLength: 0)
            }
            Text(L("Holds the game to this frame rate to keep the Mac cooler and quieter. For this game only; takes effect the next time it starts."))
                .font(.caption).foregroundStyle(.secondary)
            if let bytes = cacheBytes {
                HStack(spacing: 10) {
                    Text(L("Shader cache")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.callout.monospacedDigit())
                    Button(L("Clear")) { clearCache() }.buttonStyle(HBCompactButtonStyle()).disabled(bytes == 0 || state.busy || !state.runningSessions.isEmpty)
                    if cacheCleared { Label(L("Cleared"), systemImage: "checkmark").font(.caption).foregroundStyle(HB.good) }
                    Spacer(minLength: 0)
                }
                Text(L("What the game compiled while you played, kept so it starts smoothly next time. Clearing it is the standard first step when a game shows glitches or crashes after a graphics mode or engine change; the game rebuilds it, with some stutter at first."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(isOn: Binding(get: { state.metalHUD(for: item) }, set: { state.setMetalHUD($0, for: item) })) {
                Text(L("Show the frame rate while playing, and measure it"))
            }
            .toggleStyle(.switch).tint(HB.amber)
            Text(L("Apple's Metal overlay on screen, for this game only. KLYC-Box also reads the frame rate from it and keeps it with the game's result. Takes effect the next time the game starts."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hbCard(radius: 16)
        .onAppear { if !loaded { arguments = state.launchArguments[item.id] ?? ""; loaded = true } }
        .task(id: item.id) { await refreshCache() }
    }

    private func refreshCache() async {
        let folders = state.shaderCacheFolders(for: item)
        cacheBytes = folders.isEmpty ? nil : await Task.detached(priority: .utility) { ShaderCache.size(of: folders) }.value
    }

    private func clearCache() {
        let folders = state.shaderCacheFolders(for: item)
        Task {
            let freed = await Task.detached(priority: .userInitiated) { ShaderCache.clear(folders) }.value
            let size = ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file)
            state.appendLog("\(item.title): shader cache cleared (\(size))")
            state.notify(String(format: L("Shader cache cleared: %@ freed."), size))
            cacheCleared = true
            await refreshCache()
        }
    }
}

import SwiftUI
import KLYCKit
import UniformTypeIdentifiers

/// The "Mods" card of a game's page: the folder and its Windows path, adding files safely, running a mod tool in the
/// game's environment, the DLL overrides mods need, and undo.
struct ModsPanel: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem

    private struct Pending: Identifiable { let id = UUID(); let plan: ModInstaller.Plan }
    @State private var pending: Pending?
    @State private var message: String?
    @State private var dropTargeted = false
    @State private var showCustomDLL = false
    @State private var customDLL = ""
    @State private var refresh = 0   // bumped after every change so undo and the DLL list redraw

    private var folder: URL? { state.programFolder(for: item) }
    private var entry: ModCatalog.Entry? { state.modEntry(for: item) }

    var body: some View {
        if let folder, let bottle = state.modBottle(for: item) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HB.eyebrow(L("Mods"))
                    Spacer(minLength: 0)
                    if dropTargeted { Text(L("Drop to add to the game folder")).font(.caption).foregroundStyle(HB.amber) }
                }
                pathRows(folder, bottle)
                if let folders = entry?.folders, !folders.isEmpty { folderChips(folders, root: folder) }
                actions(folder)
                dllSection
                historySection
                if let notes = entry?.notes { ForEach(notes, id: \.self) { noteRow($0) } }
                noteRow(L("Steam's \"Verify integrity of game files\" can remove added files and restore replaced ones."))
                if let message { Text(message).font(.callout).foregroundStyle(HB.good).fixedSize(horizontal: false, vertical: true) }
            }
            .id(refresh)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hbCard(radius: 16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HB.amber.opacity(dropTargeted ? 0.9 : 0), lineWidth: 2))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                collectURLs(providers) { begin($0, subfolder: nil) }
                return true
            }
            .alert(L("Some files already exist"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button(L("Replace")) { if let p = pending { finish(p.plan, overwrite: true) }; pending = nil }
                Button(L("Skip existing")) { if let p = pending { finish(p.plan, overwrite: false) }; pending = nil }
                Button(L("Cancel"), role: .cancel) { pending = nil }
            } message: {
                Text(String(format: L("%d files are already in the game folder. Replaced files are backed up first, and \"Undo last install\" puts them back."), pending?.plan.conflicts.count ?? 0))
            }
            .alert(L("Add a DLL override"), isPresented: $showCustomDLL) {
                TextField("dwrite", text: $customDLL)
                Button(L("Add")) { addDLL(customDLL); customDLL = "" }
                Button(L("Cancel"), role: .cancel) { customDLL = "" }
            } message: { Text(L("The name of the library the mod puts next to the game, without .dll.")) }
        }
    }

    // MARK: pieces

    private func pathRows(_ folder: URL, _ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L("Game folder")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text(folder.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 8)
                Button(L("Open")) { NSWorkspace.shared.open(folder) }.buttonStyle(HBCompactButtonStyle())
            }
            if let win = state.windowsPath(for: item) {
                HStack(spacing: 10) {
                    Text(L("Windows path")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text(win).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button(L("Copy")) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(win, forType: .string); state.notify(L("Copied"))
                        message = L("Windows path copied: paste it where a mod tool asks where the game is.")
                    }.buttonStyle(HBCompactButtonStyle())
                }
            }
        }
    }

    private func folderChips(_ folders: [ModCatalog.Folder], root: URL) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipButtons(folders, root: root); Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) { chipButtons(folders, root: root) }
        }
    }

    @ViewBuilder private func chipButtons(_ folders: [ModCatalog.Folder], root: URL) -> some View {
        ForEach(folders, id: \.self) { f in
            let url = root.appending(path: f.path, directoryHint: .isDirectory)
            Button { NSWorkspace.shared.open(url) } label: { Label(f.title, systemImage: "folder") }
                .buttonStyle(HBCompactButtonStyle())
                .disabled(!FileManager.default.fileExists(atPath: url.path))
                .help(f.path)
        }
    }

    private func actions(_ folder: URL) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { addMenu; runMenu(folder); Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 10) { addMenu; runMenu(folder) }
        }
    }

    private var addMenu: some View {
        Menu {
            Button(L("Game folder")) { pickFiles(subfolder: nil) }
            ForEach(entry?.folders ?? [], id: \.self) { f in Button(f.title) { pickFiles(subfolder: f.path) } }
        } label: { Label(L("Add files…"), systemImage: "plus.square.on.square").lineLimit(1).fixedSize() }
            .menuStyle(.button).buttonStyle(HBSecondaryButtonStyle()).fixedSize()
    }

    private func runMenu(_ folder: URL) -> some View {
        Menu {
            Button(L("Choose a program…")) { pickProgram() }
            let tools = state.toolsInGameFolder(item)
            if !tools.isEmpty {
                Divider()
                ForEach(tools, id: \.self) { url in
                    Button(url.path.replacingOccurrences(of: folder.path + "/", with: "")) { run(url) }
                }
            }
        } label: { Label(L("Run a program"), systemImage: "play.rectangle").lineLimit(1).fixedSize() }
            .menuStyle(.button).buttonStyle(HBSecondaryButtonStyle()).fixedSize()
            .disabled(state.busy)
            .help(L("Runs a mod tool in this game's environment, the way the game itself would run."))
    }

    private var dllSection: some View {
        let names = state.modDLLs(for: item)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L("DLL overrides")).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Menu {
                    ForEach(ModDLLOverrides.presets.filter { !names.contains($0) }, id: \.self) { n in Button(n) { addDLL(n) } }
                    Divider()
                    Button(L("Other…")) { showCustomDLL = true }
                } label: { Label(L("Add"), systemImage: "plus").lineLimit(1).fixedSize() }
                    .menuStyle(.button).buttonStyle(HBCompactButtonStyle()).fixedSize()
                if names.isEmpty { Text(L("None")).font(.callout).foregroundStyle(.secondary) }
                ForEach(names, id: \.self) { n in
                    Button { removeDLL(n) } label: { Label(n, systemImage: "xmark").labelStyle(.titleAndIcon).lineLimit(1).fixedSize() }
                        .buttonStyle(HBCompactButtonStyle()).help(L("Remove"))
                }
                Spacer(minLength: 0)
            }
            Text(L("For mods that put a library such as dwrite.dll next to the game: Wine loads the mod's copy first. Applies to this game only; stop the environment's processes, then start the game."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every install, newest first: what it added and replaced, and undo for the newest one.
    @ViewBuilder private var historySection: some View {
        let history = folder.map { ModInstaller.records(in: $0) } ?? []
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                undoRow(history[0])
                ForEach(Array(history.enumerated()), id: \.offset) { _, record in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(record.added + record.replaced, id: \.self) { path in
                                Text(path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }.padding(.top, 4)
                    } label: {
                        Text(String(format: L("%d files, %@"), record.added.count + record.replaced.count, record.date.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func undoRow(_ record: ModInstaller.Record) -> some View {
        HStack(spacing: 10) {
            Button { message = state.undoMods(for: item); UISound.play(.back); refresh += 1 } label: {
                Label(L("Undo last install"), systemImage: "arrow.uturn.backward").lineLimit(1).fixedSize()
            }.buttonStyle(HBCompactButtonStyle())
            Text(String(format: L("%d files, %@"), record.added.count + record.replaced.count, record.date.formatted(date: .abbreviated, time: .shortened)))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: actions

    private func pickFiles(subfolder: String?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = L("Add")
        panel.message = L("Choose mod files or folders to add to the game")
        if panel.runModal() == .OK { begin(panel.urls, subfolder: subfolder) }
    }

    private func pickProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["exe", "msi", "bat"].compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = folder
        panel.message = L("Choose a Windows program")
        if panel.runModal() == .OK, let url = panel.url { run(url) }
    }

    private func run(_ url: URL) {
        guard let bottle = state.modBottle(for: item) else { return }
        state.runDropped(url, in: bottle, andPin: false)
    }

    private func begin(_ urls: [URL], subfolder: String?) {
        guard !urls.isEmpty else { return }
        do {
            let plan = try state.planMods(urls, for: item, subfolder: subfolder)
            if plan.conflicts.isEmpty { finish(plan, overwrite: false) } else { pending = Pending(plan: plan) }
        } catch {
            message = String(format: L("Could not add the files: %@"), error.localizedDescription)
            UISound.play(.error)
        }
    }

    private func finish(_ plan: ModInstaller.Plan, overwrite: Bool) {
        guard let folder else { return }
        message = state.installMods(plan, for: item, overwrite: overwrite)
        UISound.play(.select)
        _ = folder
        refresh += 1
    }

    private func addDLL(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        state.setModDLLs(state.modDLLs(for: item) + [name], for: item)
        message = String(format: L("%@ added. Stop the environment's processes, then start the game."), name)
        refresh += 1
    }

    private func removeDLL(_ name: String) {
        state.setModDLLs(state.modDLLs(for: item).filter { $0 != name }, for: item)
        refresh += 1
    }

    /// Dropped files arrive one provider at a time; wait for all of them.
    private func collectURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let lock = NSLock(); var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { let all = urls; Task { @MainActor in completion(all) } }
    }
}

import SwiftUI
import KLYCKit

/// A game's save files: what was found, back them up, put a backup back.
struct SavesPanel: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem
    @State private var message: String?
    @State private var restoring: SaveBackup.Entry?
    @State private var refresh = 0
    /// Found off the main thread: the search walks the environment's user folders and used to freeze the page while it ran.
    @State private var folders: [SaveLocator.Candidate] = []
    @State private var backups: [SaveBackup.Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: HB.Space.m) {
            HB.eyebrow(L("Saves"))
            if folders.isEmpty {
                Text(L("No save folders were found for this game yet. Play it once, then try again."))
                    .font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(folders, id: \.self) { f in
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
                        Text(f.title).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button(L("Open")) { NSWorkspace.shared.open(f.url) }.buttonStyle(HBCompactButtonStyle())
                    }
                }
            }
            HStack(spacing: 10) {
                Button { message = state.backUpSaves(for: item); UISound.play(.select); refresh += 1 } label: {
                    Label(L("Back up saves"), systemImage: "externaldrive.badge.plus")
                }
                .buttonStyle(HBSecondaryButtonStyle()).disabled(folders.isEmpty)
                if !backups.isEmpty {
                    Button(L("Open backup folder")) { NSWorkspace.shared.open(state.saveBackupDirectory(for: item)) }.buttonStyle(HBCompactButtonStyle())
                }
                Spacer(minLength: 0)
            }
            ForEach(backups) { b in
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
                    Text(b.date.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                    Text(ByteCountFormatter.string(fromByteCount: b.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(L("Restore")) { restoring = b }.buttonStyle(HBCompactButtonStyle())
                    Button { state.deleteSaveBackup(b); refresh += 1 } label: { Image(systemName: "trash") }
                        .buttonStyle(HBCompactButtonStyle()).help(L("Delete this backup"))
                }
            }
            if let message { Text(message).font(.callout).foregroundStyle(HB.good).fixedSize(horizontal: false, vertical: true) }
        }
        .id(refresh)
        .task(id: "\(item.id)#\(refresh)") {
            let query = state.saveSearch(for: item), directory = state.saveBackupDirectory(for: item)
            let result = await Task.detached(priority: .utility) { () -> ([SaveLocator.Candidate], [SaveBackup.Entry]) in
                let found = query.map { SaveLocator.candidates(driveC: $0.driveC, steamAppID: $0.steamAppID, names: $0.names) } ?? []
                return (found, SaveBackup.list(in: directory))
            }.value
            folders = result.0; backups = result.1
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hbCard(radius: 16)
        .alert(L("Restore these saves?"), isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button(L("Restore")) { if let b = restoring { message = state.restoreSaves(b, for: item); UISound.play(.back); refresh += 1 }; restoring = nil }
            Button(L("Cancel"), role: .cancel) { restoring = nil }
        } message: { Text(L("The saves as they are now are copied to the backup folder first, so this can be undone.")) }
    }
}

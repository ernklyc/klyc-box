import SwiftUI
import KLYCKit

/// Shown on Home while the Steam in KLYC-Box and the Mac's own Steam list the same game folder: both would update (and overwrite) the same games.
struct SharedLibraryBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if !state.sharedSteamFolders.isEmpty {
            HStack(spacing: HB.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(HB.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Two Steams share a game folder")).font(.system(size: 14, weight: .semibold))
                    Text(String(format: L("The Steam in KLYC-Box and the Mac's own Steam both use %@, so each may update (and replace) the other's games."),
                                state.sharedSteamFolders.map(\.lastPathComponent).joined(separator: ", ")))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(L("Separate them")) { state.separateSteamFromMacSteam() }.buttonStyle(HBPrimaryButtonStyle())
            }
            .padding(14).frame(maxWidth: 640).hbCard(radius: 16)
        }
    }
}

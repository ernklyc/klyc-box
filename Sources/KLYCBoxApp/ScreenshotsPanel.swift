import SwiftUI
import ImageIO
import KLYCKit

/// The game's Steam screenshots as a row of thumbnails; a click opens the picture.
struct ScreenshotsPanel: View {
    @Environment(AppState.self) private var state
    let item: LibraryItem

    var body: some View {
        if let appid = item.steamAppID, let bottle = state.modBottle(for: item) {
            let shots = ScreenshotFinder.find(driveC: bottle.driveC, steamAppID: appid)
            if !shots.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HB.eyebrow(L("Screenshots"))
                    HScroll {
                        HStack(spacing: 12) {
                            ForEach(shots, id: \.self) { url in
                                Button { NSWorkspace.shared.open(url) } label: {
                                    Thumbnail(url: url).frame(width: 220, height: 124)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hbCard(radius: 16)
            }
        }
    }
}

/// A small picture read straight from the file at thumbnail size, so a folder of big screenshots stays light.
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 440,
                                             kCGImageSourceCreateThumbnailWithTransform: true]
                return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { NSImage(cgImage: $0, size: .zero) }
            }.value
        }
    }
}

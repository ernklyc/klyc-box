import SwiftUI
import KLYCKit

/// The Atlas's view of a Steam game: how solid the knowledge is, a few facts, and a link to the game's page on the site.
struct AtlasRows: View {
    let appid: Int
    let entry: AtlasEntry

    private var symbol: String {
        switch entry.tier {
        case .tested: return "checkmark.seal.fill"
        case .reported: return "person.2.fill"
        case .predicted: return "questionmark.circle"
        case .blocked: return "nosign"
        case nil: return "circle.dashed"
        }
    }
    private var tint: Color {
        switch entry.tier {
        case .tested: return HB.good
        case .reported: return Color(red: 0.50, green: 0.70, blue: 1.0)
        case .predicted: return Color(red: 0.72, green: 0.62, blue: 0.95)
        case .blocked: return HB.bad
        case nil: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
                Text(AtlasText.headline(entry)).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(AtlasText.details(entry), id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(.secondary).padding(.leading, 26).fixedSize(horizontal: false, vertical: true)
            }
            if let page = AtlasSite.gamePage(appid: appid) {
                Button(L("Open in the Atlas")) { NSWorkspace.shared.open(page) }
                    .buttonStyle(HBCompactButtonStyle()).padding(.leading, 26)
                    .help(L("Opens this game's page on the KLYC-Box site, with who tried it, when, and on which Mac."))
            }
        }
        .font(.callout)
    }
}

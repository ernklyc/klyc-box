import SwiftUI
import KLYCKit

/// What Epic gives away now and next, as one slim row above the store: small enough that the store keeps the room.
/// Claiming needs the Epic account, in the page below.
struct EpicFreeStrip: View {
    @Binding var show: Bool
    @State private var games: [EpicFreeGame] = []

    var body: some View {
        let now = Date()
        let shown = games.filter { $0.isFree(at: now) } + games.filter { $0.start > now }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HB.eyebrow(L("Free on Epic this week"))
                    Spacer(minLength: 8)
                    Button { withAnimation(HB.Motion.standard) { show.toggle() } } label: {
                        Label(show ? L("Hide") : L("Show"), systemImage: show ? "chevron.up" : "chevron.down").font(.caption)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                if show {
                    HScroll {
                        HStack(spacing: 12) { ForEach(shown) { tile($0, now: now) } }
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 14)
        } else {
            Color.clear.frame(height: 0).task { if games.isEmpty { games = await EpicFree.fetch() } }
        }
    }

    private func tile(_ g: EpicFreeGame, now: Date) -> some View {
        let free = g.isFree(at: now)
        return Button { if let url = g.url { NSWorkspace.shared.open(url) } } label: {
            HStack(spacing: 10) {
                AsyncImage(url: g.image, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.06) }
                }
                .frame(width: 112, height: 63).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(free ? L("Free now") : g.start.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 11, weight: .bold)).padding(.horizontal, 7).frame(height: 20)
                        .background(Capsule().fill(free ? HB.good.opacity(0.85) : Color.white.opacity(0.14)))
                    Text(String(format: L("Until %@"), g.end.formatted(.dateTime.day().month(.abbreviated)))).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 140, alignment: .leading)
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        }.buttonStyle(.plain)
        .task { if games.isEmpty { games = await EpicFree.fetch() } }
    }
}

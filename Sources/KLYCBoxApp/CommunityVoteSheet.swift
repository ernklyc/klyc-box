import SwiftUI
import KLYCKit

/// "Tell other players": a report for one game, shown in full before it is sent. Opt-in, anonymous,
/// one per game, and it can be taken back from here.
struct CommunityVoteSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var vote: CommunityVote
    @State private var working = false
    @State private var problem: String?

    init(item: LibraryItem, draft: CommunityVote) {
        self.item = item
        _vote = State(initialValue: draft)
    }

    private var sent: SentVote? { state.sentVotes[vote.appid] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Tell other players")).font(.title3.weight(.semibold))
                Text(item.title).foregroundStyle(.secondary)
            }
            Picker(L("Does it work?"), selection: $vote.works) {
                Text(L("Works")).tag(true)
                Text(L("Has problems")).tag(false)
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 4) {
                Text(L("Rating")).foregroundStyle(.secondary)
                Spacer()
                ForEach(1...5, id: \.self) { star in
                    Button { vote.rating = star } label: {
                        Image(systemName: star <= vote.rating ? "star.fill" : "star").foregroundStyle(star <= vote.rating ? HB.amber : .secondary)
                    }.buttonStyle(.plain).accessibilityLabel(String(format: L("%d stars"), star))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Note (optional)")).font(.caption).foregroundStyle(.secondary)
                TextField(L("What should another player know?"), text: Binding(get: { vote.note }, set: { vote.note = String($0.prefix(CommunityVote.noteLimit)) }), axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Text("\(vote.note.count)/\(CommunityVote.noteLimit)").font(.caption2).foregroundStyle(.secondary)
            }
            disclosure
            if let problem { Text(problem).font(.callout).foregroundStyle(HB.bad) }
            HStack {
                if sent != nil {
                    Button(L("Take my report back")) { Task { await run { await state.withdrawCommunityVote(appid: vote.appid, title: item.title) } } }
                        .buttonStyle(HBCompactButtonStyle()).disabled(working)
                }
                Spacer()
                Button(L("Cancel")) { dismiss() }.buttonStyle(HBCompactButtonStyle()).keyboardShortcut(.cancelAction)
                Button(sent == nil ? L("Send") : L("Send again")) { Task { await run { await state.sendCommunityVote(vote, title: item.title) } } }
                    .buttonStyle(HBPrimaryButtonStyle()).disabled(working || !vote.isValid).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }

    /// Every field that leaves this Mac, as the server receives it.
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            HB.eyebrow(L("What is sent"))
            ForEach(Array(vote.disclosure.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    Text(row.value).font(.callout).lineLimit(2)
                }
            }
            Text(L("Anonymous: no name or email is attached, and KLYC-Box does not keep your IP address. The reports are hosted by Google Firebase, which sees the connection like any web service. One report per game; sending again replaces it, and you can take it back here."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Link(L("Privacy details"), destination: CommunityReports.privacyURL).font(.caption)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: 12)
    }

    private func run(_ work: () async -> String?) async {
        working = true; problem = nil
        let result = await work()
        working = false
        if let result { problem = result } else { dismiss() }
    }
}

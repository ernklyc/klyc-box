import KLYCKit

/// Player reports: the opt-in "tell other players" step. Nothing here runs by itself; every
/// send starts from the sheet where the player has read each field.
extension AppState {
    /// The report prefilled from this Mac's own answer and settings; nil for a game without a Steam id.
    func communityDraft(for item: LibraryItem) -> CommunityVote? {
        guard let appid = item.steamAppID else { return nil }
        let sent = sentVotes[appid]
        let local = localVerdicts[item.id]
        let bottle = modBottle(for: item)
        return CommunityVote(appid: appid, works: sent?.works ?? local?.works ?? true,
                             rating: sent?.rating ?? ((local?.works ?? true) ? 4 : 2),
                             chip: local?.chip ?? Machine.chip(), macos: local?.macos ?? Machine.macOSVersion(),
                             engine: local?.engine ?? bottle?.settings.engineID ?? "",
                             renderer: local?.renderer ?? bottle?.settings.renderer.rawValue ?? "",
                             note: sent?.note ?? "")
    }

    /// Returns nil on success, else a sentence for the sheet.
    func sendCommunityVote(_ vote: CommunityVote, title: String) async -> String? {
        do {
            try await CommunityReports(paths: paths).send(vote)
            let sent = SentVote(works: vote.works, rating: vote.rating, note: vote.note)
            SentVoteStore(paths: paths).set(sent, for: vote.appid)
            sentVotes[vote.appid] = sent
            appendLog("\(title): player report sent (\(vote.works ? "works" : "problems"), \(vote.rating)/5)")
            notify(L("Thanks, your report was sent."))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func withdrawCommunityVote(appid: Int, title: String) async -> String? {
        do {
            try await CommunityReports(paths: paths).withdraw(appid: appid)
            SentVoteStore(paths: paths).set(nil, for: appid)
            sentVotes[appid] = nil
            appendLog("\(title): player report withdrawn")
            notify(L("Your report was taken back."), style: .info)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

import SwiftUI
import KLYCKit

/// What an Epic download says about itself, in words: "37% · 5.2 MB/s · 12 min left".
enum EpicDownloadText {
    static func percent(_ p: EpicDownloadProgress) -> String? {
        p.percent.map { String(format: "%.0f%%", $0) }
    }

    static func speed(_ p: EpicDownloadProgress) -> String? { p.downloadSpeed.flatMap(speed(bytesPerSecond:)) }

    static func speed(bytesPerSecond s: Double) -> String? {
        guard s > 1024 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file) + "/s"
    }

    static func timeLeft(_ p: EpicDownloadProgress) -> String? {
        guard (p.percent ?? 0) > 0 else { return nil }
        return p.etaSeconds.flatMap(timeLeft(seconds:))
    }

    /// "12 min left"; nil for nothing left or an unknown time.
    static func timeLeft(seconds eta: Int) -> String? {
        guard eta > 0 else { return nil }
        let h = eta / 3600, m = (eta % 3600) / 60
        let text = h > 0 ? String(format: L("%d h %02d min"), h, m) : (m > 0 ? String(format: L("%d min"), m) : String(format: L("%d sec"), eta))
        return String(format: L("%@ left"), text)
    }

    /// "8.4 GB of 22.9 GB" when both are known; the downloaded part alone otherwise.
    static func amount(_ p: EpicDownloadProgress) -> String? {
        guard let done = p.downloadedBytes else { return nil }
        let doneText = ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
        guard let total = p.downloadSize, total > 0 else { return doneText }
        return String(format: L("%@ of %@"), doneText, ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
    }

    /// The one line under the title.
    static func line(for d: EpicDownload) -> String {
        switch d.state {
        case .pausing: return L("Pausing… saving its place can take a minute or two.")
        case .paused: return [percent(d.progress), L("Paused")].compactMap { $0 }.joined(separator: " · ")
        case .failed: return L("Stopped. Resume to try again.")
        case .running:
            let parts = [percent(d.progress), speed(d.progress), timeLeft(d.progress)].compactMap { $0 }
            return parts.isEmpty ? L("Starting…") : parts.joined(separator: " · ")
        }
    }
}

/// One Epic install: title, a bar, the line of numbers, and Pause / Resume / Cancel. `compact` is
/// the activity strip's single row.
struct EpicDownloadRow: View {
    @Environment(AppState.self) private var state
    let download: EpicDownload
    var compact = false

    private var canPause: Bool { download.state == .running }
    private var canResume: Bool {
        if case .failed = download.state { return true }
        return download.state == .paused
    }

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(download.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                controls
            }
            ProgressView(value: download.progress.fraction ?? 0).tint(download.state == .running ? HB.amber : Color.secondary)
            HStack(spacing: 10) {
                Text(EpicDownloadText.line(for: download)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let amount = EpicDownloadText.amount(download.progress) {
                    Text(amount).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            if case .failed(let why) = download.state, !why.isEmpty {
                Text(why).font(.caption).foregroundStyle(HB.amber).lineLimit(3).textSelection(.enabled)
            }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            Image(systemName: download.state == .running ? "arrow.down.circle.fill" : "pause.circle.fill")
                .foregroundStyle(download.state == .running ? HB.amber : Color.secondary)
            Text(download.title).font(.callout.weight(.medium)).lineLimit(1)
            ProgressView(value: download.progress.fraction ?? 0).tint(HB.amber).frame(width: 90)
            Text(EpicDownloadText.line(for: download)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 12)
            controls
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 8) {
            if canPause {
                Button { state.epicDownloads.pause(download.appName) } label: { Label(L("Pause"), systemImage: "pause.fill") }
                    .buttonStyle(HBCompactButtonStyle())
            } else if canResume {
                Button { state.epicResume(download.appName) } label: { Label(L("Resume"), systemImage: "play.fill") }
                    .buttonStyle(HBCompactButtonStyle())
            }
            Button(L("Cancel")) { state.epicDownloads.cancel(download.appName) }
                .buttonStyle(HBCompactButtonStyle()).disabled(download.state == .pausing)
                .help(L("Stops the download. What was already downloaded is kept, so installing the game again continues from there."))
        }
    }
}

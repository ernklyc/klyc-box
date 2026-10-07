import AppKit
import KLYCKit

/// On the launch after a crash, offers (never sends) a pre-filled GitHub report. The first run only sets the clock, so an old crash
/// file from a previous install never triggers it. What the report contains is spelled out in the dialog, and the person sees it all in
/// the browser before submitting. See `CrashReport`.
@MainActor
enum CrashPrompt {
    private static let key = "crashPromptCheckedAt"

    static func checkOnLaunch(chip: String) {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: key) as? Date
        defaults.set(Date(), forKey: key)
        guard let last, let summary = CrashReport.newest(after: last) else { return }

        let alert = NSAlert()
        alert.messageText = L("KLYC-Box closed unexpectedly last time")
        alert.informativeText = L("If you like, open a pre-filled report on GitHub so it can be fixed. You will see everything in it before you send it: the type of crash, the versions of KLYC-Box and macOS, and the names of the functions where it happened. No file paths, no games, no accounts.")
        alert.addButton(withTitle: L("Review the report…"))
        alert.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(CrashReport.issueURL(summary, chip: chip, macos: Machine.macOSVersion()))
        }
    }
}

import AppKit
import KLYCKit
import UserNotifications

/// A macOS notification when a long job finishes while the window is not in front: a download, an install,
/// an "Improve" run. Asked for the first time it is needed; if the user says no, nothing else happens.
@MainActor
enum Notifier {
    static func finished(_ title: String, failed: Bool, startedAt: Date?) {
        // Short jobs are over before anyone looks away.
        guard let startedAt, Date().timeIntervalSince(startedAt) > 20, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = failed ? L("Something went wrong") : L("Done")
            content.body = title
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// A watched friend appeared online. Sent even while the window is in front: the friend list may not be on screen.
    static func friendsOnline(_ names: [String]) {
        guard !names.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L("A friend is online")
            content.body = names.joined(separator: ", ")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

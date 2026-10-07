import Foundation
import Observation

/// Whether Sparkle has found a newer version, so the app can say so without a popup the person may
/// have dismissed: a dot on the settings button and a line at the top of Settings. Sparkle's own
/// window still does the updating; this only keeps the fact in view until it is done.
@Observable @MainActor
final class UpdateStatus {
    static let shared = UpdateStatus()
    /// The version waiting, nil when this build is the newest (or nothing has been found yet).
    private(set) var availableVersion: String?

    func found(_ version: String) { availableVersion = version }
    func upToDate() { availableVersion = nil }
}

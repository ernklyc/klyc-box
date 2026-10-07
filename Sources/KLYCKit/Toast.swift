import Foundation
import Observation

/// One short confirmation shown after an action whose result is not visible on its own: a saved
/// setting, a copied path, a cleared cache. It says what happened, in a few words.
public struct Toast: Identifiable, Equatable, Sendable {
    public enum Style: Equatable, Sendable { case success, info, warning }

    public let id: UUID
    public var text: String
    public var style: Style

    public init(text: String, style: Style = .success, id: UUID = UUID()) {
        self.id = id; self.text = text; self.style = style
    }
}

/// Holds the confirmation currently on screen and takes it down by itself. One at a time: a
/// newer one replaces the older, because two stacked confirmations of the same kind of action
/// say less than the last one does, and a repeated identical text restarts the clock instead of
/// flashing.
@Observable @MainActor
public final class ToastCenter {
    public private(set) var current: Toast?
    /// How long a confirmation stays; a warning stays longer because it is to be read.
    public var duration: Duration = .milliseconds(2400)
    public var warningDuration: Duration = .milliseconds(4500)

    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ text: String, style: Toast.Style = .success) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let toast = Toast(text: trimmed, style: style, id: current?.text == trimmed && current?.style == style ? current!.id : UUID())
        current = toast
        dismissTask?.cancel()
        let wait = style == .warning ? warningDuration : duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    /// Takes the confirmation down, unless a newer one has replaced it in the meantime.
    public func dismiss(_ id: UUID? = nil) {
        if let id, current?.id != id { return }
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

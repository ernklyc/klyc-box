import SwiftUI
import KLYCKit

/// Shows the confirmation `AppState.notify` raised, low and centred above the activity strip, as a
/// glass capsule that fades in and out like everything else here. It never takes a click: what
/// is under it stays usable.
private struct ToastHost: ViewModifier {
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = state.toasts.current {
                    ToastView(toast: toast)
                        .padding(.bottom, 64).padding(.horizontal, HB.Space.l)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .id(toast.id)
                }
            }
            .animation(HB.Motion.standard, value: state.toasts.current?.id)
    }
}

private struct ToastView: View {
    let toast: Toast

    private var symbol: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    private var tint: Color {
        switch toast.style {
        case .success: return HB.good
        case .info: return Color.white.opacity(0.9)
        case .warning: return HB.amber
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 14, weight: .semibold))
            Text(toast.text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(2)
        }
        .padding(.horizontal, 14).frame(minHeight: 36)
        .hbGlass(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Where confirmations appear; put it once on a window's root view.
    func hbToasts() -> some View { modifier(ToastHost()) }
}

extension AppState {
    /// Confirms an action whose result is not visible on its own. Sound and a VoiceOver
    /// announcement come with the capsule, so it is felt without looking.
    func notify(_ text: String, style: Toast.Style = .success) {
        toasts.show(text, style: style)
        UISound.play(style == .warning ? .error : .select)
        AccessibilityNotification.Announcement(text).post()
    }
}

extension AppState {
    /// `update`, then says it was saved. For a change the person just made in a settings control.
    func updateAndConfirm(_ bottle: Bottle) {
        update(bottle)
        notify(L("Saved"))
    }

    /// Confirms once after a burst of changes: a text box that saves on every keystroke would
    /// otherwise flash a confirmation per letter. `key` names the burst; each new change inside
    /// the quiet period restarts it.
    func notifyDebounced(_ key: String, _ text: String, after delay: Duration = .milliseconds(700)) {
        debouncedNotices[key]?.cancel()
        debouncedNotices[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.debouncedNotices[key] = nil
            self.notify(text)
        }
    }
}

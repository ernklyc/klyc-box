import AppKit
import KLYCKit
import SwiftUI

/// A row that scrolls sideways and can be used with any mouse: the wheel moves it, arrow buttons appear at the ends that have more
/// to show, and the trackpad keeps working as before. (A plain horizontal ScrollView ignores a mouse wheel and hides its bar, so
/// with a mouse there was no way to reach the games past the edge.)
struct HScroll<Content: View>: View {
    @State private var controller = HScrollController()
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content.background(HScrollTracker(controller: controller))
        }
        // Where there is more to see, the row fades out instead of ending on a hard edge; the arrows sit on that fade.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: controller.canLeft ? 48 : 0)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: controller.canRight ? 48 : 0)
            }
        }
        .overlay(alignment: .leading) { if controller.canLeft { arrow(left: true) } }
        .overlay(alignment: .trailing) { if controller.canRight { arrow(left: false) } }
        .animation(HB.Motion.quick, value: controller.canLeft)
        .animation(HB.Motion.quick, value: controller.canRight)
    }

    private func arrow(left: Bool) -> some View {
        Button { UISound.play(.move); controller.page(left ? -1 : 1) } label: { Image(systemName: left ? "chevron.left" : "chevron.right") }
            .buttonStyle(HBIconButtonStyle())
        .padding(.horizontal, 6).transition(.opacity)
        .help(left ? L("Earlier") : L("Later"))
    }
}

@Observable @MainActor
final class HScrollController {
    @ObservationIgnored weak var scrollView: NSScrollView?
    var canLeft = false
    var canRight = false

    func update() {
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let x = sv.contentView.bounds.origin.x
        let maxX = max(0, doc.frame.width - sv.contentView.bounds.width)
        let left = x > 1, right = x < maxX - 1
        if left != canLeft { canLeft = left }
        if right != canRight { canRight = right }
    }

    /// A page to the left or right (most of the visible width), eased.
    func page(_ direction: CGFloat) {
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let clip = sv.contentView
        let maxX = max(0, doc.frame.width - clip.bounds.width)
        let target = min(max(0, clip.bounds.origin.x + direction * clip.bounds.width * 0.8), maxX)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            clip.animator().setBoundsOrigin(NSPoint(x: target, y: clip.bounds.origin.y))
        }
        sv.reflectScrolledClipView(clip)
    }
}

/// Sits behind the row's content to find the AppKit scroll view around it: reports how far it can scroll and turns a mouse wheel
/// over it into sideways movement. A trackpad (smooth, two-axis) is left alone, so it scrolls the page as it always did.
struct HScrollTracker: NSViewRepresentable {
    let controller: HScrollController

    func makeNSView(context: Context) -> TrackerView { let v = TrackerView(); v.controller = controller; return v }
    func updateNSView(_ view: TrackerView, context: Context) { view.controller = controller }

    final class TrackerView: NSView {
        weak var controller: HScrollController?
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard window != nil, monitor == nil, let sv = enclosingScrollView else { return }
            MainActor.assumeIsolated { controller?.scrollView = sv; controller?.update() }
            sv.contentView.postsBoundsChangedNotifications = true
            sv.documentView?.postsFrameChangedNotifications = true
            let refresh: (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.controller?.update() } }
            observers = [NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main, using: refresh)]
            if let doc = sv.documentView {
                observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: doc, queue: .main, using: refresh))
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) ?? event }
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let sv = enclosingScrollView, event.window === window, !event.hasPreciseScrollingDeltas,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            let point = sv.convert(event.locationInWindow, from: nil)
            guard sv.bounds.contains(point), let doc = sv.documentView else { return event }
            let clip = sv.contentView
            let maxX = max(0, doc.frame.width - clip.bounds.width)
            guard maxX > 0 else { return event }
            // Wheel down = further along the row.
            let x = min(max(0, clip.bounds.origin.x - event.scrollingDeltaY * 14), maxX)
            clip.setBoundsOrigin(NSPoint(x: x, y: clip.bounds.origin.y))
            sv.reflectScrolledClipView(clip)
            return nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

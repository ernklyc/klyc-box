import AppKit
import SwiftUI

// MARK: - Design tokens
//
// One place for colours, sizes and motion. A screen asks for `HB.Metric.icon`, not for 40; for `HB.Motion.standard`, not for
// `.easeInOut(duration: 0.2)`: changing the feel of the app is then one edit here, and no two screens drift apart.

enum HB {
    // Near-black with a cool blue tint and a steel-blue accent: the same ink and greys as klycbox.ernklyc.dev and the app icon.
    // The names are historical (amber was the old accent); every use follows the accent.
    static let amber = Color(red: 0.38, green: 0.47, blue: 0.68)
    static let amberDeep = Color(red: 0.13, green: 0.17, blue: 0.30)
    static let ground = Color(red: 0.044, green: 0.051, blue: 0.068)
    /// The lit state of a button, tab or segment: a soft white with dark ink on it, as on the website.
    static let lit = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let ink = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let card = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.10)
    static let good = Color(red: 0.45, green: 0.78, blue: 0.60)
    static let warn = Color(red: 0.96, green: 0.72, blue: 0.32)
    static let bad = Color(red: 0.98, green: 0.62, blue: 0.50)

    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(.secondary)
    }
}

extension HB {
    /// Sizes shared by every screen.
    enum Metric {
        static let icon: CGFloat = 36          // round icon buttons: back, settings, refresh, arrows, close
        static let primary: CGFloat = 42       // the main button of a screen
        static let secondary: CGFloat = 36     // every other button
        static let compact: CGFloat = 30       // buttons inside panels and sheets
        static let chip: CGFloat = 30          // filter chips and toggles
        static let row: CGFloat = 38           // a row in a list of choices (settings categories)
        static let radius: CGFloat = 16        // cards
        static let margin: CGFloat = 40        // a page's side margin
    }

    /// Gaps between things: inside a control, between buttons, between cards, between sections of a page.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8       // between buttons that belong together, between chips
        static let m: CGFloat = 12      // inside a card, between a title and its text block
        static let l: CGFloat = 16      // between cards
        static let xl: CGFloat = 24     // between the sections of a page
    }

    /// How things move. Short and soft; the same for a chip, a tab and a page.
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)         // hover, press, a chip switching on or off
        static let standard = Animation.easeInOut(duration: 0.22)    // a tab or a section changing, content replacing a placeholder
        static let slow = Animation.easeInOut(duration: 0.35)        // something large arriving
        static let page: Animation = .easeInOut(duration: 0.24)       // a page opening: a soft fade
    }
}

/// A secondary text action ("See all", "Show more", "Details"): a small, quiet capsule, so it reads as a button, not as stray blue text.
struct HBTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1).fixedSize()
            .foregroundStyle(Color.white.opacity(hovering ? 1 : 0.85))
            .padding(.horizontal, 12).frame(height: HB.Metric.compact)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.20 : hovering ? 0.15 : 0.09)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(HB.Motion.quick, value: hovering)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// A setting that is on or off: its name and a line about it on the left, a switch on the right. The same row everywhere.
struct HBToggleRow: View {
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .medium))
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(HB.amber)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).hbCard(radius: HB.Metric.radius)
    }
}

/// A round glass icon button. Use as a button style on a label that is just an `Image`.
struct HBIconButtonStyle: ButtonStyle {
    var size: CGFloat = HB.Metric.icon
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.95))
            .frame(width: size, height: size)
            .hbGlass(Circle(), interactive: true)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(HB.Motion.quick, value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
    }
}

extension View {
    /// The same round glass for a label that is not a plain button (the "+" menu).
    func hbIconChrome(size: CGFloat = HB.Metric.icon) -> some View {
        self.font(.system(size: size * 0.38, weight: .semibold)).frame(width: size, height: size).hbGlass(Circle(), interactive: true).contentShape(Circle())
    }

    /// Every page opens the same way: a soft fade, no movement (a slide up from below read as jumpy). Applied to a page's root view.
    func hbPage() -> some View { modifier(HBPageAppear()) }

    /// What every page's root view gets: the opening motion, a clear toolbar and no navigation title (the app draws its own bar).
    func hbPageRoot() -> some View { self.hbPage().hbToolbarClear().navigationTitle("") }
}

struct HBPageAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : HB.Motion.page) { shown = true } }
    }
}

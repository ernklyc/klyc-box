import Foundation

/// The display a game will draw on, in the terms the scaling settings use.
public struct DisplayInfo: Equatable, Sendable {
    public var pointWidth: Int
    public var pointHeight: Int
    /// 1 on a standard display, 2 on Retina.
    public var backingScale: Double

    public init(pointWidth: Int, pointHeight: Int, backingScale: Double) {
        self.pointWidth = pointWidth; self.pointHeight = pointHeight; self.backingScale = max(backingScale, 1)
    }

    public var isRetina: Bool { backingScale > 1.01 }
    public var pixelWidth: Int { Int((Double(pointWidth) * backingScale).rounded()) }
    public var pixelHeight: Int { Int((Double(pointHeight) * backingScale).rounded()) }
    public var pointMegapixels: Double { Double(pointWidth * pointHeight) / 1_000_000 }
    public var pixelMegapixels: Double { Double(pixelWidth * pixelHeight) / 1_000_000 }
}

/// What the display means for the "Retina resolution at 100%" option, in plain numbers.
///
/// Wine's Mac driver draws a game at the display's point size (sharpness of a standard display,
/// scaled up) unless the option asks for the display's native pixels. On a standard display there
/// are no extra pixels to ask for; on a Retina display they cost the pixel count's ratio
/// (4× at 2×). A recommendation is only made where one exists: the right choice on a Retina
/// display depends on how heavy the game is, so there the numbers are shown and the choice is left.
public struct DisplayAdvice: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Not Retina, the option is off: nothing to change.
        case standard
        /// Not Retina, yet the option is on: it has no pixels to add.
        case standardOptionOn
        /// Retina: the cost of native pixels, for the player to weigh.
        case retina
    }

    public var kind: Kind
    public var display: DisplayInfo
    /// The value the option should have, when a change is advised; nil when the setting is fine
    /// or the choice is the player's.
    public var recommendedRetinaAt100: Bool?

    /// How many times more pixels native resolution draws than the point size.
    public var costFactor: Double { display.isRetina ? display.pixelMegapixels / max(display.pointMegapixels, 0.001) : 1 }

    public static func advice(for display: DisplayInfo, retinaAt100: Bool) -> DisplayAdvice {
        if display.isRetina { return DisplayAdvice(kind: .retina, display: display, recommendedRetinaAt100: nil) }
        return retinaAt100
            ? DisplayAdvice(kind: .standardOptionOn, display: display, recommendedRetinaAt100: false)
            : DisplayAdvice(kind: .standard, display: display, recommendedRetinaAt100: nil)
    }
}

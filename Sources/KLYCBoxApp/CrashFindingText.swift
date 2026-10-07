import Foundation
import KLYCKit

/// The words for a finding: what it is, what it means, and the label of its one button. The
/// kit decides *what* the log says; the wording lives here with the other screens' text.
extension CrashFinding {
    var headline: String {
        let d = detail ?? ""
        switch kind {
        case .missingRuntime: return String(format: L("%@ is missing"), d)
        case .missingDotNet: return L("The game needs .NET")
        case .missingDirectXFiles: return String(format: L("DirectX file %@ is missing"), d)
        case .missingMedia: return String(format: L("Video playback file %@ is missing"), d)
        case .missingLibrary: return String(format: L("%@ is missing"), d)
        case .antiCheat: return String(format: L("%@ stopped the game"), d)
        case .graphics: return L("The graphics driver stopped")
        case .outOfMemory: return L("The game ran out of memory")
        case .crash: return L("The game crashed")
        case .syncMismatch: return L("The environment runs in a different sync mode")
        }
    }

    var meaning: String {
        switch kind {
        case .missingRuntime: return L("The game needs the Visual C++ runtime. Installing it usually fixes this.")
        case .missingDotNet: return L("Installing .NET Framework 4.8 usually fixes this.")
        case .missingDirectXFiles: return L("This engine has no copy of that file. Another graphics mode may avoid it.")
        case .missingMedia: return L("Wine's video support lacks this file, and a game that plays a video at start can close because of it.")
        case .missingLibrary: return L("A file the game needs was not found. Verifying or reinstalling the game in its launcher may bring it back.")
        case .antiCheat: return L("This anti-cheat does not run under Wine on a Mac, so the game cannot start. Nothing in KLYC-Box can change that.")
        case .graphics: return L("Another graphics mode often avoids it.")
        case .outOfMemory: return L("Close other apps and lower the game's graphics quality.")
        case .crash: return L("Another graphics mode is the most common fix.")
        case .syncMismatch: return L("Stopping the environment's processes lets the next Play start fresh.")
        }
    }

    /// The label of the fix's button, nil when the fix is "nothing the app can do".
    var fixTitle: String? {
        switch fix {
        case .installRecipe(let id): return String(format: L("Install %@"), AppState.recipe(id)?.title ?? id)
        case .restartEnvironment: return L("Stop all processes")
        case .tryOtherRenderer, .none: return nil
        }
    }

    /// Whether switching the graphics mode is a sensible thing to offer next to this finding.
    var suggestsOtherRenderer: Bool { fix == .tryOtherRenderer }
}

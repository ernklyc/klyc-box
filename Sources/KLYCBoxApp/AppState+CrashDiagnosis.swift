import Foundation
import KLYCKit

/// A launch that ended at once, explained from its own log.
extension AppState {
    /// Shows the "quit right away" alert, with the cause the log names when it names one. The
    /// log is read off the main thread (it can be large); the alert waits for it, which takes
    /// milliseconds, so it never shows once and then changes.
    func presentCrash(_ suggestion: CrashSuggestion) {
        let log = URL(fileURLWithPath: suggestion.logPath)
        Task {
            let findings = await Task.detached(priority: .userInitiated) {
                CrashDiagnosis.diagnose(log: CrashDiagnosis.tail(of: log))
            }.value
            var s = suggestion
            s.findings = findings
            crashSuggestion = s
            if let top = findings.first {
                appendLog("\(s.program): \(top.headline) (\(top.kind.rawValue)\(top.detail.map { ": \($0)" } ?? ""))")
            }
        }
    }

    /// The button the top finding offers. Installing needs the environment the game ran in.
    func applyCrashFix(_ fix: CrashFinding.Fix, for s: CrashSuggestion) {
        guard let bottle = bottles.first(where: { $0.name == s.bottleName }) else { return }
        switch fix {
        case .installRecipe(let id): applyRecipe(id, to: bottle)
        case .restartEnvironment: killBottle(bottle)
        case .tryOtherRenderer, .none: break
        }
    }
}

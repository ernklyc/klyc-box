import Foundation

public enum PlaytimeText {
    /// "2 h 14 min", "35 min", "less than a minute": what a person reads on a game's page.
    public static func format(seconds: Int) -> String {
        if seconds < 60 { return L("less than a minute") }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: L("%d min"), minutes) }
        return String(format: L("%d h %d min"), minutes / 60, minutes % 60)
    }

    /// Launch arguments as the list a launch takes: split on spaces, a quoted part stays together.
    public static func arguments(from text: String) -> [String] {
        var out: [String] = [], current = "", quote: Character?
        for ch in text {
            if let q = quote { if ch == q { quote = nil } else { current.append(ch) } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == " " || ch == "\t" || ch == "\n" { if !current.isEmpty { out.append(current); current = "" } }
            else { current.append(ch) }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

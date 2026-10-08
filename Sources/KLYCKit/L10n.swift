import Foundation

/// Tiny localization layer: English strings are the keys; Turkish, Simplified Chinese and Japanese are translated.
/// (A proper String Catalog needs an Xcode project; this keeps SwiftPM-only builds localized.)
public func L(_ en: String) -> String {
    // Tests assert the English text, whatever language the Mac running them is set to.
    if AppLanguage.underTest { return en }
    switch AppLanguage.active {
    case "tr": return L10n.tr[en] ?? L10n.trKit[en] ?? en
    case "zh": return L10n.zh[en] ?? en
    case "ja": return L10n.ja[en] ?? en
    default: return en
    }
}

/// Which language the interface uses: the choice in Settings, or (Automatic) the Mac's first preferred language.
public enum AppLanguage: String, CaseIterable, Sendable {
    case auto, en, tr, zh, ja
    public static let defaultsKey = "appLanguage"

    /// Name shown in the picker, in its own language so a person who cannot read the current one can still find it.
    public var title: String {
        switch self {
        case .auto: return L("Automatic (Mac's language)")
        case .en: return "English"
        case .tr: return "Türkçe"
        case .zh: return "简体中文"
        case .ja: return "日本語"
        }
    }

    /// Pure: the language code to use from the saved choice and the system's first preferred language.
    public static func resolve(override: String?, system: String) -> String {
        if let o = override, o != "auto", AppLanguage(rawValue: o) != nil { return o }
        let s = system.lowercased()
        for code in ["tr", "zh", "ja"] where s.hasPrefix(code) { return code }
        return "en"
    }

    /// Read once: L() runs thousands of times per screen, and a change of language applies after a restart anyway.
    public static let active: String = code()
    static let underTest: Bool = NSClassFromString("XCTestCase") != nil

    public static func code() -> String {
        resolve(override: UserDefaults.standard.string(forKey: defaultsKey), system: Locale.preferredLanguages.first ?? "")
    }
}

/// The language the Steam store speaks to match the app's: descriptions, reviews, tags and the price format. Prices keep the Turkish region
/// (the player's own store); only the words change. Under XCTest it stays Turkish so the parsing tests keep their fixtures.
public enum StoreLanguage {
    public static var steam: String { code(AppLanguage.underTest ? "tr" : AppLanguage.active) }
    public static var locale: Locale { Locale(identifier: ["tr": "tr_TR", "zh": "zh_CN", "ja": "ja_JP"][AppLanguage.underTest ? "tr" : AppLanguage.active] ?? "en_US") }
    /// Steam's own language names.
    public static func code(_ app: String) -> String { ["tr": "turkish", "zh": "schinese", "ja": "japanese"][app] ?? "english" }
}

enum L10n {
}

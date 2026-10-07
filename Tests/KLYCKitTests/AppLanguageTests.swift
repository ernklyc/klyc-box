import XCTest
@testable import KLYCKit

final class AppLanguageTests: XCTestCase {
    func testAutomaticFollowsTheMacAndFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolve(override: nil, system: "tr-TR"), "tr")
        XCTAssertEqual(AppLanguage.resolve(override: "auto", system: "zh-Hans-CN"), "zh")
        XCTAssertEqual(AppLanguage.resolve(override: nil, system: "ja-JP"), "ja")
        XCTAssertEqual(AppLanguage.resolve(override: nil, system: "de-DE"), "en")
        XCTAssertEqual(AppLanguage.resolve(override: nil, system: ""), "en")
    }

    func testAChoiceBeatsTheSystemAndAJunkChoiceIsIgnored() {
        XCTAssertEqual(AppLanguage.resolve(override: "ja", system: "tr-TR"), "ja")
        XCTAssertEqual(AppLanguage.resolve(override: "en", system: "zh-CN"), "en")
        XCTAssertEqual(AppLanguage.resolve(override: "klingon", system: "tr-TR"), "tr")
    }

    /// Every Turkish key has a Chinese and a Japanese translation with the same placeholders: a missing one would show English,
    /// a changed one would crash or show garbage in String(format:).
    func testTranslationsCoverTheTurkishKeysWithSamePlaceholders() throws {
        let placeholders: (String) -> [String] = { s in
            (try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfsu%]|%\\.\\d+f|%ld|%lld")).matches(in: s, range: NSRange(s.startIndex..., in: s))
                .map { String(s[Range($0.range, in: s)!]) }.sorted()
        }
        let keys = Set(L10n.tr.keys).union(L10n.trKit.keys)
        for (name, table) in [("zh", L10n.zh), ("ja", L10n.ja)] {
            var missing = 0, missingKeys: [String] = [], wrong: [String] = []
            for k in keys {
                guard let v = table[k], !v.isEmpty else { missing += 1; missingKeys.append(k); continue }
                if placeholders(k) != placeholders(v) { wrong.append(k) }
            }
            XCTAssertEqual(missing, 0, "\(name): \(missing) keys have no translation, e.g. \(missingKeys.sorted().prefix(8))")
            XCTAssertTrue(wrong.isEmpty, "\(name): placeholders differ for \(wrong.prefix(3))")
        }
    }
}

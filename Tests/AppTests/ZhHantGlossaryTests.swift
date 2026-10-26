import XCTest

/// **zh-Hant uses one word for each thing** (Chiu 2026-10-26, #289). The
/// glossary is ADR `2026-10-26-zh-hant-uses-one-word-for-each-thing`; this
/// holds both catalogues to the words it retired, so a new string written with
/// 相片 or 停留點 fails here rather than in Chiu's next walk through the app.
///
/// Reads the source catalogues, as `LocalizationCoverageTests` reads the source
/// tree: every zh-Hant value, including plural and device variations.
final class ZhHantGlossaryTests: XCTestCase {
    /// A retired word, the glossary word that replaced it, and the only keys
    /// allowed to keep it.
    private struct Retired {
        let word: String
        let use: String
        var allowed: Set<String> = []
    }

    private static let retired: [Retired] = [
        // 匯出 is kept for a file that really leaves the app.
        Retired(word: "匯出", use: "製作", allowed: ["about_export_diagnostics"]),
        Retired(word: "輸出", use: "製作"),
        Retired(word: "算圖", use: "製作"),
        Retired(word: "回顧", use: "旅程影片"),
        Retired(word: "相片", use: "照片"),
        Retired(word: "您", use: "你"),
        Retired(word: "停留", use: "地點"),
        Retired(word: "行程", use: "旅程"),
        // The home-screen name stays Kamome; inside a sentence it is 卡摸咩.
        Retired(word: "Kamome", use: "卡摸咩", allowed: ["CFBundleDisplayName", "CFBundleName"])
    ]

    func testNoZhHantValueUsesARetiredWord() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources")
        var checked = 0
        for catalogue in ["Localizable", "InfoPlist"] {
            let url = resources.appendingPathComponent("\(catalogue).xcstrings")
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = try XCTUnwrap(json?["strings"] as? [String: Any], "\(catalogue): no strings")
            for (key, entry) in strings {
                let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
                guard let zh = localizations?["zh-Hant"] else { continue }
                for value in Self.values(in: zh) {
                    checked += 1
                    for rule in Self.retired where value.contains(rule.word) && !rule.allowed.contains(key) {
                        XCTFail("\(catalogue) \(key): 「\(rule.word)」 is retired, the word is 「\(rule.use)」: \(value)")
                    }
                }
            }
        }
        // An empty walk would pass every rule above.
        XCTAssertGreaterThan(checked, 250, "the zh-Hant values were not found")
    }

    /// Every `stringUnit` value under a localization, however deep the
    /// variations and substitutions nest.
    private static func values(in node: Any) -> [String] {
        guard let dictionary = node as? [String: Any] else { return [] }
        var found: [String] = []
        if let unit = dictionary["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            found.append(value)
        }
        for (key, child) in dictionary where key != "stringUnit" {
            found += values(in: child)
        }
        return found
    }
}

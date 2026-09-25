import XCTest

final class LocalizationCoverageTests: XCTestCase {
    private func localizedValue(_ key: String, locale: String) throws -> String {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: locale, ofType: "lproj"),
            "\(locale).lproj missing from app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// **Every key the screens use resolves, in both languages** (2026-09-25).
    ///
    /// The tests above hold chosen keys to chosen words; nothing held the rest.
    /// So the whole stop photo picker — eleven keys, including the only sentence
    /// that explains its tap / hold gestures — shipped as raw `stop_photos_*`
    /// identifiers, and the export sheet's photo section header with it. A
    /// missing key resolves to itself, which is what this checks for.
    ///
    /// Scans the call sites that take a key literal. A key built at runtime is
    /// out of its reach; the hand-written tests above are still the net there.
    func testEveryKeyTheUIUsesResolvesInBothLanguages() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // A call that takes a key, then the snake_case literal it was given.
        let callSite = #"(?:Text|Label|Button|Toggle|Picker|Section|navigationTitle|confirmationDialog|localized:)"#
        let pattern = try NSRegularExpression(pattern: callSite + #"\(?\s*"([a-z][a-z0-9]*(?:_[a-z0-9]+)+)""#)
        var keys: [String: String] = [:]
        for directory in ["UI", "App"] {
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: repoRoot.appendingPathComponent(directory), includingPropertiesForKeys: nil
                )
            )
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(source.startIndex..., in: source)
                for match in pattern.matches(in: source, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                    let key = String(source[keyRange])
                    keys[key] = keys[key] ?? file.lastPathComponent
                }
            }
        }
        XCTAssertGreaterThan(keys.count, 100, "the scan found too few keys to mean anything — has the source moved?")
        for (key, file) in keys.sorted(by: { $0.key < $1.key }) {
            for locale in ["en", "zh-Hant"] {
                XCTAssertNotEqual(
                    try localizedValue(key, locale: locale), key,
                    "\(file) uses \"\(key)\", which has no \(locale) string — the screen shows the raw key"
                )
            }
        }
    }
}

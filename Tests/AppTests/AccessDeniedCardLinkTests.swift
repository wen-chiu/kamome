import XCTest

/// **Footprints' 「打開設定」 draws as a link, in the accent** (#318). In
/// Footprints' list the card's `Link` took the row's style and drew in primary
/// black, beside a grey body, so it read as a heading rather than something to
/// tap. Borderless, it takes the accent (ADR
/// 2026-10-26-text-and-controls-take-a-deeper-teal), as the list's other
/// buttons already do. The colour was checked on the simulator in light and
/// dark; this holds what it rests on.
final class AccessDeniedCardLinkTests: XCTestCase {
    func testTheSettingsLinkIsBorderless() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(
            contentsOf: repoRoot.appendingPathComponent("UI/Discovery/DiscoveryStates.swift"), encoding: .utf8
        )
        let start = try XCTUnwrap(file.range(of: "struct AccessDeniedCard: View {"))
        let end = try XCTUnwrap(file.range(of: "\n}\n", range: start.upperBound..<file.endIndex))
        let card = file[start.lowerBound..<end.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(card.contains("Link(\"access_denied_settings\""), "this is not the card's link any more")
        XCTAssertTrue(card.contains(".buttonStyle(.borderless)"), "in a List row the link draws in primary black (#318)")
    }
}

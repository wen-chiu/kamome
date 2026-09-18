import XCTest

@testable import KamomeImportKit

/// The card's photographs: highlights lead, the rest sample the whole journey.
final class PhotoCoverSelectorTests: XCTestCase {
    private func candidates(_ count: Int, highlights: Set<Int> = []) -> [PhotoCoverSelector.Candidate] {
        (0..<count).map { PhotoCoverSelector.Candidate(assetId: "p\($0)", isHighlight: highlights.contains($0)) }
    }

    func testHighlightsLeadThenTheRestIsSpread() {
        let picked = PhotoCoverSelector.select(candidates(20, highlights: [7]), count: 3)
        XCTAssertEqual(picked.first, "p7", "the favourite leads")
        XCTAssertEqual(picked.count, 3)
        XCTAssertEqual(Set(picked).count, 3, "never repeats")
        XCTAssertTrue(picked.contains("p0"), "the rest starts at the beginning")
        XCTAssertTrue(picked.contains("p19"), "and reaches the end")
    }

    /// Ten photographs, three slots: the ends and the middle (4.5 rounds up).
    func testWithNoHighlightsTheSpreadCoversTheJourney() {
        XCTAssertEqual(PhotoCoverSelector.select(candidates(10), count: 3), ["p0", "p5", "p9"])
    }

    func testFewerPhotographsThanAskedReturnsThemAll() {
        XCTAssertEqual(PhotoCoverSelector.select(candidates(2), count: 3), ["p0", "p1"])
        XCTAssertEqual(PhotoCoverSelector.select([], count: 3), [])
        XCTAssertEqual(PhotoCoverSelector.select(candidates(5), count: 0), [])
    }

    func testMoreHighlightsThanSlotsKeepsTheEarliest() {
        XCTAssertEqual(PhotoCoverSelector.select(candidates(10, highlights: [1, 4, 6, 8]), count: 3), ["p1", "p4", "p6"])
    }
}

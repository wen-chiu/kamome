import KamomeConfig
@testable import KamomeExportEngine
import KamomeImportKit
import XCTest

/// **Which of a stop's photographs reach the film, and which stops do**
/// (Chiu 2026-09-24).
///
/// People reported the film picking photographs that were not the ones they
/// wanted, and marking a photo in the Stop Editor appeared to do nothing. Both
/// had one cause: each stop's deck was an eight-photo spread cut to its first
/// three, so only the first ~30% of a visit could reach the film, the visit's
/// first frame always did, and a highlight past the first was dropped.
final class StopDeckPickTests: XCTestCase {
    private func shipped() throws -> TrackingConfig {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url)
    }

    private func visit(_ count: Int, highlights: Set<Int> = []) -> [(ref: Int, isHighlight: Bool)] {
        (0..<count).map { (ref: $0, isHighlight: highlights.contains($0)) }
    }

    // MARK: - The deck

    /// The defect itself: three photographs from a hundred must sample the whole
    /// visit, not its first third.
    func testThreeFromAHundredSampleTheWholeVisit() {
        let deck = PhotoDeckSelector.pick(visit(100), count: 3)
        XCTAssertEqual(deck, [16, 50, 83])
        XCTAssertGreaterThan(deck.last ?? 0, 66, "the last third of the visit must be reachable")
        XCTAssertFalse(deck.contains(0), "the visit's first frame is not guaranteed a place")
    }

    /// Every highlight the deck has room for is shown, and they lead.
    func testHighlightsAreAllKeptAndLead() {
        let deck = PhotoDeckSelector.pick(visit(60, highlights: [5, 40, 59]), count: 3)
        XCTAssertEqual(deck, [5, 40, 59])

        let roomy = PhotoDeckSelector.pick(visit(60, highlights: [40]), count: 3)
        XCTAssertEqual(roomy.first, 40, "a highlight leads the deck")
        XCTAssertEqual(roomy.count, 3)
        XCTAssertEqual(Set(roomy).count, 3, "no repeats")
    }

    /// More highlights than room: the highlights themselves are spread, and
    /// nothing unmarked displaces a marked photograph.
    func testExcessHighlightsAreSpreadAmongThemselves() {
        let marked = Set(0..<12).map { $0 * 5 }
        let deck = PhotoDeckSelector.pick(visit(60, highlights: Set(marked)), count: 5)
        XCTAssertEqual(deck.count, 5)
        XCTAssertTrue(deck.allSatisfy { marked.contains($0) }, "only marked photographs, \(deck)")
        XCTAssertEqual(deck, deck.sorted(), "time order")
        XCTAssertGreaterThan(deck.last ?? 0, 40, "spread across the marked set, not its start")
    }

    func testSmallStopsShowWhatTheyHave() {
        XCTAssertEqual(PhotoDeckSelector.pick(visit(2), count: 3), [0, 1])
        XCTAssertEqual(PhotoDeckSelector.pick(visit(0), count: 3), [])
        XCTAssertEqual(PhotoDeckSelector.pick(visit(10), count: 0), [])
    }

    /// Chiu's rule: highlights lift a deck above its allocation, never past the cap.
    func testHighlightsLiftTheDeckUpToTheCap() throws {
        let cap = try shipped().photoImport.deckHighlightMaxPhotos
        XCTAssertEqual(cap, 5)
        XCTAssertEqual(PhotoDeckSelector.deckCount(allocated: 3, highlights: 0, highlightCap: cap), 3)
        XCTAssertEqual(PhotoDeckSelector.deckCount(allocated: 3, highlights: 1, highlightCap: cap), 3)
        XCTAssertEqual(PhotoDeckSelector.deckCount(allocated: 3, highlights: 4, highlightCap: cap), 4)
        XCTAssertEqual(PhotoDeckSelector.deckCount(allocated: 3, highlights: 12, highlightCap: cap), 5)
        XCTAssertEqual(PhotoDeckSelector.deckCount(allocated: 0, highlights: 2, highlightCap: cap), 2)
    }

    // MARK: - The stops

    /// A marked stop that ranks below the earned count is still presented, and
    /// the stop it displaces is an unmarked one.
    func testAMarkedStopIsAlwaysKept() throws {
        let config = try shipped().export
        // 10 stops earn 8; the marked one ranks last on photographs.
        var signals = (0..<9).map { StopPhotoAllocator.Signal(photoCount: 100 - $0) }
        signals.append(StopPhotoAllocator.Signal(photoCount: 1, favoriteCount: 1))
        let tiers = StopPhotoAllocator.triage(signals, config: config)
        XCTAssertNotNil(tiers[9], "the marked stop is presented")
        XCTAssertEqual(tiers.compactMap { $0 }.count, 8, "still the earned count")
        XCTAssertNil(tiers[8], "the lowest-ranked unmarked stop gives up its place")
    }

    /// With no marks anywhere, triage is the ranked cut it always was.
    func testNoMarksMeansTheRankedCut() throws {
        let config = try shipped().export
        let signals = (0..<10).map { StopPhotoAllocator.Signal(photoCount: 100 - $0) }
        let tiers = StopPhotoAllocator.triage(signals, config: config)
        XCTAssertEqual(tiers.map { $0 != nil }, Array(repeating: true, count: 8) + [false, false])
    }

    /// More marked stops than the trip earned: every one of them stays.
    func testMoreMarkedStopsThanEarnedAreAllKept() throws {
        let config = try shipped().export
        let signals = (0..<10).map { StopPhotoAllocator.Signal(photoCount: 10, favoriteCount: $0 == 9 ? 0 : 1) }
        let tiers = StopPhotoAllocator.triage(signals, config: config)
        XCTAssertEqual(tiers.prefix(9).compactMap { $0 }.count, 9)
        XCTAssertNil(tiers[9], "no room is left for the unmarked stop")
    }

    // MARK: - The length

    /// A trip with no marks is priced exactly as before; decks the marks lifted
    /// buy the extra slots they need.
    func testDurationPaysForLiftedDecks() throws {
        let config = try shipped().export
        let standard = Array(repeating: config.tierStandardPhotos, count: 8)
        XCTAssertEqual(StopPhotoAllocator.earnedDurationS(photoCounts: standard, config: config),
                       StopPhotoAllocator.earnedDurationS(presentedStops: 8, config: config),
                       accuracy: 1e-9)
        let lifted = Array(repeating: 5, count: 8)
        let extra = StopPhotoAllocator.earnedDurationS(photoCounts: lifted, config: config)
            - StopPhotoAllocator.earnedDurationS(presentedStops: 8, config: config)
        XCTAssertGreaterThan(extra, 0)
    }
}

import KamomeImportKit
import XCTest

/// **The app's pick once it has looked at the photographs** (ADR 2026-09-25 (c)).
///
/// The first test is the one that makes the rest safe to ship: with no signal,
/// the analysed pick is the time-based pick, index for index. A trip whose
/// photographs Vision never saw plays exactly as it did before.
final class PhotoSignalPickTests: XCTestCase {
    private let threshold = 0.4

    private func visit(_ count: Int, highlights: Set<Int> = []) -> [(ref: Int, isHighlight: Bool)] {
        (0..<count).map { (ref: $0, isHighlight: highlights.contains($0)) }
    }

    /// A unit vector along `axis` — two photographs share a print when they
    /// share an axis (distance 0) and are √2 apart otherwise.
    private func print(_ axis: Int) -> [Float] {
        (0..<16).map { $0 == axis ? 1 : 0 }
    }

    // MARK: - No signal is the old pick

    func testWithNoSignalItIsTheTimeBasedPickExactly() {
        for count in 0...60 {
            for size in 0...7 {
                for highlights in [Set<Int>(), [0], [count / 2], Set(stride(from: 0, to: count, by: 7))] {
                    let candidates = visit(count, highlights: highlights)
                    XCTAssertEqual(
                        PhotoDeckSelector.pick(
                            candidates, count: size,
                            signals: Array(repeating: PhotoSignal(), count: count), duplicateDistance: threshold
                        ),
                        PhotoDeckSelector.pick(candidates, count: size),
                        "\(count) photographs, deck of \(size), highlights \(highlights.sorted())"
                    )
                }
            }
        }
    }

    // MARK: - What analysis changes

    func testUtilityPhotographsAreNeverPickedUnlessStarred() {
        var signals = (0..<6).map { PhotoSignal(featurePrint: print($0)) }
        signals[1].isUtility = true
        signals[4].isUtility = true
        let deck = PhotoDeckSelector.pick(visit(6), count: 6, signals: signals, duplicateDistance: threshold)
        XCTAssertEqual(deck, [0, 2, 3, 5])

        let starred = PhotoDeckSelector.pick(
            visit(6, highlights: [4]), count: 2, signals: signals, duplicateDistance: threshold
        )
        XCTAssertEqual(starred.first, 4, "a starred receipt is the person's call")
    }

    /// Ten frames of one waterfall, then two other views: three slots show
    /// three different things, not three frames of the burst.
    func testABurstIsOneMoment() {
        let signals = (0..<12).map { PhotoSignal(featurePrint: print($0 < 10 ? 0 : $0)) }
        let deck = PhotoDeckSelector.pick(visit(12), count: 3, signals: signals, duplicateDistance: threshold)
        XCTAssertEqual(deck.count, 3)
        XCTAssertEqual(deck.filter { $0 < 10 }.count, 1, "one frame of the burst: \(deck)")
        XCTAssertEqual(Array(deck.suffix(2)), [10, 11])
        // Without analysis, the burst took two of the three slots.
        XCTAssertEqual(PhotoDeckSelector.pick(visit(12), count: 3).filter { $0 < 10 }.count, 2)
    }

    /// Within a burst the best-scored frame stands for it; across slots, each
    /// takes its best-scored moment rather than its centre.
    func testTheBestPhotographNearEachSlotWins() {
        var burst = (0..<5).map { _ in PhotoSignal(quality: 0.1, featurePrint: print(0)) }
        burst[3].quality = 0.9
        let burstDeck = PhotoDeckSelector.pick(visit(5), count: 1, signals: burst, duplicateDistance: threshold)
        XCTAssertEqual(burstDeck, [3])

        // Nine distinct views, three slots: centres 1, 4, 7 by time.
        var views = (0..<9).map { PhotoSignal(quality: 0, featurePrint: print($0)) }
        views[0].quality = 0.8
        views[5].quality = 0.5
        views[8].quality = 0.6
        let deck = PhotoDeckSelector.pick(visit(9), count: 3, signals: views, duplicateDistance: threshold)
        XCTAssertEqual(deck, [0, 5, 8])
        XCTAssertEqual(PhotoDeckSelector.pick(visit(9), count: 3), [1, 4, 7])
    }

    /// Without quality scores (iOS 17) a burst still collapses, and the frame
    /// kept is the one nearest the middle.
    func testWithoutScoresTheMiddleFrameStandsForItsMoment() {
        let signals = (0..<5).map { _ in PhotoSignal(featurePrint: print(0)) }
        XCTAssertEqual(PhotoDeckSelector.pick(visit(5), count: 3, signals: signals, duplicateDistance: threshold), [2])
    }

    func testAMomentRepeatingAHighlightIsDropped() {
        let signals = (0..<4).map { PhotoSignal(featurePrint: print($0 == 3 ? 0 : $0)) }
        // 0 is starred; 3 is the same view later in the visit.
        let deck = PhotoDeckSelector.pick(
            visit(4, highlights: [0]), count: 4, signals: signals, duplicateDistance: threshold
        )
        XCTAssertEqual(deck, [0, 1, 2])
    }

    /// Anchored, not chained: a slow pan whose neighbours are each close does
    /// not collapse into one moment once it has moved away from its first frame.
    func testAPanIsNotChainedIntoOneMoment() {
        // Each frame 0.3 from the next along a line, so frame 2 is 0.6 from frame 0.
        let signals = (0..<4).map { step in PhotoSignal(featurePrint: [Float(step) * 0.3, 0]) }
        let deck = PhotoDeckSelector.pick(visit(4), count: 4, signals: signals, duplicateDistance: threshold)
        XCTAssertEqual(deck.count, 2, "frames 0–1 are one moment, frames 2–3 another: \(deck)")
    }

    func testDistanceIsUnknownWithoutTwoComparablePrints() {
        XCTAssertNil(PhotoSignal.distance(nil, [1]))
        XCTAssertNil(PhotoSignal.distance([1, 0], [1]))
        XCTAssertEqual(PhotoSignal.distance([3, 0], [0, 4]) ?? 0, 5, accuracy: 1e-9)
        XCTAssertFalse(PhotoSignal.isDuplicate(PhotoSignal(), PhotoSignal(), within: 1))
    }
}

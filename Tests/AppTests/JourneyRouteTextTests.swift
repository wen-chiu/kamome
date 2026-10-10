@testable import Kamome
import KamomeTrackingEngine
import XCTest

/// **The route line's glyphs belong to the travel they stand between**
/// (#265). The glyph between two shown names was `legModes[i − 1]`: one entry
/// per segment, indexed by the names after repeats had been folded and
/// coordinate names dropped, so the two lists drifted apart.
final class JourneyRouteTextTests: XCTestCase {
    private typealias Stop = JourneyRouteText.Stop
    private let car = TransportGlyph.symbol(for: .drive)
    private let walk = TransportGlyph.symbol(for: .walk)

    private func leg(_ startedAt: Double, _ mode: TransportMode, crossing: Bool = false) -> StoryLegFolding.Piece {
        StoryLegFolding.Piece(startedAt: startedAt, mode: mode, provenance: .inferred, isCrossing: crossing)
    }

    /// The issue's case: A, A, B, walking around A and then driving to B.
    /// Folded to "A, B", the glyph is the drive, not the walk.
    func testTheGlyphIntoAPlaceIsTheTravelFromTheLastStopOfTheNameBefore() {
        let steps = JourneyRouteText.steps(
            stops: [
                Stop(name: "A", arrivedAt: 0, departedAt: 100),
                Stop(name: "A", arrivedAt: 200, departedAt: 300),
                Stop(name: "B", arrivedAt: 1_000, departedAt: 1_100)
            ],
            legs: [leg(100, .walk), leg(300, .drive)]
        )
        XCTAssertEqual(steps, [.init(name: "A", glyph: nil), .init(name: "B", glyph: car)])
    }

    /// Routing splits one gap into several segments: the glyph is the gap's
    /// first mode, and the next gap still gets its own.
    func testSeveralSegmentsInOneGapAreOneGlyph() {
        let steps = JourneyRouteText.steps(
            stops: [
                Stop(name: "A", arrivedAt: 0, departedAt: 100),
                Stop(name: "B", arrivedAt: 1_000, departedAt: 1_100),
                Stop(name: "C", arrivedAt: 2_000, departedAt: nil)
            ],
            legs: [leg(100, .drive), leg(400, .drive), leg(700, .drive), leg(1_100, .walk)]
        )
        XCTAssertEqual(steps.map(\.glyph), [nil, car, walk], "used to read the second segment, a drive, for C")
    }

    /// A stop with no real name is skipped, and the travel through it still
    /// counts: a crossing on either side of it is the plane.
    func testAnUnnamedStopIsSkippedAndACrossingThroughItIsThePlane() {
        let steps = JourneyRouteText.steps(
            stops: [
                Stop(name: "A", arrivedAt: 0, departedAt: 100),
                Stop(name: nil, arrivedAt: 500, departedAt: 600),
                Stop(name: "B", arrivedAt: 5_000, departedAt: nil)
            ],
            legs: [leg(100, .drive), leg(600, .drive, crossing: true)]
        )
        XCTAssertEqual(steps, [.init(name: "A", glyph: nil), .init(name: "B", glyph: TransportGlyph.crossing)])
    }

    /// No legs at all between two names (an unrouted trip): an honest arrow,
    /// never a guessed car.
    func testAGapWithNoLegIsTheArrow() {
        let steps = JourneyRouteText.steps(
            stops: [Stop(name: "A", arrivedAt: 0, departedAt: 100), Stop(name: "B", arrivedAt: 900, departedAt: nil)],
            legs: []
        )
        XCTAssertEqual(steps.last?.glyph, TransportGlyph.symbol(for: .unknown))
    }
}

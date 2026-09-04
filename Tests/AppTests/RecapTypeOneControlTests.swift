@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeRouteMatching
import XCTest

/// **The type-1 control for the 2026-09-02/09-04 type-2 work.**
///
/// Its own file, because *"nothing in this round reaches a local film"* is a
/// different claim from the ones `RecapJourneyCardTests` makes, and because a
/// control that lived inside the suite under test would share its helpers — and
/// therefore its bugs. Everything here is built independently.
///
/// The brief's rule: `miyakojima` **must come out identical, said with a
/// measurement rather than an argument**. The measured half is in
/// `Docs/handoff-type2-opening-retime.md` (timeline report and continuity line,
/// both line-for-line against `main`); this is the structural half, which holds
/// after the numbers stop being re-measured by hand.
final class RecapTypeOneControlTests: XCTestCase {
    private static let control = "miyakojima"

    /// The same offline build the crossing suite uses, repeated rather than
    /// shared: a control that reached through the suite under test for its own
    /// setup would stop being independent evidence.
    private struct Film {
        let line: LinearTimeline
        let trip: RecapTrip
        let config: TrackingConfig.Export
    }

    private func film(_ fixture: String) async throws -> Film {
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        return Film(
            line: try XCTUnwrap(LinearTimeline(
                trip: trip, config: config, establishing: nil, locale: Locale(identifier: "en_US")
            )),
            trip: trip, config: config
        )
    }

    /// **The type-1 control, measured** (`Docs/handoff-type2-opening-retime.md`).
    ///
    /// Not "type-1 is unaffected because the code is gated" — that is an argument.
    /// This asserts the three things the retime could have leaked into a local
    /// film: a boarding pass, a hidden leg, and a changed odometer.
    func testTheTypeOneControlDrawsNoCardHidesNoLegAndCountsEveryKilometre() async throws {
        let made = try await film(Self.control)
        let (line, trip, config) = (made.line, made.trip, made.config)
        XCTAssertFalse(line.opensOnTheFlight, "the control must not be a type-2 film")
        XCTAssertTrue(trip.legs.allSatisfy { !$0.isCrossing }, "the control has no crossing")
        for frame in 0..<line.frameCount where line.journeyCardContent(
            atTime: Double(frame) / Double(config.fps)
        ) != nil {
            XCTFail("a local film drew a boarding pass at frame \(frame)")
        }
        // And no flight marks: the two additions of 2026-09-04 are gated on
        // `opensOnTheFlight`, and this is the measurement that says so.
        for frame in stride(from: 0, to: line.frameCount, by: config.fps / 2) {
            for overlay in line.overlayContents(atTime: Double(frame) / Double(config.fps)) {
                if case .flightEnds = overlay {
                    XCTFail("a local film drew a flight-end mark at frame \(frame)")
                }
            }
        }

        // Every leg is drawn for the whole film, and the odometer is the whole
        // route — with no crossing, local distance and route distance are the
        // same number at every instant, which is what "unchanged" means here.
        for frame in stride(from: 0, to: line.frameCount, by: config.fps) {
            let timeS = Double(frame) / Double(config.fps)
            XCTAssertEqual(
                line.path.traveledLocalDistanceM(atTime: timeS),
                line.path.traveledDistanceM(atTime: timeS),
                accuracy: 0.001,
                "the control's odometer must be untouched at \(timeS)s"
            )
        }
    }
}

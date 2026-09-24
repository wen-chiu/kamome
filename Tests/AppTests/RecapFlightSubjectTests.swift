@testable import Kamome
@testable import KamomeExportEngine
import XCTest

/// **Which subject a flight film draws around the flight** (ADR 2026-09-24 §5).
///
/// Split from `RecapJourneyCardTests` for the file-length budget; it reuses that
/// file's `TypeTwoFilm` fixture builder, so the three flight films here are the
/// same films the card tests read.
final class RecapFlightSubjectTests: XCTestCase {
    /// **The car never appears before the plane, nor as the plane lands**
    /// (Chiu 2026-09-24: 「開頭要出現飛機之前他還是會不小心跑出一個車子」).
    ///
    /// The departure airport's pull-away ramp faded the subject in as the
    /// trip's vehicle for `subject_park_s` just before the flight, and the
    /// landing stop's park-in drew it again. Every visible frame from the start
    /// of the film to the middle of the first stop after landing is the crossing
    /// role — on all three flight fixtures, because the ramp is a property of the
    /// stops around the flight, not of one trip.
    func testNoCarIsDrawnFromTheOpeningUntilTheFirstStopAfterLanding() async throws {
        for fixture in [
            UnroutableSeaProvider.crossingFixture, UnroutableSeaProvider.longHaulFixture,
            UnroutableSeaProvider.roundTripFixture
        ] {
            let made = try await TypeTwoFilm.make(fixture)
            let (line, config) = (made.line, made.config)
            XCTAssertTrue(line.opensOnTheFlight, "\(fixture) must open on the flight")
            let beat = try XCTUnwrap(line.path.crossingBeatWindowsS.first)
            let landing = try XCTUnwrap(line.holds.first { $0.startS >= beat.upperBound - 1e-9 })
            let untilS = (landing.startS + landing.endS) / 2
            var visible = 0
            for frame in 0..<Int(untilS * Double(config.fps)) {
                let timeS = Double(frame) / Double(config.fps)
                let subject = line.subjectState(atTime: timeS)
                guard subject.isVisible else { continue }
                visible += 1
                XCTAssertEqual(subject.role, .crossing, "\(fixture): the car is drawn at \(timeS)s, around the flight")
            }
            XCTAssertGreaterThan(visible, 0, "\(fixture): nothing was visible to check")
            // …and once the stop is over, the trip's own vehicle drives on.
            XCTAssertEqual(line.subjectState(atTime: landing.endS + 0.5).role, .vehicle, fixture)
        }
    }
}

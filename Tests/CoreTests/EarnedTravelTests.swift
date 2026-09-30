import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **Travel lasts as long as its windows need** (ADR file 2026-09-28,
/// `LinearTimeline.earningTravel`), on the shipped tunables.
///
/// Chiu, on his New Zealand film: the van crossed empty map for tens of seconds,
/// and when it was sped up the film was no shorter. Travel had a fixed share of
/// the body whatever the camera showed in it; Iceland's dump crossed 5.7 windows
/// in 80 s. These pin that the road gives the time back, and only the road.
final class EarnedTravelTests: XCTestCase {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")

    private func shipped() throws -> TrackingConfig.Export {
        try TrackingConfigLoader.load(contentsOf: Self.configURL).export
    }

    /// A 200 km drive east with a stop at each end and one halfway.
    private let route = (0...100).map { CameraPath.Point(lat: 24.80, lon: 121.0 + Double($0) * 0.02) }
    private var stops: [CameraPath.Point] { [route[0], route[50], route[100]] }
    /// Photo-rich stops, so the shortened film stays above `total_duration_min_s`.
    private let holdsS = [30.0, 30.0, 30.0]

    private func film(
        totalS: Double, config: TrackingConfig.Export, framing: CameraPath.Framing? = nil
    ) -> CameraPath? {
        CameraPath(
            route: route, stops: stops, config: config, stopHoldsS: holdsS, totalDurationS: totalS,
            establishing: nil, openingS: 0, journeyEndsBeforeS: 0, crossingVertexRanges: [],
            openingFlightFrame: nil, stopPlaces: [], framing: framing
        )
    }

    private func earned(totalS: Double, config: TrackingConfig.Export) throws -> (CameraPath, CameraPath) {
        let first = try XCTUnwrap(film(totalS: totalS, config: config))
        let plan = RecapDurationPlan(totalS: totalS, openingS: 0, stopDwellS: holdsS)
        let path = LinearTimeline.earningTravel(first, plan: plan, stopHoldsS: holdsS, config: config) {
            self.film(totalS: $0, config: $1, framing: $2)
        }
        return (first, path)
    }

    /// A film whose road is slower than `windows_per_s` gets shorter by exactly
    /// the road's excess: every stop keeps its seconds, the framing is the same,
    /// and the vehicle now crosses its windows at the configured rate.
    func testSlowTravelGivesItsTimeBackAndOnlyItsTime() throws {
        let config = try shipped()
        XCTAssertTrue(config.travelPacing.isEnabled)
        let (first, path) = try earned(totalS: 150, config: config)
        let before = LinearTimeline.travelWindows(of: first)
        XCTAssertLessThan(before.windows / before.seconds, config.travelPacing.windowsPerS,
                          "precondition: this film's road is slower than the rate")

        XCTAssertLessThan(path.durationS, first.durationS - 10)
        XCTAssertGreaterThan(path.durationS, config.totalDurationMinS, "precondition: the film minimum does not bind")
        let after = LinearTimeline.travelWindows(of: path)
        XCTAssertEqual(after.windows / after.seconds, config.travelPacing.windowsPerS, accuracy: 0.02)
        XCTAssertEqual(path.areaSpansM, first.areaSpansM, "the rebuild re-framed the film")
        XCTAssertEqual(path.holds.count, first.holds.count)
        let frameS = 1.0 / Double(config.fps)
        for (now, then) in zip(path.holds, first.holds) {
            XCTAssertEqual(now.endS - now.startS, then.endS - then.startS, accuracy: frameS,
                           "stop \(now.stopIndex) lost photo time to the shorter film")
        }
    }

    /// A film whose road is already at least as fast is left exactly as built:
    /// earned travel only ever shortens. (A one-area drive is never faster than
    /// the pan floor, so the rate is set below it here.)
    func testFastTravelIsLeftAlone() throws {
        let json = try String(contentsOf: Self.configURL, encoding: .utf8)
        let slowRate = json.replacingOccurrences(
            of: #""windows_per_s":\s*[0-9.]+"#, with: #""windows_per_s": 0.01"#, options: .regularExpression
        )
        XCTAssertNotEqual(slowRate, json, "the key moved")
        let config = try TrackingConfigLoader.load(from: Data(slowRate.utf8)).export
        let (first, path) = try earned(totalS: 150, config: config)
        let travel = LinearTimeline.travelWindows(of: first)
        XCTAssertGreaterThanOrEqual(travel.windows / travel.seconds, config.travelPacing.windowsPerS,
                                    "precondition: this film's road is already fast")
        XCTAssertEqual(path.durationS, first.durationS)
    }

    /// Every derived copy carries the rate. A copy that dropped it would fall
    /// back to `.off` silently and give the road its fixed share again.
    func testEveryCopyOfTheConfigKeepsTheTravelPacing() throws {
        let config = try shipped()
        XCTAssertFalse(TravelPacingConfig.off.isEnabled)
        let copies = [
            config.withFollowHeadingUp(true), config.withAllocationZeroShare(0.5),
            config.withRecapMode(config.recapMode), config.withTotalDuration(min: 60, max: 90),
            config.withCrossingBeatS(4), config.withKeyframeIntervalFrames(15),
            config.withSnapshotStations(maxMagnification: 1.1, padding: 1.03),
            config.withMaxHoldFraction(0.9)
        ]
        for copy in copies {
            XCTAssertEqual(copy.travelPacing, config.travelPacing)
            XCTAssertEqual(copy.endRouteHoldS, config.endRouteHoldS)
        }
        XCTAssertEqual(config.withMaxHoldFraction(0.9).maxHoldFraction, 0.9)
    }
}

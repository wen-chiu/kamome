@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// **The camera changes scale only inside a beat that exists to change it**
/// (ADR 2026-09-24), scanned on every fixture the continuity gate scans.
///
/// Since the body is framed area by area (`CameraPathAreas`), "the body never
/// zooms" is no longer the rule. What replaced it is narrower and just as
/// checkable: outside the opening, the end reveal, a crossing arc and a reframe
/// beat, the span of consecutive frames is identical. A zoom anywhere else is a
/// camera that re-frames mid-motion — the 2026-08-02 act camera — and fails here.
///
/// The continuity gate (`RecapCameraContinuityTests`) still scans the same films
/// for ground lost between frames; this adds the one property it cannot see,
/// because a slow enough zoom loses no ground and is still wrong.
final class RecapCameraAreaTests: XCTestCase {
    private static let fixtures = [
        "margaret-river", "miyakojima", "iceland", "finland", "new-zealand", "nz-real",
        UnroutableSeaProvider.crossingFixture, UnroutableSeaProvider.longHaulFixture,
        UnroutableSeaProvider.roundTripFixture
    ]

    func testTheSpanChangesOnlyInsideABeatThatExistsToChangeIt() async throws {
        for fixture in Self.fixtures {
            let (trip, config) = try await RecapDemoFilmTests.importedRecap(
                named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
            )
            let line = try XCTUnwrap(LinearTimeline(trip: trip, config: config, establishing: nil))
            let path = line.path
            let beats = (path.arcs + path.reframeArcs).map { $0.startS...$0.endS }
            let step = 1.0 / Double(config.fps)
            let revealS = line.durationS - config.endCardS - config.endRevealS
            func inABeat(_ time: Double) -> Bool { beats.contains { $0.contains(time) } }

            var moved = 0
            var time = line.openingS + step
            while time < revealS {
                if !inABeat(time), !inABeat(time - step),
                   abs(line.cameraFrame(atTime: time).spanM - line.cameraFrame(atTime: time - step).spanM) > 1e-6 {
                    moved += 1
                    if moved <= 3 { XCTFail("\(fixture): the span changed at t=\(time) outside every beat") }
                }
                time += step
            }
            print(String(
                format: "KAMOME_AREAS %-22@ %2d areas · spans %@ km · %d reframes · %.1fs",
                fixture as NSString, path.areaSpansM.count,
                path.areaSpansM.map { String(format: "%.1f", $0 / 1000) }.joined(separator: " / ") as NSString,
                path.reframeArcs.count, line.durationS
            ))
        }
    }

    /// **The film lands on the town, not on the whole destination** — Chiu's
    /// complaint, as a number. The round-trip fixture's first stops after the
    /// flight sit in one town; before ADR 2026-09-24 the arc landed on 0.60 × the
    /// destination's extent (19.5 km, measured). It now lands on the first area.
    func testATypeTwoFilmLandsOnItsFirstAreaNotTheWholeDestination() async throws {
        let fixture = UnroutableSeaProvider.roundTripFixture
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        let line = try XCTUnwrap(LinearTimeline(trip: trip, config: config, establishing: nil))
        XCTAssertTrue(line.opensOnTheFlight)
        let flight = try XCTUnwrap(line.path.arcs.first)
        let landed = line.cameraFrame(atTime: flight.endS + 0.5).spanM

        let destination = RecapTypeTwoFilm.trimmedToTheDestination(trip, config: config).legs
            .dropFirst().flatMap(\.coordinates).map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let oneSpan = CameraPath.fittingSpanM(bounds: CameraPath.bounds(of: destination), config: config)
            * config.wideSpanPadding / config.targetZoomRatio
        print(String(
            format: "KAMOME_LANDING %@ lands on %.1f km · one-span rule %.1f km", fixture, landed / 1000, oneSpan / 1000
        ))
        XCTAssertEqual(landed, line.path.areaSpansM[0], accuracy: 1)
        XCTAssertLessThan(landed, oneSpan / config.cameraAreaSplitRatio)
    }
}

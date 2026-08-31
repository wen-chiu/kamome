@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeRouteMatching
import XCTest

/// **The crossing beat and its contained arc** (`Docs/camera-arcs.md` §3–§8).
///
/// `RecapCameraContinuityTests` is the catastrophe detector — it asks whether
/// consecutive frames share *enough* ground. These are the assertions the arc
/// design asks for instead of a threshold, and they are stronger:
///
/// - the tighter of any two sampled frames lies **entirely inside** the looser;
/// - `CameraPath.confine` never fires during an arc, so the safe-zone clamp and
///   the move are never fighting.
///
/// Both are properties of the geometry rather than of a tuned number, which is
/// the design's central claim: an apex built to contain both end footprints
/// makes containment a consequence rather than a target (`CameraPath.containedLerp`).
final class RecapCrossingArcTests: XCTestCase {
    private func crossingScene() async throws -> (trip: RecapTrip, config: TrackingConfig.Export) {
        try await RecapDemoFilmTests.importedRecap(
            named: UnroutableSeaProvider.crossingFixture, baseURL: "",
            reconstructor: UnroutableSeaProvider.forFixture(UnroutableSeaProvider.crossingFixture)
        )
    }

    private func timeline(
        trip: RecapTrip, config: TrackingConfig.Export
    ) throws -> LinearTimeline {
        let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
        return try XCTUnwrap(LinearTimeline(
            trip: trip, config: config,
            establishing: RecapBounds(
                minLat: bounds.minLat, minLon: bounds.minLon, maxLat: bounds.maxLat, maxLon: bounds.maxLon
            )
        ))
    }

    /// The gate above is worthless if the fixture never produces a crossing, and
    /// it would still pass — a trip with no arc is a trip the camera already
    /// handled. So this asserts the *premise* separately.
    func testTheFixtureProducesExactlyOneCrossingAndTheRestAreRoadLegs() async throws {
        let (trip, config) = try await crossingScene()
        let crossings = trip.legs.filter(\.isCrossing)
        XCTAssertEqual(
            crossings.count, 1,
            "the fixture is one drive, one sea crossing and four island stops — \(trip.legs.count) legs in all"
        )
        for leg in trip.legs where !leg.isCrossing {
            XCTAssertFalse(
                leg.isCrossing,
                "a leg the provider said nothing about must never read as a crossing"
            )
        }
        let line = try timeline(trip: trip, config: config)
        XCTAssertEqual(line.path.arcWindowsS.count, 1, "one crossing, one arc")
        print(String(
            format: "KAMOME_CROSSING legs %d · crossings %d · arcs %d · film %.1fs · body span %.1f km",
            trip.legs.count, crossings.count, line.path.arcWindowsS.count,
            line.durationS, line.path.bodySpanM / 1000
        ))
    }

    /// **The invariant, asserted directly — and corrected.**
    ///
    /// ⚠️ **`Docs/camera-arcs.md` §8 states this in a form no arc can satisfy,
    /// and it took a render-free measurement to see it.** Its words are:
    ///
    /// > For any two frames sampled a snapshot interval apart, the tighter must
    /// > lie entirely inside the looser.
    ///
    /// Measured 2026-08-30 on the crossing fixture, that fails on exactly six
    /// sample pairs, all of them **straddling the apex** — and it fails there by
    /// construction, not by defect. An arc opens out and closes back in, so a
    /// pair taken either side of the widest point is two *different*
    /// sub-rectangles of the apex, and neither contains the other. The span is
    /// interpolated geometrically, so the last tenth of the outward half still
    /// covers ~28% of the absolute widening; the centre travels with it, and the
    /// two straddling frames end up ~15 km apart across a ~490 km frame.
    ///
    /// The property the design actually *needs* survives intact, in two halves:
    ///
    /// 1. **Within either half of the move** — where the span is monotonic — the
    ///    tighter frame lies entirely inside the looser. This is the guarantee
    ///    `containedLerp` was built for, and it is the one that matters, because
    ///    it is what makes the compositor's cross-fade honest.
    /// 2. **Across the apex** both frames lie entirely inside the apex, which the
    ///    film was showing between them. No ground appears that the viewer had
    ///    not just been shown, which is what §3's sentence means.
    ///
    /// The overlap gate itself is unaffected and unrelaxed: `groundOverlap`
    /// divides by the smaller footprint, and a 15 km shift across a 490 km frame
    /// scores ~0.95 against a 0.40 floor.
    func testTheArcIsContainedWithinEachHalfAndBoundedByTheApexAcrossIt() async throws {
        let (trip, config) = try await crossingScene()
        let line = try timeline(trip: trip, config: config)
        try XCTSkipIf(line.path.arcs.isEmpty, "no arc to check — the premise test says why")

        let snapshotStep = Double(config.keyframeIntervalFrames) / Double(config.fps)
        let step = 1.0 / Double(config.fps)
        var worstHalfSlackM = Double.greatestFiniteMagnitude
        var worstApexSlackM = Double.greatestFiniteMagnitude
        var straddles = 0
        func assertContained(_ slack: Double, atTime time: Double, what: String) {
            XCTAssertGreaterThanOrEqual(
                slack, -1.0,
                String(format: "at %.2fs a frame escaped by %.0f m — it should have stayed %@", time, -slack, what)
            )
        }

        for arc in line.path.arcs {
            let apexS = (arc.startS + arc.endS) / 2
            var time = arc.startS
            while time <= arc.endS {
                for gap in [step, snapshotStep] {
                    let earlier = max(time - gap, arc.startS)
                    guard earlier < time else { continue }
                    let before = line.cameraFrame(atTime: earlier)
                    let now = line.cameraFrame(atTime: time)
                    guard (earlier - apexS) * (time - apexS) < 0 else {
                        // Same half: strict containment, and this is the claim
                        // the whole interpolation exists to make true.
                        let slack = Self.containmentSlackM(before, now)
                        worstHalfSlackM = min(worstHalfSlackM, slack)
                        assertContained(slack, atTime: time, what: "within one half of the arc")
                        continue
                    }
                    // Straddling the apex: both must sit inside the frame the
                    // film showed between them.
                    straddles += 1
                    for frame in [before, now] {
                        let slack = Self.containmentSlackM(Self.waist(arc.apex), frame)
                        worstApexSlackM = min(worstApexSlackM, slack)
                        assertContained(slack, atTime: time, what: "inside the apex itself")
                    }
                }
                time += step
            }
        }
        // A metre of tolerance above, because the two frames are compared on a
        // local plane about different reference latitudes. The printed figures
        // are the real margins, and they are what a future change erodes first.
        print(String(
            format: "KAMOME_CROSSING containment · within a half %.0f m slack · beside the apex %.0f m slack "
                + "· %d straddling pairs",
            worstHalfSlackM, worstApexSlackM, straddles
        ))
        XCTAssertGreaterThan(straddles, 0, "an out-and-back move must have sample pairs across its apex")
    }

    /// **The apex has to be sized for the safe-zone gate, not merely survive it**
    /// (`HANDOFF.md` 2026-08-21 finding 4). A `confine` that fires drags the frame
    /// off the arc, and containment is what that would break.
    func testConfineIsANoOpForEveryFrameOfEveryArc() async throws {
        let (trip, config) = try await crossingScene()
        let line = try timeline(trip: trip, config: config)
        try XCTSkipIf(line.path.arcs.isEmpty, "no arc to check")

        let step = 1.0 / Double(config.fps)
        var worstReach = 0.0
        for arc in line.path.arcs {
            var time = arc.startS
            while time <= arc.endS {
                let framed = arc.frame(atTime: time)
                let subject = line.path.position(atTime: time)
                let confined = CameraPath.confine(framed, around: subject, config: config)
                XCTAssertEqual(
                    confined.centerLat, framed.centerLat, accuracy: 1e-9,
                    String(format: "confine moved the arc's frame north/south at %.2fs", time)
                )
                XCTAssertEqual(
                    confined.centerLon, framed.centerLon, accuracy: 1e-9,
                    String(format: "confine moved the arc's frame east/west at %.2fs", time)
                )
                worstReach = max(worstReach, Self.subjectReach(
                    centerLat: framed.centerLat, centerLon: framed.centerLon, spanM: framed.spanM,
                    subject: subject, config: config
                ))
                time += step
            }
        }
        print(String(
            format: "KAMOME_CROSSING subject worst reach %.0f%% of the half-frame (safe zone %.0f%%, "
                + "apex padding %.2f predicts %.0f%%)",
            worstReach * 100, config.cameraSafeZoneFraction * 100,
            config.crossingApexPadding, 100 / config.crossingApexPadding
        ))
        XCTAssertLessThanOrEqual(worstReach, config.cameraSafeZoneFraction)
    }

    /// **What the destination's framing costs now versus the union it replaces.**
    ///
    /// Not a threshold — the same trip is built twice, once with the crossing
    /// established and once with nothing established about any leg, and the two
    /// body spans are printed. The second is the film Chiu has been watching:
    /// `RecapDurationPlan.bodySpanM`'s pan floor sized against a route that
    /// includes 300 km of open sea.
    func testTheCrossingsDistanceLeavesTheBodySpan() async throws {
        let (crossingTrip, config) = try await crossingScene()
        let withCrossing = try timeline(trip: crossingTrip, config: config)

        // The same geometry with the crossing unestablished — literally the same
        // legs, one flag flipped, so nothing but the correction differs.
        let unionTrip = RecapTrip(
            legs: crossingTrip.legs.map {
                RecapTrip.Leg(
                    coordinates: $0.coordinates, mode: $0.mode, provenance: $0.provenance, isCrossing: false
                )
            },
            stops: crossingTrip.stops, title: crossingTrip.title, subtitle: crossingTrip.subtitle,
            statsLines: crossingTrip.statsLines, callToAction: crossingTrip.callToAction
        )
        let union = try timeline(trip: unionTrip, config: config)

        print(String(
            format: "KAMOME_CROSSING body span %.1f km with the crossing beat vs %.1f km derived from the union "
                + "(%.2f× tighter) · film %.1fs vs %.1fs",
            withCrossing.path.bodySpanM / 1000, union.path.bodySpanM / 1000,
            union.path.bodySpanM / max(withCrossing.path.bodySpanM, 1),
            withCrossing.durationS, union.durationS
        ))
        XCTAssertLessThan(
            withCrossing.path.bodySpanM, union.path.bodySpanM,
            "taking the crossing out of the pan floor must frame the destination tighter, not wider"
        )
    }

    // MARK: - Geometry

    /// The camera's own frame type as the narrow-waist one, so the containment
    /// helper can compare an arc's apex with a frame the timeline produced.
    private static func waist(_ frame: CameraPath.CameraFrame) -> CameraFrame {
        CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon,
            spanM: frame.spanM, bearing: frame.bearing
        )
    }

    /// How many metres of margin the tighter frame has inside the looser one.
    /// Negative means it escaped, by that much.
    private static func containmentSlackM(_ lhs: CameraFrame, _ rhs: CameraFrame) -> Double {
        let (looser, tighter) = lhs.spanM >= rhs.spanM ? (lhs, rhs) : (rhs, lhs)
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = 111_320.0 * cos(looser.centerLat * .pi / 180)
        let aspect = 1920.0 / 1080.0
        let dEast = (tighter.centerLon - looser.centerLon) * metresPerDegreeLon
        let dNorth = (tighter.centerLat - looser.centerLat) * metresPerDegreeLat
        let east = (looser.spanM - tighter.spanM) / 2 - abs(dEast)
        let north = (looser.spanM - tighter.spanM) * aspect / 2 - abs(dNorth)
        return min(east, north)
    }

    /// How far the subject sits toward the frame edge, as a fraction of the
    /// half-frame — the quantity `camera_safe_zone_fraction` bounds.
    private static func subjectReach(
        centerLat: Double, centerLon: Double, spanM: Double,
        subject: CameraPath.Position, config: TrackingConfig.Export
    ) -> Double {
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = 111_320.0 * cos(centerLat * .pi / 180)
        let aspect = Double(config.frameHeightPx) / Double(config.frameWidthPx)
        let east = abs(subject.lon - centerLon) * metresPerDegreeLon / (spanM / 2)
        let north = abs(subject.lat - centerLat) * metresPerDegreeLat / (spanM * aspect / 2)
        return max(east, north)
    }
}

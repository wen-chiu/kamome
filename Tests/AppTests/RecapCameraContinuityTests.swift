@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeRouteMatching
import XCTest

/// **The camera continuity gate** (Chiu 2026-08-01).
///
/// > Two consecutive frames must always share meaningful geography. If frame N
/// > and frame N+1 have little or no overlapping geography, that is a bug, not
/// > cinematic editing.
///
/// The four symptoms of the 2026-08-01 NZ device film — a frozen opening, a
/// stutter on inferred legs, a strobe from 0:50, and a wrong-feeling end reveal
/// — were one design fault: `CameraPathActs` framed each act to its own bounds
/// and nothing reconciled that with the clock-driven timing, so camera motion
/// came from data shape rather than from spatial continuity. That fault was
/// invisible to every existing test, because a still frame is trivially correct
/// and a strobing one is only wrong *between* frames.
///
/// This measures the thing the eye actually judges: **how much of the previous
/// frame's ground is still on screen.** It is deliberately not a golden-frame
/// test — pixels can be perfect in every individual frame of an unwatchable film.
///
/// Runs entirely offline (no tiles, no routing, no rendering) so it can gate every
/// CI run: fixture JSON → clusterer → raw legs → timeline → scan. `base_url` is
/// forced empty, which leaves every leg unrouted — a straight line between photo
/// positions. That is the **worst case** for the camera and the exact shape the
/// shipped app produces today, since `matching.base_url` ships empty.
final class RecapCameraContinuityTests: XCTestCase {
    /// Committed photo-import fixtures spanning the scales the camera has to
    /// survive: a day trip, an island, two countries, and a multi-day road trip.
    private static let fixtures = [
        "margaret-river", "miyakojima", "iceland", "finland", "new-zealand", "nz-real", crossingFixture
    ]

    /// The fixture with a leg that has no road under it. Named in one place —
    /// see `UnroutableSeaProvider`, which also holds the geography and why it is
    /// a meridian rather than a distance.
    static let crossingFixture = UnroutableSeaProvider.crossingFixture

    /// Fraction of the frame's ground that must still be on screen one frame
    /// later. Generous on purpose — this is a catastrophe detector, not a
    /// smoothness metric. The dead-zone camera's own budget
    /// (`camera_pan_window_fraction_per_s`) is ~0.35 window-widths per *second*,
    /// which retains ~99% frame to frame, so passing this leaves ~3× headroom
    /// for inertia catch-up.
    private static let minFrameOverlap = 0.50

    /// The same measure across a snapshot interval. Lower, because these are the
    /// frames the compositor **cross-fades** between: two keyframes sharing no
    /// ground dissolve one place into an unrelated one, which is what the strobe
    /// actually looked like.
    private static let minSnapshotOverlap = 0.40

    /// A permitted cut (flight / ferry / data gap) may break continuity, but only
    /// briefly — this is the window either side of it that the scan forgives.
    private static let cutToleranceS = 0.10

    /// **Both camera configurations, because scanning one was scanning the wrong
    /// one** (2026-09-02).
    ///
    /// Until now every scan here passed a synthetic `establishing` extent, and
    /// the comment justifying that said it was "the same code path, not a stub".
    /// **It is not.** `establishing` decides whether the opening gets a region
    /// beat, `establishedSpanM` returns the prologue's *last* beat, and
    /// `bodySpanM` divides that — so a nil `establishing` yields a different
    /// prologue, a different established span and a different body span. It also
    /// switches the film off content-derived pacing onto `.fixed`.
    ///
    /// **The shipped app has passed nil since 2026-08-15** (`RecapModel`: the
    /// extent comes from an installed `.pmtiles` region, and no region is ever
    /// installed while MapLibre is parked). So the gate that exists to stop the
    /// camera strobing had never once measured the camera that ships.
    ///
    /// Both are scanned rather than swapping to nil alone: `region` is the
    /// configuration MapLibre would restore, and dropping it to test the shipped
    /// one would trade one blind spot for another.
    private static func configurations(
        synthetic: RecapBounds
    ) -> [(label: String, establishing: RecapBounds?)] {
        [("region", synthetic), ("shipped", nil)]
    }

    func testCameraNeverBreaksSpatialContinuity() async throws {
        // Landed green with the dead-zone camera on 2026-08-01: every fixture
        // retains ≥97% of its ground frame to frame, against a 50% floor. The
        // `XCTExpectFailure` this carried while acts still framed the camera is
        // gone — if this ever fails again, the camera regressed, not the gate.
        var report: [String] = []
        for fixture in Self.fixtures {
            report.append(contentsOf: try await scan(fixture: fixture))
        }
        print("KAMOME_CONTINUITY\n" + report.joined(separator: "\n"))
    }

    /// **The subject may never reach the edge of frame** (Chiu 2026-08-01).
    ///
    /// A hard constraint, not a preference. The vehicle is what the audience is
    /// watching; if it drifts into the outer margin they have to hunt for it, and
    /// if it leaves the frame the film has lost its own subject. It does not need
    /// to be centred — only never to be out there.
    ///
    /// This is separate from the continuity scan on purpose. Continuity is about
    /// the *world* staying coherent between frames; this is about the *subject*
    /// staying findable within one. A camera can be perfectly smooth and still
    /// leave the car behind, which is exactly what the dead-zone spring did on
    /// fast legs before the safe-zone clamp was added.
    func testSubjectNeverEntersTheOuterMargin() async throws {
        for fixture in Self.fixtures {
            let (trip, config) = try await RecapDemoFilmTests.importedRecap(
                named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
            )
            let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
            let synthetic = RecapBounds(
                minLat: bounds.minLat, minLon: bounds.minLon,
                maxLat: bounds.maxLat, maxLon: bounds.maxLon
            )
            // Both cameras, for the same reason the continuity scan runs both:
            // the shipped one passes nil and had never been measured here either.
            for (label, establishing) in Self.configurations(synthetic: synthetic) {
                try assertSubjectStaysFindable(
                    fixture: fixture, label: label, trip: trip, config: config, establishing: establishing
                )
            }
        }
    }

    /// One fixture, one camera configuration.
    private func assertSubjectStaysFindable(
        fixture: String, label: String, trip: RecapTrip,
        config: TrackingConfig.Export, establishing: RecapBounds?
    ) throws {
            let line = try XCTUnwrap(LinearTimeline(
                trip: trip, config: config, establishing: establishing
            ))
            // Only once the journey exists: through the opening the subject is
            // parked at the origin and deliberately not drawn at all.
            let step = 1.0 / Double(config.fps)
            var worst = 0.0
            var worstAt = 0.0
            var reaches: [Double] = []
            for frame in Int(line.journeyStartS / step)..<line.frameCount {
                let timeS = Double(frame) * step
                let camera = line.cameraFrame(atTime: timeS)
                let subject = line.subjectState(atTime: timeS)
                // Offset from frame centre, as a fraction of the half-frame.
                let east = Self.meters(camera.centerLat, camera.centerLon, camera.centerLat, subject.lon)
                let north = Self.meters(camera.centerLat, camera.centerLon, subject.lat, camera.centerLon)
                let fractionX = east / (camera.spanM / 2)
                let fractionY = north / (camera.spanM * 1920 / 1080 / 2)
                let reach = max(fractionX, fractionY)
                if reach > worst { worst = reach; worstAt = timeS }
                reaches.append(reach)
            }
            // The peak alone says little — it is usually one moment in the end
            // reveal. Where the subject *sits* is what a viewer experiences.
            let sorted = reaches.sorted()
            func percentile(_ fraction: Double) -> Double {
                sorted.isEmpty ? 0 : sorted[min(Int(Double(sorted.count - 1) * fraction), sorted.count - 1)]
            }
            print(String(
                // One decimal on `worst` deliberately: the shipped crossing camera
                // sits within a point of the limit, and a rounded integer cannot
                // tell "at the bar" from "over it".
                format: "KAMOME_SAFEZONE %-16@ %-7@ median %3.0f%% · p95 %3.0f%% · worst %5.1f%% at %5.1fs "
                    + "(limit %.0f%%)",
                fixture as NSString, label as NSString, percentile(0.5) * 100, percentile(0.95) * 100,
                worst * 100, worstAt, config.cameraSafeZoneFraction * 100))
            XCTAssertLessThanOrEqual(
                worst, config.cameraSafeZoneFraction + 0.02,
                String(
                    format: "%@ (%@): the subject reached %.0f%% of the way to the frame edge at %.1fs "
                        + "— the safe zone is %.0f%%",
                    fixture, label, worst * 100, worstAt, config.cameraSafeZoneFraction * 100
                )
            )
    }

    // MARK: - The scan

    private struct Violation {
        let timeS: Double
        let overlap: Double
        let movedM: Double
        let spanM: Double
        let kind: String
    }

    /// **The card beat must be a still frame, and the film proper starts after
    /// it** — the first frame the continuity scan may begin at.
    ///
    /// ⚠️ **This is not an exemption and must not become one.** An exemption
    /// forgives a violation inside a window. This asserts instead that there is
    /// no camera motion to be continuous *with* before the cut — the card beat is
    /// one framing, held — and then everything after it is scanned with nothing
    /// forgiven. If the card beat ever moved, this fails rather than skips, which
    /// is the whole difference.
    private func assertTheCardBeatIsStill(
        _ line: LinearTimeline, fixture: String, fps: Int
    ) throws -> Int {
        guard let cut = line.titleCutS else { return 1 }
        let step = 1.0 / Double(fps)
        let card = line.cameraFrame(atTime: 0)
        for frame in 0..<max(Int((cut * Double(fps)).rounded(.down)), 1) {
            XCTAssertEqual(
                Self.groundOverlap(card, line.cameraFrame(atTime: Double(frame) * step)), 1.0,
                accuracy: 1e-9,
                "\(fixture): the title card's beat moved at frame \(frame) — a cut is only honest "
                    + "out of a still frame, so this is a violation, not an exemption"
            )
        }
        return Int((cut * Double(fps)).rounded(.up)) + 1
    }

    /// Builds `fixture`'s real timeline and walks every frame of it — once per
    /// camera configuration, because they are different cameras. See
    /// `configurations(synthetic:)`.
    @discardableResult
    private func scan(fixture: String) async throws -> [String] {
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        // The synthetic extent stands in for an installed map region. Widening
        // the trip's own bounds is what the prologue does when a region is
        // available; `nil` beside it is what the app actually ships.
        let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
        let synthetic = RecapBounds(
            minLat: bounds.minLat, minLon: bounds.minLon, maxLat: bounds.maxLat, maxLon: bounds.maxLon
        )
        var lines: [String] = []
        for (label, establishing) in Self.configurations(synthetic: synthetic) {
            lines.append(try scanOne(
                fixture: fixture, label: label, trip: trip, config: config, establishing: establishing
            ))
        }
        return lines
    }

    /// One fixture, one camera configuration, every frame.
    private func scanOne(
        fixture: String, label: String, trip: RecapTrip,
        config: TrackingConfig.Export, establishing: RecapBounds?
    ) throws -> String {
        let line = try XCTUnwrap(LinearTimeline(trip: trip, config: config, establishing: establishing))

        let permitted = line.path.permittedCutTimesS
        let step = 1.0 / Double(config.fps)
        let snapshotStep = Double(config.keyframeIntervalFrames) / Double(config.fps)

        var violations: [Violation] = []
        var excusedCount = 0
        var worst = (overlap: 1.0, timeS: 0.0)

        // **The film proper begins at the title-card cut** (Chiu 2026-08-31).
        // Before it the camera is a *held* frame under a title card, which the
        // viewer reads as chrome; a cut out of chrome is a film convention and
        // costs no continuity. After it, every rule below applies to every frame
        // with nothing forgiven.
        //
        // ⚠️ **This is not an exemption and must not become one.** An exemption
        // would forgive a violation inside a window. This asserts instead that
        // there is no camera motion to be continuous *with* before the cut — the
        // card beat is one frame, held — and then scans everything after it. If
        // the card beat ever moved, the loop below would fail rather than skip,
        // which is the whole difference.
        let scanFrom = try assertTheCardBeatIsStill(line, fixture: fixture, fps: config.fps)
        for frame in scanFrom..<line.frameCount {
            let timeS = Double(frame) * step
            for (gap, floor, kind) in [
                (step, Self.minFrameOverlap, "frame"),
                (snapshotStep, Self.minSnapshotOverlap, "snapshot")
            ] {
                guard timeS - gap >= 0 else { continue }
                // Never compare across the cut itself: the pair would straddle a
                // discontinuity the film declares, and the frames after it are
                // already scanned against each other.
                if let cut = line.titleCutS, timeS - gap <= cut { continue }
                let now = line.cameraFrame(atTime: timeS)
                let before = line.cameraFrame(atTime: timeS - gap)
                let overlap = Self.groundOverlap(before, now)
                if kind == "frame", overlap < worst.overlap { worst = (overlap, timeS) }
                guard overlap < floor else { continue }
                // Forgiven only if a genuine discontinuity sits in this interval.
                let excused = permitted.contains {
                    $0 >= timeS - gap - Self.cutToleranceS && $0 <= timeS + Self.cutToleranceS
                }
                if excused {
                    // **Counted, not merely skipped** — the free evidence
                    // `HANDOFF.md` 2026-08-21 finding 3 asked for and nobody had
                    // collected. `permitted.count` says how many cuts are
                    // *available*; this says how many were actually spent, which
                    // is the number that decides whether the exemption can go to
                    // zero (`Docs/camera-arcs.md` §8).
                    excusedCount += 1
                    continue
                }
                violations.append(Violation(
                    timeS: timeS, overlap: overlap,
                    movedM: Self.meters(before.centerLat, before.centerLon, now.centerLat, now.centerLon),
                    spanM: now.spanM, kind: kind
                ))
            }
        }

        return Self.report(
            fixture: fixture, label: label, line: line, violations: violations,
            worst: worst, cuts: (permitted: permitted.count, excused: excusedCount)
        )
    }

    /// One line per fixture, plus a failure per violation. Split out of `scan`
    /// so the scan itself stays a walk over frames.
    private static func report(
        fixture: String, label: String, line: LinearTimeline, violations: [Violation],
        worst: (overlap: Double, timeS: Double), cuts: (permitted: Int, excused: Int)
    ) -> String {
        let summary = String(
            format: "  %-16@ %-7@ %5.1fs · span %6.1f km · worst frame overlap %3.0f%% at %5.1fs · "
                + "%d violations · %d permitted cuts · %d excused · %d arcs",
            fixture as NSString, label as NSString, line.durationS, line.path.bodySpanM / 1000,
            worst.overlap * 100, worst.timeS, violations.count, cuts.permitted, cuts.excused,
            line.path.arcWindowsS.count
        )
        for violation in violations.prefix(3) {
            XCTFail(String(
                format: "%@ (%@) · %@-to-%@ continuity broken at %.2fs: only %.0f%% of the frame's ground "
                    + "survives (camera moved %.0f m across a %.0f m window). "
                    + "No route discontinuity permits a cut here.",
                fixture, label, violation.kind, violation.kind, violation.timeS,
                violation.overlap * 100, violation.movedM, violation.spanM
            ))
        }
        return summary + (violations.isEmpty ? "  ✅" : "  ❌")
    }

    // MARK: - Geometry

    /// How much of the tighter frame's ground the looser one still contains:
    /// **area(intersection) / area(smaller footprint)**.
    ///
    /// Measured against the *smaller* footprint on purpose, because that makes a
    /// pure zoom score 1.0 — and it should. Zooming loses no geography; every
    /// place on the tighter screen is still on the wider one, which is exactly
    /// what "the viewer keeps their bearings" means. What breaks a viewer's map
    /// is the frame moving somewhere *else*, and that is what this catches.
    ///
    /// (An earlier draft divided by the zoom ratio, which scored the sanctioned
    /// opening zoom and closing reveal as continuity failures. That was the
    /// metric being wrong, not the camera: the product rule already forbids the
    /// body from zooming at all, and `testBodySpanNeverChangesWhileTravelling`
    /// is what enforces it.)
    ///
    /// Both axes count, and the frame is portrait, so a north-south jump is
    /// judged as harshly as an east-west one.
    private static func groundOverlap(_ lhs: CameraFrame, _ rhs: CameraFrame) -> Double {
        // Metres east/north of `lhs`'s centre — a local plane is exact enough for
        // two frames a thirtieth of a second apart.
        let dEast = meters(lhs.centerLat, lhs.centerLon, lhs.centerLat, rhs.centerLon)
            * ((rhs.centerLon >= lhs.centerLon) ? 1 : -1)
        let dNorth = meters(lhs.centerLat, lhs.centerLon, rhs.centerLat, lhs.centerLon)
            * ((rhs.centerLat >= lhs.centerLat) ? 1 : -1)
        let aspect = 1920.0 / 1080.0

        /// One frame's ground footprint, as a rectangle about a shared origin.
        struct Footprint {
            let minEast: Double, maxEast: Double, minNorth: Double, maxNorth: Double
            init(_ frame: CameraFrame, east: Double, north: Double, aspect: Double) {
                let halfW = frame.spanM / 2, halfH = frame.spanM * aspect / 2
                minEast = east - halfW; maxEast = east + halfW
                minNorth = north - halfH; maxNorth = north + halfH
            }
        }
        let here = Footprint(lhs, east: 0, north: 0, aspect: aspect)
        let next = Footprint(rhs, east: dEast, north: dNorth, aspect: aspect)

        let overlapW = max(min(here.maxEast, next.maxEast) - max(here.minEast, next.minEast), 0)
        let overlapH = max(min(here.maxNorth, next.maxNorth) - max(here.minNorth, next.minNorth), 0)
        let smallerArea = max(min(lhs.spanM, rhs.spanM) * min(lhs.spanM, rhs.spanM) * aspect, 1)
        return overlapW * overlapH / smallerArea
    }

    private static func meters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let haversine = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}

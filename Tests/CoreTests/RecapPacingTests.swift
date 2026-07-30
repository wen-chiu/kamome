import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// The cinematic pass (Chiu 2026-07-30): a film whose length follows its content,
/// and a one-time opening that establishes *where* before showing *what*.
///
/// These pin the two things a rendered still cannot show — how the budget is
/// allocated, and that the camera stops moving once the journey starts.
final class RecapPacingTests: XCTestCase {
    private func config(
        stopDwellMinS: Double = 6,
        stopDwellMaxS: Double = 25,
        totalMinS: Double = 60,
        totalMaxS: Double = 90
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 30, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.6,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: 1080, frameHeightPx: 1920,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 2.5,
            actSplitKm: 25, followHeadingUp: false,
            deckPhotoHoldS: 2.5, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 3.0, openingRegionalS: 3.5, openingRouteS: 0.4,
            countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalMinS, totalDurationMaxS: totalMaxS,
            keyframeIntervalFrames: 15, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5
        )
    }

    private var deck: RecapDeck {
        RecapDeck(photoHoldS: 2.5, zoomS: 0.5, labelLeadS: 0.6)
    }

    private func trip(photoCounts: [Int]) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -44.0 + Double($0) * 0.02, lon: 170.5) }
        let stops = photoCounts.enumerated().map { index, count in
            RecapTrip.Stop(
                coordinate: route[min((index + 1) * 8, route.count - 1)],
                name: "Stop \(index + 1)", dayLabel: "Day 1",
                photos: (0..<count).map { .asset("s\(index)-\($0)") },
                dwellS: deck.dwellS(photoCount: count)
            )
        }
        return RecapTrip(
            route: route, stops: stops, title: "Trip", subtitle: "",
            statsLines: [], callToAction: ""
        )
    }

    /// The region's extent — wider than the trip, which is what the country view
    /// frames.
    private let establishing = RecapBounds(minLat: -47.5, minLon: 166.0, maxLat: -34.0, maxLon: 179.2)

    // MARK: - Target duration

    /// The whole point of the change: a fixed 30 s gave a six-stop trip 2.5 s per
    /// stop. Duration now follows content, inside the window.
    func testDurationFollowsContentAndStaysInsideTheTargetWindow() {
        let export = config()
        for counts in [[3], [3, 3], [3, 4, 2], [3, 3, 3, 3], [3, 3, 3, 3, 3, 3], Array(repeating: 8, count: 8)] {
            let plan = RecapDurationPlan.plan(photoCounts: counts, config: export, deck: deck)
            XCTAssertGreaterThanOrEqual(plan.totalS, export.totalDurationMinS, "\(counts.count) stops")
            XCTAssertLessThanOrEqual(plan.totalS, export.totalDurationMaxS, "\(counts.count) stops")
        }
    }

    /// More content buys a longer film, up to the ceiling.
    func testMoreStopsBuyALongerFilmUntilTheCeiling() {
        let export = config()
        let two = RecapDurationPlan.plan(photoCounts: [3, 3], config: export, deck: deck)
        let four = RecapDurationPlan.plan(photoCounts: [3, 3, 3, 3], config: export, deck: deck)
        XCTAssertGreaterThan(four.totalS, two.totalS)
        XCTAssertLessThan(four.totalS, export.totalDurationMaxS, "four 3-photo stops do not need the cap")

        // A genuinely photo-heavy trip does reach it, and stops there.
        let heavy = RecapDurationPlan.plan(
            photoCounts: Array(repeating: 8, count: 6), config: export, deck: deck
        )
        XCTAssertEqual(heavy.totalS, export.totalDurationMaxS, accuracy: 0.01)
    }

    /// A route-only trip is not padded out with stops it does not have.
    func testRouteOnlyTripGetsTheFloorAndNoDwell() {
        let plan = RecapDurationPlan.plan(photoCounts: [], config: config(), deck: deck)
        XCTAssertEqual(plan.totalS, 60)
        XCTAssertTrue(plan.stopDwellS.isEmpty)
    }

    // MARK: - Stop dwell budgeting (deliberately uneven)

    /// Time is **not** shared evenly (Chiu 2026-07-30): a photo-rich stop earns
    /// substantially more than a sparse one, and that ordering survives the
    /// global scale that fits the film into the window.
    func testPhotoRichStopsGetSubstantiallyMoreDwellThanSparseOnes() throws {
        let plan = RecapDurationPlan.plan(photoCounts: [1, 8], config: config(), deck: deck)
        let sparse = try XCTUnwrap(plan.stopDwellS.first)
        let rich = try XCTUnwrap(plan.stopDwellS.last)
        XCTAssertGreaterThan(rich, sparse * 1.8, "8 photos must earn far more than 1: \(plan.stopDwellS)")
    }

    /// Scaling to fit preserves the *relative* weight each stop earned, rather
    /// than flattening everything toward the mean.
    func testFittingToTheWindowPreservesRelativeWeight() throws {
        let export = config()
        let counts = [1, 4, 8, 2, 6, 3]
        let plan = RecapDurationPlan.plan(photoCounts: counts, config: export, deck: deck)
        // Ordering by photo count must equal ordering by dwell.
        let byCount = counts.indices.sorted { counts[$0] < counts[$1] }
        let byDwell = plan.stopDwellS.indices.sorted { plan.stopDwellS[$0] < plan.stopDwellS[$1] }
        XCTAssertEqual(byCount, byDwell, "relative weight lost: \(plan.stopDwellS)")
    }

    func testDwellNeverLeavesThePerStopWindowBeforeScaling() {
        let export = config(stopDwellMinS: 6, stopDwellMaxS: 12)
        let plan = RecapDurationPlan.plan(photoCounts: [1, 20], config: export, deck: deck)
        // The 20-photo stop is clamped by the ceiling, not allowed to run away.
        XCTAssertLessThanOrEqual(plan.stopDwellS.max() ?? 0, export.stopDwellMaxS + 0.01)
    }

    // MARK: - The opening

    private func timeline(_ trip: RecapTrip, _ export: TrackingConfig.Export) throws -> LinearTimeline {
        try XCTUnwrap(LinearTimeline(trip: trip, config: export, establishing: establishing))
    }

    /// The country view comes first, and it is genuinely wider than the trip —
    /// that is what makes the place recognizable before the journey starts.
    func testOpeningFramesTheRegionWiderThanTheTrip() throws {
        let export = config()
        let line = try timeline(trip(photoCounts: [3, 3]), export)

        let opening = line.cameraFrame(atTime: 0)
        let settled = line.cameraFrame(atTime: line.openingS + 1)
        XCTAssertGreaterThan(opening.spanM, settled.spanM * 2, "the country view must be much wider than the route")
        XCTAssertEqual(opening.bearing, 0, "north-up throughout")
    }

    /// Country → regional → route, each eased over `zoom_transition_s`, and the
    /// whole opening is exactly the budgeted length.
    func testOpeningRunsCountryThenRegionalThenRouteOverTheBudgetedTime() throws {
        let export = config()
        let line = try timeline(trip(photoCounts: [3, 3]), export)
        XCTAssertEqual(
            line.openingS,
            export.openingCountryS + export.openingRegionalS + export.openingRouteS + 2 * export.zoomTransitionS,
            accuracy: 0.01
        )

        // Held through the country beat, then monotonically zooming in.
        let country = line.cameraFrame(atTime: 0).spanM
        XCTAssertEqual(line.cameraFrame(atTime: export.openingCountryS - 0.1).spanM, country, accuracy: 1)

        var previous = country
        for time in stride(from: export.openingCountryS, through: line.openingS, by: 0.25) {
            let span = line.cameraFrame(atTime: time).spanM
            XCTAssertLessThanOrEqual(span, previous + 1, "the opening must only ever zoom in (t=\(time))")
            previous = span
        }
    }

    /// The subject waits at the route's start while the camera establishes, so the
    /// trail has not begun and the opening has the frame to itself.
    func testSubjectHoldsAtTheRouteStartThroughTheOpening() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 3])
        let line = try timeline(sample, export)
        let start = try XCTUnwrap(sample.route.first)

        for time in stride(from: 0.0, to: line.openingS - 0.1, by: 0.5) {
            let subject = line.subjectState(atTime: time)
            XCTAssertEqual(subject.lat, start.lat, accuracy: 1e-6, "vehicle moved during the opening (t=\(time))")
        }
        // And it does move once the journey starts.
        let moved = line.subjectState(atTime: line.openingS + (line.durationS - line.openingS) * 0.5)
        XCTAssertGreaterThan(abs(moved.lat - start.lat), 1e-4)
    }

    /// **The body camera never moves again** (Chiu 2026-07-30). The opening is the
    /// only camera movement in the film: no per-stop approach, no drift. This is
    /// the guard on the static-camera decision surviving the cinematic pass.
    func testCameraIsCompletelyStillAfterTheOpening() throws {
        let export = config()
        let line = try timeline(trip(photoCounts: [3, 4, 2]), export)

        let settled = line.cameraFrame(atTime: line.openingS + 0.5)
        var time = line.openingS + 0.5
        while time <= line.durationS {
            let frame = line.cameraFrame(atTime: time)
            XCTAssertEqual(frame.spanM, settled.spanM, accuracy: 0.5, "camera zoomed at t=\(time)")
            XCTAssertEqual(frame.centerLat, settled.centerLat, accuracy: 1e-6, "camera panned at t=\(time)")
            XCTAssertEqual(frame.centerLon, settled.centerLon, accuracy: 1e-6, "camera panned at t=\(time)")
            XCTAssertEqual(frame.bearing, 0, "camera rotated at t=\(time)")
            time += 0.25
        }
    }

    /// Without an establishing extent nothing changes: no prologue, the old fixed
    /// duration. That is what keeps every existing trip and golden frame intact.
    func testNoEstablishingExtentMeansNoPrologueAndTheOldDuration() throws {
        let export = config()
        let line = try XCTUnwrap(LinearTimeline(trip: trip(photoCounts: [3, 3]), config: export))
        XCTAssertEqual(line.openingS, 0)
        XCTAssertEqual(line.durationS, export.targetDurationS)
    }
}

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
    // Not `private`: shared with the opening-sequence tests split into
    // `RecapPacingOpeningSequenceTests.swift` (lint length only, Chiu 2026-08-07).
    func config(
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
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7, cameraSafeZoneFraction: 0.8,
            cameraResponsiveness: 6.0, endRevealS: 2.5, endRevealPadding: 1.9, endCardStyle: "full",
            deckPhotoHoldS: 2.5, deckPhotoMinHoldS: 0.2, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 1.0, openingRegionalS: 1.0, countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: stopDwellMinS, stopDwellMaxS: stopDwellMaxS,
            totalDurationMinS: totalMinS, totalDurationMaxS: totalMaxS,
            keyframeIntervalFrames: 15, subjectLengthPx: 300, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5,
            stopWeightingEnabled: false, waypointMaxPhotos: 2, waypointMaxDwellS: 900, waypointHoldS: 0.8,
            uncappedPhotoHoldS: 1.0,
            allocationZeroShare: 0.4, allocationOneShare: 0.3,
            allocationTwoShare: 0.2, allocationMaxPhotos: 3, favoriteWeight: 3.0,
            tierTopShare: 0.15,
            tierStandardPhotos: 3, tierTopPhotos: 5,
            earnedStopsFloor: 8, earnedStopsCap: 21,
            earnedStopsPerDoubling: 7, earnedStopsReferenceTripStops: 10,
            recapMode: .highlight
        )
    }

    var deck: RecapDeck {
        RecapDeck(photoHoldS: 2.5, zoomS: 0.5, labelLeadS: 0.6)
    }

    // Internal for the same reason as `config` above: the opening-sequence tests
    // live in another file and `private` is file-scoped.
    func trip(photoCounts: [Int]) -> RecapTrip {
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
    let establishing = RecapBounds(minLat: -47.5, minLon: 166.0, maxLat: -34.0, maxLon: 179.2)

    // MARK: - Target duration

    /// **Rewritten 2026-08-14 for the duration inversion** (Chiu). These two tests
    /// asserted the model that was just replaced — that duration is clamped into
    /// `[total_duration_min_s, total_duration_max_s]` and that a photo-heavy trip
    /// pins exactly to the ceiling. The ceiling is what made trip size invisible
    /// (every trip presented 8 stops because every film was 90 s), so an
    /// assertion that it still binds would now be asserting the defect.
    ///
    /// What replaces it is the property the inversion is *for*: duration is a
    /// function of how many stops the film presents, and nothing else.
    func testDurationIsBoughtByThePresentedStopsAndNotClamped() {
        let export = config()
        for count in [1, 2, 4, 8, 15, 21] {
            let plan = RecapDurationPlan.plan(
                photoCounts: Array(repeating: 3, count: count), config: export, deck: deck
            )
            let expected = max(
                StopPhotoAllocator.earnedDurationS(presentedStops: count, config: export),
                export.totalDurationMinS
            )
            XCTAssertEqual(plan.totalS, expected, accuracy: 0.01, "\(count) stops")
        }
    }

    /// More presented stops always buy a longer film — with **no ceiling** to stop
    /// at. Photo count per stop does not change the length: the cost model prices
    /// a stop, and what its photographs buy is dwell *within* that stop.
    func testMoreStopsBuyALongerFilmWithNoCeiling() {
        let export = config()
        // Counts chosen above the duration floor: below it every film is
        // `total_duration_min_s` and the comparison would say nothing. The floor
        // itself is covered by `testRouteOnlyTripGetsTheFloorAndNoDwell`.
        let twelve = RecapDurationPlan.plan(
            photoCounts: Array(repeating: 3, count: 12), config: export, deck: deck
        )
        let sixteen = RecapDurationPlan.plan(
            photoCounts: Array(repeating: 3, count: 16), config: export, deck: deck
        )
        let many = RecapDurationPlan.plan(
            photoCounts: Array(repeating: 3, count: 21), config: export, deck: deck
        )
        XCTAssertGreaterThan(sixteen.totalS, twelve.totalS)
        XCTAssertGreaterThan(many.totalS, sixteen.totalS)
        XCTAssertGreaterThan(many.totalS, export.totalDurationMaxS,
                             "the old ceiling must no longer bind — it is what hid trip size")

        // A photo-heavy trip is not a longer film, it is a denser one.
        let heavy = RecapDurationPlan.plan(
            photoCounts: Array(repeating: 8, count: 16), config: export, deck: deck
        )
        XCTAssertEqual(heavy.totalS, sixteen.totalS, accuracy: 0.01)
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

    func timeline(_ trip: RecapTrip, _ export: TrackingConfig.Export) throws -> LinearTimeline {
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

    /// The opening spends time only where the camera is actually going somewhere.
    ///
    /// When the installed region's extent *is* the trip's own extent — a tightly
    /// cut dogfood region — the country and regional beats frame the identical
    /// picture, so one of them is dropped rather than spending a transition and a
    /// hold on a frozen frame.
    ///
    /// (The beat this test used to guard, regional→route, is gone entirely: the
    /// route beat was a stored frame held with the vehicle pinned at distance
    /// zero, and deleting it beat collapsing it.)
    ///
    /// **The extent was the trip's own bounds until 2026-08-08, and that never
    /// tested this.** The sample route is a straight north-south line, so its
    /// bounding box has *zero* longitude extent, `containedSpanM` came out 0, and
    /// both wide beats floored onto `camera_span_m` — a 1.5 km frame for an 89 km
    /// trip. What then "still ran" was not a zoom at all but a 45 km translate
    /// across thirty frame-widths, which is the defect
    /// `FollowCameraRestingFrameTests` was added for. A region has area; this one
    /// is a snug box around the trip, which is what a tightly cut dogfood region
    /// actually looks like, and it collapses the beats *and* zooms.
    func testOpeningCollapsesBeatsThatDoNotMoveTheCamera() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 3])
        let line = try XCTUnwrap(LinearTimeline(
            trip: sample, config: export,
            establishing: RecapBounds(minLat: -44.2, minLon: 170.2, maxLat: -43.0, maxLon: 170.8)
        ))
        let configured = export.openingCountryS + export.openingRegionalS + 2 * export.zoomTransitionS
        XCTAssertLessThan(line.openingS, configured - 2, "duplicate beats must be dropped")
        XCTAssertGreaterThan(line.openingS, export.zoomTransitionS, "but the zoom itself still runs")

        // No stretch of the opening longer than one hold sits completely still —
        // measured from the end of the title card, like the gate in
        // `CameraPathTests`. A still frame *with the title on it* is the title
        // beat working; only stillness after the card is gone is a hang.
        var frozenRun = 0.0
        var previous = line.cameraFrame(atTime: export.titleCardS).spanM
        var longestFrozen = 0.0
        for time in stride(from: export.titleCardS, through: line.openingS, by: 1.0 / 30) {
            let span = line.cameraFrame(atTime: time).spanM
            if abs(span - previous) < 1 { frozenRun += 1.0 / 30 } else { frozenRun = 0 }
            longestFrozen = max(longestFrozen, frozenRun)
            previous = span
        }
        XCTAssertLessThan(
            longestFrozen, export.openingRegionalS + 0.5,
            "the opening froze for \(longestFrozen)s — that is the hang"
        )

        // Held through the country beat, then monotonically zooming in.
        let country = line.cameraFrame(atTime: 0).spanM
        XCTAssertEqual(line.cameraFrame(atTime: export.openingCountryS - 0.1).spanM, country, accuracy: 1)

        var widest = country
        for time in stride(from: export.openingCountryS, through: line.openingS, by: 0.25) {
            let span = line.cameraFrame(atTime: time).spanM
            XCTAssertLessThanOrEqual(span, widest + 1, "the opening must only ever zoom in (t=\(time))")
            widest = span
        }
    }

    /// The subject waits at the route's start while the camera establishes, so the
    /// trail has not begun and the opening has the frame to itself.
    func testSubjectHoldsAtTheRouteStartThroughTheOpening() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 3])
        let line = try timeline(sample, export)
        let start = try XCTUnwrap(sample.route.first)

        // The journey waits for the opening to resolve completely. An earlier
        // pass started it during the closing zoom so that something would be
        // moving through the wide beats; that made the first stop present itself
        // mid-zoom, against the rule that the camera never zooms while the
        // journey is on screen. The dead air it was hiding is fixed at source —
        // the wide beats are capped (`testOpeningHasNoHeldBeat…`).
        XCTAssertEqual(line.journeyStartS, line.openingS, accuracy: 1e-9)
        for time in stride(from: 0.0, to: line.openingS - 0.1, by: 0.5) {
            let subject = line.subjectState(atTime: time)
            XCTAssertEqual(subject.lat, start.lat, accuracy: 1e-6, "vehicle moved during the opening (t=\(time))")
        }
        let moved = line.subjectState(atTime: line.openingS + (line.durationS - line.openingS) * 0.5)
        XCTAssertGreaterThan(abs(moved.lat - start.lat), 1e-4)
    }

    /// **The body never zooms, and never cuts** (Chiu 2026-08-01). The camera may
    /// translate — that is the dolly following the journey — but the span is
    /// fixed for the whole trip and consecutive frames always share their ground.
    ///
    /// This replaced an assertion that the camera was *completely* still after
    /// the opening. That rule came from the act camera, where holding still was
    /// the only way to stay legible; it is exactly what forced a cut whenever the
    /// journey outgrew one frame.
    func testBodyTranslatesWithoutZoomingOrCutting() throws {
        let export = config()
        let line = try timeline(trip(photoCounts: [3, 4, 2]), export)

        let settled = line.cameraFrame(atTime: line.openingS + 0.5)
        let step = 1.0 / Double(export.fps)
        var previous = settled
        var time = line.openingS + 0.5
        while time <= line.durationS - export.endCardS - export.endRevealS {
            let frame = line.cameraFrame(atTime: time)
            XCTAssertEqual(frame.spanM, settled.spanM, accuracy: 0.5, "camera zoomed at t=\(time)")
            XCTAssertEqual(frame.bearing, 0, "camera rotated at t=\(time)")
            let moved = Geo.distanceM(
                latA: previous.centerLat, lonA: previous.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            XCTAssertLessThan(moved, frame.spanM * 0.5, "camera cut at t=\(time)")
            previous = frame
            time += step
        }
    }

    /// `.fixed` means no prologue and exactly the length asked for — the
    /// deterministic harness path, so a golden frame means something.
    ///
    /// **Renamed 2026-08-08.** This was `testNoEstablishingExtentMeansNoPrologue…`
    /// and asserted that a *nil map extent* produced this. It asserted the
    /// coupling, not the behaviour: pacing read `establishing`, so "no tiles
    /// installed" and "give me a short fixed film" were the same request. The
    /// behaviour it guards is still wanted; only the way of asking for it changed.
    func testFixedPacingMeansNoPrologueAndExactlyTheLengthAsked() throws {
        let export = config()
        let line = try XCTUnwrap(LinearTimeline(
            trip: trip(photoCounts: [3, 3]), config: export,
            pacing: .fixed(totalS: export.targetDurationS)
        ))
        XCTAssertEqual(line.openingS, 0, "no prologue, so zoom_transition_s never enters the opening")
        XCTAssertEqual(line.durationS, export.targetDurationS)
    }

    /// **Pacing is a story fact and must never consult the map** (Chiu 2026-08-08).
    ///
    /// The defect this locks out: `LinearTimeline.pacing` used to be gated on
    /// `establishing != nil`, so a trip that no installed vector-tile region
    /// covered fell back to a flat `target_duration_s` with no prologue. A six-day
    /// trip came out 30 seconds long because of which files were on the device.
    ///
    /// **What is asserted, and what deliberately is not.** The film's *length* is a
    /// story fact and must be identical whatever the coverage — that is the whole
    /// defect. How that time is *distributed* is not map-independent, and should
    /// not be: a wide beat showing nothing the body shot does not already show is
    /// collapsed, which is a framing decision the tiles legitimately participate
    /// in, and a shorter opening hands the body more time to spend. Measured, the
    /// stop presentation moves 1022 → 1085 frames between the widest and tightest
    /// coverage while the film stays exactly as long. Asserting that away would be
    /// asserting that framing ignores the tiles, which is the opposite of what the
    /// span cap exists for.
    func testFilmLengthIsIdenticalWhateverTheMapCoverage() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 1, 8, 2])
        let extents: [(String, RecapBounds?)] = [
            ("no tiles at all (Apple's map)", nil),
            ("a region far wider than the trip", establishing),
            ("a region barely containing the trip",
             RecapBounds(minLat: -44.2, minLon: 170.2, maxLat: -43.0, maxLon: 170.8))
        ]
        var reference: Double?
        for (label, extent) in extents {
            let line = try XCTUnwrap(LinearTimeline(trip: sample, config: export, establishing: extent))
            guard let first = reference else { reference = line.durationS; continue }
            XCTAssertEqual(
                line.durationS, first, accuracy: 0.001,
                "film length changed with \(label) — length is content, not coverage"
            )
        }
    }

    /// The structural half of the same rule: the plan that decides length and
    /// per-stop weight takes **no map input at all**, so it cannot consult tile
    /// state even by accident. This pins the signature as much as the numbers.
    func testTheDurationPlanTakesNoMapInput() {
        let export = config()
        let counts = [3, 1, 8, 2]
        let first = RecapDurationPlan.plan(photoCounts: counts, config: export, deck: deck)
        let second = RecapDurationPlan.plan(photoCounts: counts, config: export, deck: deck)
        XCTAssertEqual(first.totalS, second.totalS)
        XCTAssertEqual(first.openingS, second.openingS)
        XCTAssertEqual(first.stopDwellS, second.stopDwellS)
    }
}

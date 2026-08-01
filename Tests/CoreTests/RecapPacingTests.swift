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
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7,
            cameraResponsiveness: 6.0, endRevealS: 2.5,
            deckPhotoHoldS: 2.5, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 3.0, openingRegionalS: 3.5, openingRouteS: 0.4,
            countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
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
    func testOpeningCollapsesBeatsThatDoNotMoveTheCamera() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 3])
        let lats = sample.route.map(\.lat), lons = sample.route.map(\.lon)
        let line = try XCTUnwrap(LinearTimeline(
            trip: sample, config: export,
            establishing: RecapBounds(
                minLat: lats.min()!, minLon: lons.min()!, maxLat: lats.max()!, maxLon: lons.max()!
            )
        ))
        let configured = export.openingCountryS + export.openingRegionalS + 2 * export.zoomTransitionS
        XCTAssertLessThan(line.openingS, configured - 2, "duplicate beats must be dropped")
        XCTAssertGreaterThan(line.openingS, export.zoomTransitionS, "but the zoom itself still runs")

        // No stretch of the opening longer than one hold sits completely still.
        var frozenRun = 0.0
        var previous = line.cameraFrame(atTime: 0).spanM
        var longestFrozen = 0.0
        for time in stride(from: 0.0, through: line.openingS, by: 1.0 / 30) {
            let span = line.cameraFrame(atTime: time).spanM
            if abs(span - previous) < 1 { frozenRun += 1.0 / 30 } else { frozenRun = 0 }
            longestFrozen = max(longestFrozen, frozenRun)
            previous = span
        }
        XCTAssertLessThan(
            longestFrozen, max(export.openingCountryS, export.openingRegionalS) + 0.5,
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
    func testSubjectHoldsAtTheRouteStartThroughTheWideOpening() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 3])
        let line = try timeline(sample, export)
        let start = try XCTUnwrap(sample.route.first)

        // Only through the *wide* beats. The journey deliberately starts before
        // the opening finishes (Chiu 2026-08-01): the closing zoom plays over a
        // moving car and a growing trail, which is what removed the freeze that
        // survived every round of dwell tuning.
        for time in stride(from: 0.0, to: line.journeyStartS - 0.1, by: 0.5) {
            let subject = line.subjectState(atTime: time)
            XCTAssertEqual(subject.lat, start.lat, accuracy: 1e-6, "vehicle moved during the wide opening (t=\(time))")
        }
        XCTAssertLessThan(line.journeyStartS, line.openingS, "the journey must start before the opening ends")
        // It is already rolling by the time the opening resolves.
        let rolling = line.subjectState(atTime: line.openingS)
        XCTAssertGreaterThan(abs(rolling.lat - start.lat), 1e-7, "the car should be moving as the opening settles")
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

    /// Without an establishing extent nothing changes: no prologue, the old fixed
    /// duration. That is what keeps every existing trip and golden frame intact.
    func testNoEstablishingExtentMeansNoPrologueAndTheOldDuration() throws {
        let export = config()
        let line = try XCTUnwrap(LinearTimeline(trip: trip(photoCounts: [3, 3]), config: export))
        XCTAssertEqual(line.openingS, 0)
        XCTAssertEqual(line.durationS, export.targetDurationS)
    }

    // MARK: - Opening sequence (Chiu 2026-07-31)

    /// A trip whose first stop sits at the route's origin, `photoBearing`
    /// deciding whether it has anything to present.
    private func tripOpeningOnAStop(photoBearing: Bool) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -44.0 + Double($0) * 0.02, lon: 170.5) }
        let first = RecapTrip.Stop(
            coordinate: route[0], name: "Origin", dayLabel: "Day 1",
            photos: photoBearing ? [.asset("o1"), .asset("o2"), .asset("o3")] : [],
            dwellS: deck.dwellS(photoCount: photoBearing ? 3 : 0)
        )
        let later = RecapTrip.Stop(
            coordinate: route[25], name: "Later", dayLabel: "Day 2",
            photos: [.asset("l1"), .asset("l2")], dwellS: deck.dwellS(photoCount: 2)
        )
        return RecapTrip(
            route: route, stops: [first, later], title: "Trip", subtitle: "",
            statsLines: [], callToAction: ""
        )
    }

    /// The first moment the subject is drawn at all.
    private func firstSubjectAppearance(_ line: LinearTimeline) -> Double? {
        var time = 0.0
        while time <= line.durationS {
            if line.subjectState(atTime: time).emphasis > 0.001 { return time }
            time += 1.0 / 30
        }
        return nil
    }

    /// The first moment any stop content is drawn.
    private func firstStopPresentation(_ line: LinearTimeline) -> Double? {
        var time = 0.0
        while time <= line.durationS {
            for content in line.overlayContents(atTime: time) {
                if case let .stopLabel(_, _, _, opacity) = content, opacity > 0.001 { return time }
                if case let .photoDeck(deck) = content, deck.opacity > 0.001 { return time }
            }
            time += 1.0 / 30
        }
        return nil
    }

    /// **Case A** — the trip opens on a photo-bearing stop:
    /// opening → stop presentation → car appears → first leg.
    ///
    /// The car must never appear and then park at the origin. That was a
    /// sequencing fault, not a pacing one: the vehicle was on screen before the
    /// journey it belongs to had anything to show.
    func testTripOpeningOnAPhotoStopPresentsTheStopBeforeTheCarExists() throws {
        let export = config()
        let line = try timeline(tripOpeningOnAStop(photoBearing: true), export)

        let stopAt = try XCTUnwrap(firstStopPresentation(line), "the opening stop must present itself")
        let carAt = try XCTUnwrap(firstSubjectAppearance(line), "the car must eventually arrive")

        XCTAssertGreaterThanOrEqual(
            stopAt, line.journeyStartS - 0.05,
            "the stop belongs to the journey, which starts as the opening's closing zoom begins"
        )
        XCTAssertGreaterThan(carAt, stopAt, "the car must not exist before the stop has been presented")

        // Not drawn anywhere across the prologue or the stop's own scene.
        for time in stride(from: 0.0, to: stopAt + 0.5, by: 1.0 / 30) {
            XCTAssertEqual(
                line.subjectState(atTime: time).emphasis, 0, accuracy: 1e-6,
                "the car must be absent at t=\(time) — before it, only the place exists"
            )
        }
        // And once it arrives it stays: no appear-then-park at the origin.
        for time in stride(from: carAt + 0.5, through: min(carAt + 3, line.durationS), by: 1.0 / 30) {
            XCTAssertGreaterThan(
                line.subjectState(atTime: time).emphasis, 0.001,
                "the car parked again right after arriving at t=\(time) — that is the false start"
            )
        }
    }

    /// **Case B** — nothing to present at the origin: opening → car → first leg.
    /// There is no stop scene to wait for, so the car simply arrives with the
    /// route and drives.
    func testTripWithoutAPhotoStopAtTheOriginJustStartsDriving() throws {
        let export = config()
        let line = try timeline(tripOpeningOnAStop(photoBearing: false), export)

        let carAt = try XCTUnwrap(firstSubjectAppearance(line))
        XCTAssertLessThanOrEqual(
            carAt, line.openingS + 0.05,
            "with nothing to present, the car arrives with the route rather than waiting"
        )
        XCTAssertGreaterThan(carAt, 0, "but not before the establishing shot has run")
        // It is moving shortly after, not parked.
        let start = try XCTUnwrap(tripOpeningOnAStop(photoBearing: false).route.first)
        let moved = line.subjectState(atTime: line.openingS + (line.durationS - line.openingS) * 0.3)
        XCTAssertGreaterThan(abs(moved.lat - start.lat), 1e-4, "the first leg must actually run")
    }

    /// The sequence choice is about *presentable content*, not about position:
    /// a photoless origin stop must not trigger the wait.
    func testTheWaitIsChosenByPhotosNotByPosition() throws {
        let export = config()
        let withPhotos = try timeline(tripOpeningOnAStop(photoBearing: true), export)
        let without = try timeline(tripOpeningOnAStop(photoBearing: false), export)
        let delayed = try XCTUnwrap(firstSubjectAppearance(withPhotos))
        let prompt = try XCTUnwrap(firstSubjectAppearance(without))
        XCTAssertGreaterThan(delayed, prompt, "only the presentable stop delays the car")
    }
}

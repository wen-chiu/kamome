import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Opening sequence (Chiu 2026-07-31). Split from `RecapPacingTests.swift`
/// (lint length only, Chiu 2026-08-07) — shares its fixtures (`config`,
/// `deck`, `timeline`, `establishing`), so those became internal there rather
/// than `private`.
extension RecapPacingTests {
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

    /// **A region with nothing wider to say opens where the journey begins.**
    ///
    /// The counterpart to `testOpeningCollapsesBeatsThatDoNotMoveTheCamera`, and
    /// the unit-level statement of the bug that turned CI red on 2026-08-07.
    ///
    /// `cappedToRegion` refuses to frame ground the installed tiles cannot draw,
    /// and when a trip nearly fills its region that cap lands on the *same* span
    /// the body camera uses. The wide beat is then no wider than the body — there
    /// is no establishing shot to be had. It used to stay centred on the trip
    /// anyway, so the "closing zoom" that followed had no zoom left in it and was
    /// purely a translate from the middle of the trip to its start: on the real
    /// New Zealand fixture, 110 km across a 41 km frame, replacing the screen's
    /// entire contents twice before the film had begun.
    ///
    /// The correct behaviour is to open on the journey's start and hold. This
    /// asserts the two halves of that: the span never changes (nothing to zoom),
    /// and the frame never travels (nothing to pan to).
    func testARegionNoWiderThanTheBodyOpensOnTheJourneyWithoutPanning() throws {
        let export = config()
        let sample = trip(photoCounts: [3, 3])
        // A region cut so tightly around this north-south trip that the widest
        // frame fitting inside it is narrower than the body camera's own span —
        // so the cap lands on both and there is genuinely nothing wider to show.
        // (A slightly looser box leaves a real zoom, which is correct and is what
        // `testOpeningCollapsesBeatsThatDoNotMoveTheCamera` covers.)
        let line = try XCTUnwrap(LinearTimeline(
            trip: sample, config: export,
            establishing: RecapBounds(minLat: -44.0, minLon: 170.47, maxLat: -43.2, maxLon: 170.53)
        ))

        let opening = line.cameraFrame(atTime: 0)
        for time in stride(from: 0.0, through: line.journeyStartS, by: 1.0 / 30) {
            let frame = line.cameraFrame(atTime: time)
            XCTAssertEqual(
                frame.spanM, opening.spanM, accuracy: 1,
                "there is no wider frame available, so the opening must not pretend to zoom (t=\(time))"
            )
            let movedM = Geo.distanceM(
                latA: opening.centerLat, lonA: opening.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            XCTAssertLessThan(
                movedM, frame.spanM * 0.1,
                "the opening travelled \(Int(movedM)) m across a \(Int(frame.spanM)) m frame at t=\(time) "
                    + "— that is the pre-pan, not an establishing shot"
            )
        }
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

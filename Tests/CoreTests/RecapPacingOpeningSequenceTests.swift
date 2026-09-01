import KamomeConfig
@testable import KamomeExportEngine
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

        // **The card beat is a still frame.** This is what earns the cut: a
        // viewer reads a held picture under a title as chrome, and a cut out of
        // chrome is a film convention. If the camera moved here it would be a
        // shot, and cutting out of a shot is the bug Chiu named. Asserted first,
        // because everything below depends on the film proper starting at the cut.
        let cut = try XCTUnwrap(line.titleCutS, "the opening must cut, not ease, out of the title card")
        let card = line.cameraFrame(atTime: 0)
        for time in stride(from: 0.0, to: cut, by: 1.0 / 30) {
            let frame = line.cameraFrame(atTime: time)
            XCTAssertEqual(frame.spanM, card.spanM, accuracy: 1, "the card beat zoomed at t=\(time)")
            XCTAssertEqual(frame.centerLat, card.centerLat, accuracy: 1e-9, "the card beat panned at t=\(time)")
            XCTAssertEqual(frame.centerLon, card.centerLon, accuracy: 1e-9, "the card beat panned at t=\(time)")
        }

        // **From the cut on, the rule this test was written for still holds** —
        // the opening must not turn into a pan — but it is asserted as
        // containment now rather than as a translate budget, and this is the
        // restatement `Arch.md` §4 asks for rather than a deletion.
        //
        // What it caught: `cappedToRegion` could make the wide beat no wider than
        // the body, at which point the closing "zoom" had no zoom left and was a
        // pure 110 km translate across a 41 km frame — the screen's entire
        // contents replaced twice before the film had begun (New Zealand,
        // 2026-08-07).
        //
        // Why the old form cannot stand: it asserted the span never changes and
        // the centre never moves more than 10% of a frame, and **both encoded the
        // tiles-era cap as the mechanism**. That cap is gone — Apple Maps is
        // global, MapLibre is parked, and beat 2 is now fitted to the trip's own
        // local journey — so the closing zoom legitimately translates while it
        // zooms, from framing the journey to framing where it starts.
        //
        // The rule without the mechanism: **the camera never shows ground the
        // establishing frame did not.** That is strictly stronger than a 10%
        // budget — a small translate that also zoomed *out* would pass the budget
        // and fail this — and it is what `CameraPath.containedLerp` guarantees by
        // construction, so it asserts the guarantee rather than a symptom of it.
        let filmProperStartsS = cut + 1.0 / 30
        let establishing = line.cameraFrame(atTime: filmProperStartsS)
        let aspect = Double(export.frameWidthPx) / Double(export.frameHeightPx)
        for time in stride(from: filmProperStartsS, through: line.journeyStartS, by: 1.0 / 30) {
            let frame = line.cameraFrame(atTime: time)
            let eastM = Geo.distanceM(
                latA: frame.centerLat, lonA: establishing.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            let northM = Geo.distanceM(
                latA: establishing.centerLat, lonA: frame.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            // A metre of slack: the comparison is flat-earth about two nearby
            // centres, and the guarantee is geometric rather than to the metre.
            XCTAssertLessThanOrEqual(
                eastM + frame.spanM / 2, establishing.spanM / 2 + 1,
                "at t=\(time) the closing zoom ran off the establishing frame's east/west edge"
            )
            XCTAssertLessThanOrEqual(
                northM + frame.spanM / aspect / 2, establishing.spanM / aspect / 2 + 1,
                "at t=\(time) the closing zoom ran off the establishing frame's north/south edge"
            )
            let movedM = Geo.distanceM(
                latA: establishing.centerLat, lonA: establishing.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            XCTAssertLessThan(
                movedM, establishing.spanM,
                "at t=\(time) the opening travelled \(Int(movedM)) m — more than the establishing frame is wide"
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

    /// **Beats that do not move the camera are dropped** (Chiu 2026-07-31),
    /// driven directly rather than through a fixture (`Arch.md` §4).
    ///
    /// `testOpeningCollapsesBeatsThatDoNotMoveTheCamera` used to reach `collapse`
    /// by giving a trip a synthetic `establishing` extent so tight that
    /// `cappedToRegion` shrank the regional beat onto the country beat. Neither
    /// half of that route survives 2026-08-31: the country beat comes from
    /// `CountryExtent`, and a whole country against one trip's bounds cannot be a
    /// near-duplicate on any fixture. The rule is about the function; the fixture
    /// was only ever how the test got to it.
    func testCollapseDropsBeatsTheEyeCannotTellApart() throws {
        let export = config()
        let duplicate = CameraPath.CameraFrame(
            centerLat: -43.6, centerLon: 170.5, spanM: 40_000, bearing: 0
        )
        let nudged = CameraPath.CameraFrame(
            centerLat: -43.6, centerLon: 170.5, spanM: 40_000 * 1.01, bearing: 0
        )
        XCTAssertEqual(
            CameraPath.collapse(
                [CameraPath.Beat(frame: duplicate, holdS: 3), CameraPath.Beat(frame: nudged, holdS: 1)],
                config: export
            ).count,
            1,
            "two framings the eye cannot tell apart must become one beat"
        )
        let wider = CameraPath.CameraFrame(
            centerLat: -43.6, centerLon: 170.5, spanM: 400_000, bearing: 0
        )
        XCTAssertEqual(
            CameraPath.collapse(
                [CameraPath.Beat(frame: duplicate, holdS: 3), CameraPath.Beat(frame: wider, holdS: 1)],
                config: export
            ).count,
            2,
            "a beat that really does move the camera must survive"
        )
    }
}

import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Shared harness for the linear timeline's suites: a sample multi-stop trip,
/// the shipped export tunables, and fine samplers over the deck window.
class LinearTimelineTestCase: XCTestCase {
    /// A deterministic fixed-length film with no prologue — what these harnesses
    /// want. Said plainly since 2026-08-08; it used to be requested by passing a
    /// nil map extent, which meant "no tiles installed" everywhere else.
    func fixedTimeline(
        _ trip: RecapTrip, _ config: TrackingConfig.Export
    ) throws -> LinearTimeline {
        try XCTUnwrap(LinearTimeline(
            trip: trip, config: config, pacing: .fixed(totalS: config.targetDurationS)
        ))
    }

    func exportConfig(
        targetDurationS: Double = 30,
        deckZoomS: Double = 0.5,
        deckPhotoHoldS: Double = 0.8,
        deckPhotoMinHoldS: Double = 0.2,
        cameraSpanM: Double = 1500
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: 1080, frameHeightPx: 1920,
            cameraSpanM: cameraSpanM, wideSpanPadding: 1.15, zoomTransitionS: 0.8, actSplitKm: 25, followHeadingUp: false,
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7, cameraSafeZoneFraction: 0.8,
            cameraResponsiveness: 6.0, endRevealS: 2.5, endRevealPadding: 1.9, endCardStyle: "full",
            deckPhotoHoldS: deckPhotoHoldS, deckPhotoMinHoldS: deckPhotoMinHoldS,
            deckZoomS: deckZoomS, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 1.0, openingRegionalS: 1.0, countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
            keyframeIntervalFrames: 15, subjectLengthPx: 300, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5,
            // Stop weighting off: these gates measure the unweighted pacing.
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

    /// A wandering route with `photoCounts.count` stops spaced along it; each
    /// stop's dwell is photo-count-driven (`RecapDeck.dwellS`).
    func sampleTrip(photoCounts: [Int], config: TrackingConfig.Export) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let stops = photoCounts.enumerated().map { index, count -> RecapTrip.Stop in
            RecapTrip.Stop(
                coordinate: route[(index + 1) * 9],
                name: "Stop \(index + 1)", dayLabel: "Day 1", detail: nil,
                photos: (0..<count).map { .asset("s\(index)-\($0)") },
                dwellS: deck.dwellS(photoCount: count)
            )
        }
        return RecapTrip(
            route: route, stops: stops, title: "Sample", subtitle: "3 stops",
            statsLines: ["291 km · 3 stops"], callToAction: "Get this route", shareURL: "kamome://route/sample"
        )
    }

    func activePhotoDeck(_ contents: [OverlayContent]) -> RecapPhotoDeck? {
        for content in contents {
            if case let .photoDeck(deck) = content { return deck }
        }
        return nil
    }

    func hasStopLabel(_ contents: [OverlayContent], name: String) -> Bool {
        contents.contains {
            if case let .stopLabel(labelName, _, _, _) = $0 { return labelName == name }
            return false
        }
    }

    func firstTime(
        _ timeline: LinearTimeline, dt: Double = 1.0 / 30, where predicate: ([OverlayContent]) -> Bool
    ) -> Double? {
        var time = 0.0
        while time <= timeline.durationS {
            if predicate(timeline.overlayContents(atTime: time)) { return time }
            time += dt
        }
        return nil
    }

    struct DeckSample {
        let time: Double
        let reveal: Double
        let opacity: Double
        let spanM: Double
        let focus: Int
    }

    /// Fine-samples the deck window for the stop whose photos start with
    /// `firstRef` — only where the card is actually **drawn**. The timeline keeps
    /// emitting the content at zero opacity through the stop's departure beat,
    /// and a card nobody can see is not part of the deck's window.
    func deckWindow(
        _ timeline: LinearTimeline, firstRef: PhotoRef, dt: Double = 1.0 / 30
    ) -> [DeckSample] {
        var samples: [DeckSample] = []
        var time = 0.0
        while time <= timeline.durationS {
            if let deck = activePhotoDeck(timeline.overlayContents(atTime: time)),
               deck.photos.first == firstRef, deck.opacity > 0.001 {
                samples.append(DeckSample(
                    time: time, reveal: deck.reveal, opacity: deck.opacity,
                    spanM: timeline.cameraFrame(atTime: time).spanM, focus: deck.focusIndex
                ))
            }
            time += dt
        }
        return samples
    }
}

/// The photo deck's own reveal envelope, and the map holding still under it.
/// Since 2026-07-25 the camera holds a **fixed** frame — a stop is told by the
/// label and the card, never by flying the map — so these assert the card's
/// envelope *and* that the map stays put underneath it.
final class LinearTimelineTests: LinearTimelineTestCase {
    func testStopSceneOpensAndClosesTheCardWhileTheMapHoldsStill() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try fixedTimeline(trip, config)

        // The middle stop has 4 photos. Its hold also carries the park and
        // pull-away beats, so the *card's* own window is what is left:
        // 2·deckZoomS + 4·deckPhotoHoldS = 4.2 s.
        let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first))
        XCTAssertFalse(window.isEmpty, "the deck must be present through the stop")
        let start = try XCTUnwrap(window.first), end = try XCTUnwrap(window.last)
        XCTAssertEqual(end.time - start.time, 4.2, accuracy: 0.1, "2·deckZoomS + n·deckPhotoHoldS")

        // Edges: card barely present. Middle: card solid.
        XCTAssertLessThan(start.opacity, 0.2)
        XCTAssertLessThan(end.opacity, 0.2)
        let mid = window[window.count / 2]
        XCTAssertEqual(mid.opacity, 1, accuracy: 0.01)

        // The map does not move a metre across the whole stop — that is the
        // point of the fixed frame (Chiu 2026-07-25).
        let spans = Set(window.map { ($0.spanM * 100).rounded() })
        XCTAssertEqual(spans.count, 1, "the camera span must not change during a stop")

        // Focus rotates across all four photos.
        XCTAssertEqual(window.map(\.focus).min(), 0, "highlight leads")
        XCTAssertEqual(window.map(\.focus).max(), 3, "reaches the last photo")
    }

    func testStopLabelLeadsBeforeThePhotoDeck() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try fixedTimeline(trip, config)

        // Three beats now: the label comes up as the car parks, holds alone for
        // deck_label_lead_s, then the deck blooms.
        let labelStart = try XCTUnwrap(firstTime(timeline) { self.hasStopLabel($0, name: "Stop 2") })
        let deckStart = try XCTUnwrap(deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first)).first).time
        XCTAssertEqual(
            deckStart - labelStart, config.subjectParkS + config.deckLabelLeadS, accuracy: 0.1,
            "the deck opens a lead time after the car has finished parking"
        )

        // Mid-lead: the label is up but the photos have not arrived yet.
        let midLead = labelStart + config.subjectParkS + config.deckLabelLeadS / 2
        XCTAssertTrue(hasStopLabel(timeline.overlayContents(atTime: midLead), name: "Stop 2"))
        XCTAssertNil(activePhotoDeck(timeline.overlayContents(atTime: midLead)), "no deck during the label lead")
    }

    /// The card opens on its own envelope across the whole hold, and the map is
    /// untouched throughout — the reveal is an overlay concern only.
    func testDeckRevealOpensAcrossTheHoldWithoutMovingTheMap() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try fixedTimeline(trip, config)
        let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first))

        let peak = try XCTUnwrap(window.max { $0.reveal < $1.reveal })
        XCTAssertGreaterThan(peak.reveal, 0.9, "the card reaches full size before the scene closes")

        // The reveal only ever grows up to its peak, then eases back down.
        let opening = window.filter { $0.time <= peak.time }
        for (before, after) in zip(opening, opening.dropFirst()) {
            XCTAssertGreaterThanOrEqual(after.reveal, before.reveal - 1e-9, "the reveal must not stutter")
        }
        let closing = window.filter { $0.time >= peak.time }
        for (before, after) in zip(closing, closing.dropFirst()) {
            XCTAssertLessThanOrEqual(after.reveal, before.reveal + 1e-9, "the reveal must ease back down")
        }
        XCTAssertLessThan(try XCTUnwrap(window.last).reveal, 0.5, "the card scales back down as the scene closes")

        // Nothing the card did moved the camera.
        let spans = Set(window.map { ($0.spanM * 100).rounded() })
        XCTAssertEqual(spans.count, 1, "the deck reveal must not touch the camera")
    }

    /// The lead-in label hands the stop's identity to the card: it is solid
    /// through beat 1 and gone once the deck is fully up, so the two never
    /// double-print the stop name.
    func testLeadLabelFadesOutAsTheDeckTakesOver() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try fixedTimeline(trip, config)
        let deckStart = try XCTUnwrap(deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first)).first).time

        func labelOpacity(atTime time: Double) -> Double? {
            for content in timeline.overlayContents(atTime: time) {
                if case let .stopLabel(_, _, _, opacity) = content { return opacity }
            }
            return nil
        }

        // The hand-off is deliberately shorter than the card's grow (2026-08-02):
        // at a wide span the pin and the card sit far apart, and a slow crossfade
        // reads as the place being named twice rather than as one hand-off.
        let handoff = RecapDeck().labelHandoffS
        XCTAssertLessThan(handoff, config.deckZoomS, "the name must clear faster than the card opens")

        XCTAssertEqual(labelOpacity(atTime: deckStart - 0.2) ?? 0, 1, accuracy: 0.01, "solid through the lead beat")
        let midFade = labelOpacity(atTime: deckStart + handoff / 2) ?? 0
        XCTAssertGreaterThan(midFade, 0.05)
        XCTAssertLessThan(midFade, 0.95, "mid cross-fade with the card")
        XCTAssertNil(labelOpacity(atTime: deckStart + handoff + 0.05), "gone once the card owns the name")
    }

    func testPhotolessStopGetsNoDeckAndNoDolly() throws {
        let config = exportConfig()
        // One stop, no photos → uniform stop_hold_s, no deck, no dolly.
        var trip = sampleTrip(photoCounts: [0], config: config)
        trip = RecapTrip(
            route: trip.route,
            stops: [RecapTrip.Stop(
                coordinate: trip.stops[0].coordinate, name: "Bare", dayLabel: "Day 1",
                detail: nil, photos: [], dwellS: config.stopHoldS
            )],
            title: trip.title, subtitle: trip.subtitle, statsLines: trip.statsLines,
            callToAction: trip.callToAction, shareURL: trip.shareURL
        )
        let timeline = try fixedTimeline(trip, config)
        for time in stride(from: 0.0, through: timeline.durationS, by: 0.25) {
            XCTAssertNil(activePhotoDeck(timeline.overlayContents(atTime: time)), "no photos → no deck at t=\(time)")
        }
    }

    /// Manual timing review (env-gated): dumps the camera + overlay streams around
    /// the middle stop so the zoom-in / hold / zoom-out durations and the deck's
    /// appearance relative to the camera dolly can be read by eye.
    ///   KAMOME_TIMELINE_DUMP=1 xcodebuild test -only-testing:KamomeCoreTests/LinearTimelineTests/testDumpStopTransition
    func testDumpStopTransition() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_TIMELINE_DUMP"] == "1",
            "Manual timing dump — set KAMOME_TIMELINE_DUMP=1."
        )
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try fixedTimeline(trip, config)

        print(String(format: "=== LinearTimeline (3 stops, photos [3,4,2]) — duration %.1fs ===", timeline.durationS))
        print(String(format: "title chrome [0.0, %.1f)   end chrome [%.1f, %.1f)",
                     config.titleCardS, timeline.durationS - config.endCardS, timeline.durationS))
        for index in trip.stops.indices {
            let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[index].photos.first))
            guard let start = window.first, let end = window.last else { continue }
            let lead = config.deckLabelLeadS
            let zoom = min(config.deckZoomS, (end.time - start.time) * 0.4)
            print(String(format: "stop %d: [%.2f, %.2f)  label-lead %.1f | zoom-in %.1f | hold %.1f | zoom-out %.1f  photos %d",
                         index + 1, start.time - lead, end.time, lead, zoom,
                         (end.time - start.time) - 2 * zoom, zoom, trip.stops[index].photos.count))
        }

        let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first))
        let start = try XCTUnwrap(window.first).time, end = try XCTUnwrap(window.last).time
        print("--- around stop 2 (t, camSpan, bearing, deckEmphasis, focus, overlays) ---")
        var time = start - config.deckLabelLeadS - 0.3
        while time <= end + 0.4 {
            let camera = timeline.cameraFrame(atTime: time)
            let contents = timeline.overlayContents(atTime: time)
            let deck = activePhotoDeck(contents)
            let kinds = contents.map { content -> String in
                switch content {
                case let .routeReveal(points): return "route(\(points.count))"
                case let .stopLabel(_, _, _, opacity): return String(format: "label(o%.2f)", opacity)
                case let .photoDeck(deck):
                    return String(format: "deck(f%d,r%.2f,o%.2f)", deck.focusIndex, deck.reveal, deck.opacity)
                case .titleChrome: return "title"
                case .endChrome: return "end"
                case let .hud(day, place, travelledM):
                    return String(format: "hud(%@/%@,%.0fm)", day, place ?? "-", travelledM)
                }
            }
            // reveal (card size) and span (map dolly) are separate curves — this
            // dump is how you eyeball that they stay in step without merging.
            print(String(format: "t=%5.2f  span=%6.0f  bear=%3.0f  reveal=%.2f  f=%@  [%@]",
                         time, camera.spanM, camera.bearing,
                         deck?.reveal ?? 0, deck.map { "\($0.focusIndex)" } ?? "-", kinds.joined(separator: ", ")))
            time += 0.1
        }
    }
}

/// **No photograph is ever shown for less than a second** (Chiu 2026-08-03).
///
/// `deck_photo_hold_s` is what a photo asks for, but `RecapDurationPlan` scales
/// every stop down to fit the film's ceiling, so a photo-dense stop could page
/// its deck faster than the eye resolves — a flicker, not a picture. Given the
/// choice, the stop shows fewer photographs rather than faster ones.
///
/// Measured off the timeline the renderer actually consumes, not off the helper
/// that decides it: the rule is about what reaches the screen.
final class DeckPhotoFloorTests: LinearTimelineTestCase {
    /// Longest run each distinct photo stays on screen, per stop.
    private func photoDurations(_ line: LinearTimeline, fps: Int) -> [Double] {
        let step = 1.0 / Double(fps)
        var runs: [Double] = []
        var currentKey: String?
        var runLength = 0.0
        for frame in 0...Int(line.durationS * Double(fps)) {
            let time = Double(frame) * step
            var key: String?
            for content in line.overlayContents(atTime: time) {
                if case let .photoDeck(deck) = content, deck.opacity > 0.5, !deck.photos.isEmpty {
                    key = "\(deck.name)#\(deck.focusIndex)"
                }
            }
            if key == currentKey {
                runLength += step
            } else {
                if currentKey != nil { runs.append(runLength) }
                currentKey = key
                runLength = step
            }
        }
        if currentKey != nil { runs.append(runLength) }
        return runs
    }

    func testEveryPhotoStaysOnScreenForAtLeastTheFloor() throws {
        let export = exportConfig(deckPhotoMinHoldS: 1.0)
        // Eight photos on every stop — the most the importer selects — so the
        // duration plan has to scale the dwells down to fit the film. That
        // squeeze is what produced sub-second slots. (Four stops is the sample
        // route's limit.)
        let trip = sampleTrip(photoCounts: [8, 8, 8, 8], config: export)
        let lats = trip.route.map { $0.lat }, lons = trip.route.map { $0.lon }
        let line = try XCTUnwrap(LinearTimeline(
            trip: trip, config: export,
            establishing: RecapBounds(
                minLat: lats.min()!, minLon: lons.min()!, maxLat: lats.max()!, maxLon: lons.max()!
            )
        ))

        let durations = photoDurations(line, fps: export.fps)
        let shortest = durations.min() ?? 0
        XCTAssertFalse(durations.isEmpty, "the fixture must actually show photos")
        XCTAssertGreaterThanOrEqual(
            shortest, export.deckPhotoMinHoldS - 2.0 / Double(export.fps),
            "a photo was on screen for \(shortest)s — the floor is \(export.deckPhotoMinHoldS)s"
        )
    }
}

import KamomeConfig
import KamomeExportEngine
import XCTest

/// The linear timeline's stop choreography: a stop's deck window is a
/// zoom-in → hold → zoom-out envelope shared by the camera dolly and the photo
/// deck, so the map "zooms into" the stop exactly while the photos are up.
final class LinearTimelineTests: XCTestCase {
    private func exportConfig(
        targetDurationS: Double = 30,
        deckZoomS: Double = 0.5,
        deckPhotoHoldS: Double = 0.8,
        deckSpanM: Double = 600,
        cameraSpanM: Double = 1500
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: 1080, frameHeightPx: 1920,
            cameraSpanM: cameraSpanM, wideSpanPadding: 1.15, zoomTransitionS: 0.8, followHeadingUp: false,
            deckPhotoHoldS: deckPhotoHoldS, deckZoomS: deckZoomS, deckSpanM: deckSpanM, deckLabelLeadS: 0.6,
            keyframeIntervalFrames: 15, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5
        )
    }

    /// A wandering route with `photoCounts.count` stops spaced along it; each
    /// stop's dwell is photo-count-driven (`RecapDeck.dwellS`).
    private func sampleTrip(photoCounts: [Int], config: TrackingConfig.Export) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        let deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
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

    private func activePhotoDeck(_ contents: [OverlayContent]) -> RecapPhotoDeck? {
        for content in contents {
            if case let .photoDeck(deck) = content { return deck }
        }
        return nil
    }

    private func hasStopLabel(_ contents: [OverlayContent], name: String) -> Bool {
        contents.contains {
            if case let .stopLabel(labelName, _, _, _) = $0 { return labelName == name }
            return false
        }
    }

    private func firstTime(
        _ timeline: LinearTimeline, dt: Double = 1.0 / 30, where predicate: ([OverlayContent]) -> Bool
    ) -> Double? {
        var time = 0.0
        while time <= timeline.durationS {
            if predicate(timeline.overlayContents(atTime: time)) { return time }
            time += dt
        }
        return nil
    }

    private struct DeckSample {
        let time: Double
        let reveal: Double
        let opacity: Double
        let spanM: Double
        let focus: Int
    }

    /// Fine-samples the deck window for the stop whose photos start with `firstRef`.
    private func deckWindow(
        _ timeline: LinearTimeline, firstRef: PhotoRef, dt: Double = 1.0 / 30
    ) -> [DeckSample] {
        var samples: [DeckSample] = []
        var time = 0.0
        while time <= timeline.durationS {
            if let deck = activePhotoDeck(timeline.overlayContents(atTime: time)), deck.photos.first == firstRef {
                samples.append(DeckSample(
                    time: time, reveal: deck.reveal, opacity: deck.opacity,
                    spanM: timeline.cameraFrame(atTime: time).spanM, focus: deck.focusIndex
                ))
            }
            time += dt
        }
        return samples
    }

    func testStopSceneIsZoomInHoldZoomOutSyncedWithCameraDolly() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))

        // The middle stop has 4 photos → dwell = 2·0.5 + 4·0.8 = 4.2 s.
        let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first))
        XCTAssertFalse(window.isEmpty, "the deck must be present through the stop")
        let start = try XCTUnwrap(window.first), end = try XCTUnwrap(window.last)
        XCTAssertEqual(end.time - start.time, 4.2, accuracy: 0.1, "dwell = 2·deckZoomS + n·deckPhotoHoldS")

        // Edges: card barely present, camera at the follow span.
        XCTAssertLessThan(start.opacity, 0.2)
        XCTAssertGreaterThan(start.spanM, 1400, "camera at the follow span before the dolly-in")
        XCTAssertLessThan(end.opacity, 0.2)

        // Middle (the hold): card solid, camera dollied to deckSpanM.
        let mid = window[window.count / 2]
        XCTAssertEqual(mid.opacity, 1, accuracy: 0.01)
        XCTAssertEqual(mid.spanM, config.deckSpanM, accuracy: 5, "camera dolled into the stop while the deck holds")

        // Focus rotates across all four photos.
        XCTAssertEqual(window.map(\.focus).min(), 0, "highlight leads")
        XCTAssertEqual(window.map(\.focus).max(), 3, "reaches the last photo")
    }

    func testStopLabelLeadsBeforeThePhotoDeck() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))

        // Two beats: the stop label lands first, the deck blooms deck_label_lead_s later.
        let labelStart = try XCTUnwrap(firstTime(timeline) { self.hasStopLabel($0, name: "Stop 2") })
        let deckStart = try XCTUnwrap(deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first)).first).time
        XCTAssertEqual(deckStart - labelStart, config.deckLabelLeadS, accuracy: 0.05, "label leads the deck by the lead time")

        // Mid-lead: the label is up but the photos have not arrived yet.
        let midLead = labelStart + config.deckLabelLeadS / 2
        XCTAssertTrue(hasStopLabel(timeline.overlayContents(atTime: midLead), name: "Stop 2"))
        XCTAssertNil(activePhotoDeck(timeline.overlayContents(atTime: midLead)), "no deck during the label lead")
        XCTAssertEqual(timeline.cameraFrame(atTime: midLead).spanM, config.cameraSpanM, accuracy: 1, "no dolly during the lead")
    }

    /// The card's scale envelope and the map's dolly are **synchronized but not
    /// the same curve** (Chiu 2026-07-25): the camera reaches its tight span over
    /// `deck_zoom_s` and then holds, while the photo keeps opening across the
    /// whole hold. One value driving both is exactly what this forbids.
    func testDeckRevealKeepsOpeningAfterTheCameraDollyHasSettled() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first))

        // The instant the camera first sits at its tight span, the card is still
        // well short of fully open — the reveal outlasts the dolly.
        let settled = try XCTUnwrap(
            window.first { abs($0.spanM - config.deckSpanM) < 5 }, "the camera must reach deck_span_m"
        )
        XCTAssertLessThan(settled.reveal, 0.6, "the card is still opening once the map has finished dollying")

        // And it does finish opening, later, while the camera is still parked.
        let opened = try XCTUnwrap(window.last { $0.opacity > 0.99 })
        XCTAssertGreaterThan(opened.reveal, 0.9, "the card reaches full size before the shot pulls out")
        XCTAssertEqual(opened.spanM, config.deckSpanM, accuracy: 5, "the map has not moved while it opened")
        XCTAssertGreaterThan(opened.time, settled.time)

        // The reveal only ever grows through the opening, then eases back down.
        let opening = window.filter { $0.time <= opened.time }
        for (before, after) in zip(opening, opening.dropFirst()) {
            XCTAssertGreaterThanOrEqual(after.reveal, before.reveal - 1e-9, "the reveal must not stutter")
        }
        XCTAssertLessThan(try XCTUnwrap(window.last).reveal, 0.5, "the card scales back down as the shot pulls out")
    }

    /// The lead-in label hands the stop's identity to the card: it is solid
    /// through beat 1 and gone once the deck is fully up, so the two never
    /// double-print the stop name.
    func testLeadLabelFadesOutAsTheDeckTakesOver() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let deckStart = try XCTUnwrap(deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first)).first).time

        func labelOpacity(atTime time: Double) -> Double? {
            for content in timeline.overlayContents(atTime: time) {
                if case let .stopLabel(_, _, _, opacity) = content { return opacity }
            }
            return nil
        }

        XCTAssertEqual(labelOpacity(atTime: deckStart - 0.2) ?? 0, 1, accuracy: 0.01, "solid through the lead beat")
        let midFade = labelOpacity(atTime: deckStart + config.deckZoomS / 2) ?? 0
        XCTAssertGreaterThan(midFade, 0.05)
        XCTAssertLessThan(midFade, 0.95, "mid cross-fade with the card")
        XCTAssertNil(labelOpacity(atTime: deckStart + config.deckZoomS + 0.1), "gone once the card owns the name")
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
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
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
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))

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

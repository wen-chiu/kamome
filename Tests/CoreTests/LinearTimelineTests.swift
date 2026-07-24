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
            if case let .stopLabel(labelName, _, _) = $0 { return labelName == name }
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
        let emphasis: Double
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
                    time: time, emphasis: deck.emphasis,
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

        // Edges: deck barely present, camera at the follow span.
        XCTAssertLessThan(start.emphasis, 0.2)
        XCTAssertGreaterThan(start.spanM, 1400, "camera at the follow span before the dolly-in")
        XCTAssertLessThan(end.emphasis, 0.2)

        // Middle (the hold): deck full, camera dollied to deckSpanM.
        let mid = window[window.count / 2]
        XCTAssertEqual(mid.emphasis, 1, accuracy: 0.01)
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

    func testCameraSpanTracksDeckEmphasisMonotonically() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3, 4, 2], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let window = deckWindow(timeline, firstRef: try XCTUnwrap(trip.stops[1].photos.first))

        // Span and emphasis are one envelope: tighter span ⇔ higher emphasis.
        for sample in window {
            let expected = config.cameraSpanM + (config.deckSpanM - config.cameraSpanM) * sample.emphasis
            XCTAssertEqual(sample.spanM, expected, accuracy: 1, "camera dolly is driven by the deck emphasis")
        }
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
                case .stopLabel: return "label"
                case let .photoDeck(deck): return String(format: "deck(f%d,e%.2f)", deck.focusIndex, deck.emphasis)
                case .titleChrome: return "title"
                case .endChrome: return "end"
                }
            }
            print(String(format: "t=%5.2f  span=%6.0f  bear=%3.0f  e=%.2f  f=%@  [%@]",
                         time, camera.spanM, camera.bearing,
                         deck?.emphasis ?? 0, deck.map { "\($0.focusIndex)" } ?? "-", kinds.joined(separator: ", ")))
            time += 0.1
        }
    }
}

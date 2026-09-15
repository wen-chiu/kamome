import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The map credit is a licence obligation on the exported film** (ADR
/// 2026-09-12), and every way it can break breaks silently.
///
/// Nothing in a green suite, a rendered MP4 or a reviewer's eye tells you that
/// one beat of a 90-second film dropped its attribution — which is exactly what
/// the substrate's own burned-in credit does today, and what
/// `RecapOverlayMapCreditDrawing` records in full. So the property is asserted
/// here instead, in the same shape as
/// `LocalizationTests.testAttributionCarriesBothLicenceObligations`: the
/// obligation, never the wording or the layout.
///
/// ⚠️ **These tests read overlay *calls*, not pixels.** A pixel gate over a
/// corner of a frame would fail on every legitimate restyle and teach everyone
/// to raise its tolerance; what has to hold is that the credit is **drawn, on
/// every frame, last**. One test does read a pixel, and its comment says why it
/// has no alternative.
final class RecapMapCreditTests: RecapRenderTestCase {
    /// Records what each frame was asked to draw, in order.
    ///
    /// A spy rather than the real renderer for the reason
    /// `RecapExportCoordinatorTests` gives about its own: the question is what
    /// the pipeline *asked for*, and answering it from the finished bitmap would
    /// make a layout change look like a licence breach.
    private final class RecordingOverlay: OverlayRenderer {
        private(set) var frames: [[OverlayContent]] = []
        private var current: [OverlayContent] = []

        func render(_ content: OverlayContent, camera: CameraFrame, into surface: RenderSurface) {
            current.append(content)
        }

        /// Called from the loop's `deliver`, which runs **after** the frame is
        /// composited — so the bucket closes on exactly the frame that filled it.
        func endFrame() {
            frames.append(current)
            current = []
        }
    }

    /// A substrate that draws nothing but declares an obligation — the whole of
    /// what `MapLibreSnapshotProvider` contributes to this question, without a
    /// network, a style sheet or Metal.
    private struct CreditedProvider: MapRenderer {
        let inner = FlatSnapshotProvider()
        let credit: String?

        var capabilities: MapRendererCapabilities {
            MapRendererCapabilities(
                supportsBearing: false, supportsHeadingUp: false, attribution: credit
            )
        }

        func snapshot(
            _ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int
        ) async throws -> MapSnapshot {
            try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
        }
    }

    /// Repo-root `Config/TrackingConfig.json`, located relative to this source
    /// file — the same helper `ConfigLoaderTests` and `CrossingFramingTests` use.
    /// Read rather than restated because two of these tests are about the
    /// *shipped* numbers, and a copy of them here could go stale while staying
    /// green.
    private func shippedExportConfig() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    /// A whole film's worth of frames, and what each was asked to draw. Every
    /// beat is in here by construction — title card, travel, both stop beats,
    /// end card — because the loop renders all of them.
    private func recordAWholeFilm(credit: String?) async throws -> [[OverlayContent]] {
        // Long enough that the title card, the travel, both stop beats and the
        // end card are all separate frames rather than one blurred beat.
        let config = exportConfig(targetDurationS: 12)
        let trip = makeTrip(
            stops: [StopSpec(routeIndex: 3, name: "First", photos: [.asset("a"), .asset("b")]),
                    StopSpec(routeIndex: 7, name: "Second")],
            config: config
        )
        let timeline = try makeTimeline(trip, config: config)
        let overlay = RecordingOverlay()
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: RecapStyle(), lengthPx: 300),
            overlay: overlay,
            widthPx: widthPx, heightPx: heightPx,
            crossingSubject: nil, flightSubject: nil
        )
        let provider = CreditedProvider(credit: credit)
        let loop = RecapRenderLoop(
            timeline: timeline, compositor: compositor, provider: provider, config: config
        )
        try await loop.renderFrames { _, _ in
            overlay.endFrame()
            return true
        }
        let frames = overlay.frames
        XCTAssertEqual(
            frames.count, timeline.frameCount,
            "every frame of the film must be accounted for, or this gate has a hole in it"
        )
        return frames
    }

    // MARK: - The obligation

    /// **Every frame, and last on every frame.**
    ///
    /// "Last" is how *not covered* is asserted without reading a corner of a
    /// bitmap: nothing the compositor draws after the credit exists, so no
    /// scrim, card, deck or grade can reach it. That is the property the title
    /// band broke for the snapshotter's own copy — it lays a 0.9-alpha scrim
    /// across the bottom 27% of the frame, directly over it.
    func testEveryFrameOfAFilmCarriesTheCreditAndNothingIsDrawnOverIt() async throws {
        let frames = try await recordAWholeFilm(credit: RecapMapAttribution.openFreeMap)
        for (index, contents) in frames.enumerated() {
            let credits = contents.filter { if case .mapCredit = $0 { return true } else { return false } }
            XCTAssertEqual(
                credits.count, 1,
                "frame \(index) drew \(credits.count) map credits — the licence needs exactly one"
            )
            guard case let .mapCredit(text)? = contents.last else {
                return XCTFail(
                    "frame \(index) drew \(String(describing: contents.last)) after the credit — "
                        + "anything drawn later can cover it"
                )
            }
            XCTAssertEqual(text, RecapMapAttribution.openFreeMap, "frame \(index) credited the wrong source")
        }
    }

    /// **A substrate that obliges nothing draws nothing.**
    ///
    /// The other half of the rule, and the one that keeps `CLAUDE.md` rule 5:
    /// stamping an OpenStreetMap credit onto Apple's cartography would be a
    /// false claim about where the picture came from — and would still not cure
    /// Apple's terms, which ADR 2026-09-09 shows attribution cannot reach.
    ///
    /// It is also what keeps the golden-frame gates byte-identical: they render
    /// over `FlatSnapshotProvider`, which declares none.
    func testAFilmOnASubstrateThatObligesNothingDrawsNoCredit() async throws {
        let frames = try await recordAWholeFilm(credit: nil)
        for (index, contents) in frames.enumerated() {
            XCTAssertFalse(
                contents.contains { if case .mapCredit = $0 { return true } else { return false } },
                "frame \(index) credited a substrate that declared no attribution"
            )
        }
    }

    /// **The credit is drawn after the grade and the vignette.**
    ///
    /// The one test here that reads a pixel, because the atmosphere is a fill
    /// over the finished frame and leaves no call to record. It is a one-bit
    /// read and cannot drift with layout: with a fully opaque grade, a credit
    /// drawn *before* the atmosphere leaves a frame that is uniformly the grade
    /// colour, and a credit drawn after leaves at least one pixel that is not.
    ///
    /// It matters because `modern-minimal` ships `vignetteStrength` 0.42 and the
    /// vignette is strongest in the corners — where the credit lives. A theme
    /// must not be able to dim a licence notice below legibility.
    func testTheCreditIsDrawnOverTheFilmsAtmosphere() async throws {
        let config = exportConfig()
        var style = RecapStyle()
        style.gradeColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let trip = makeTrip(stops: [StopSpec(routeIndex: 5, name: "Stop")], config: config)
        let timeline = try makeTimeline(trip, config: config)
        // Built here rather than through `makeCompositor`, which deliberately
        // leaves the compositor on the neutral style — the golden-frame gates
        // render against no atmosphere at all, and this test needs one.
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style, lengthPx: 300),
            overlay: RecapOverlayRenderer(style: style, resolver: StubResolver { _ in nil }),
            style: style,
            widthPx: widthPx, heightPx: heightPx,
            crossingSubject: nil, flightSubject: nil
        )
        let time = timeline.durationS / 2
        let background = try await background(timeline, at: time, config: config)

        let plain = try compositor.render(atTime: time, background: background, credit: nil)
        let credited = try compositor.render(
            atTime: time, background: background, credit: RecapMapAttribution.openFreeMap
        )
        XCTAssertTrue(
            try isUniformlyBlack(plain),
            "an opaque grade must cover everything drawn before it — otherwise this test proves nothing"
        )
        XCTAssertFalse(
            try isUniformlyBlack(credited),
            "the credit was swallowed by the grade — it must be drawn after drawAtmosphere"
        )
    }

    private func isUniformlyBlack(_ image: CGImage) throws -> Bool {
        let black = RGB(red: 0, green: 0, blue: 0)
        for row in 0..<image.height {
            for col in 0..<image.width where try pixel(image, col: col, row: row) != black {
                return false
            }
        }
        return true
    }

    // MARK: - The strings

    /// **The ODbL clause is in every credit Kamome can draw**, and the
    /// OpenFreeMap line is asserted verbatim for the same reason
    /// `attribution_geoapify` is: the required thing is the format, so a
    /// well-meaning edit would break the obligation while looking tidier.
    func testEveryCreditNamesOpenStreetMap() {
        for credit in [RecapMapAttribution.openFreeMap, RecapMapAttribution.openStreetMap] {
            XCTAssertTrue(
                credit.contains("OpenStreetMap"),
                "ODbL attribution is not optional: \(credit)"
            )
        }
        XCTAssertEqual(
            RecapMapAttribution.openFreeMap, "OpenFreeMap © OpenMapTiles Data from OpenStreetMap",
            "this is the format openfreemap.org asks for (VERIFIED 2026-09-09)"
        )
    }

    /// **Apple's substrate declares none, and that is a decision.**
    /// ADR 2026-09-09: attribution cannot cure Attachment 6 §2.3 / §2.5, and an
    /// OSM credit over Apple cartography would be a false provenance claim.
    func testTheAppleSubstrateDeclaresNoAttribution() {
        for appearance in RecapAppearance.allCases {
            XCTAssertNil(
                MapKitSnapshotProvider(appearance: appearance).capabilities.attribution,
                "a map credit must never be drawn over Apple's tiles"
            )
        }
    }

    // MARK: - The two measurements this design rests on

    /// **The credit has to survive the GIF.**
    ///
    /// Every export surface composites the same frame and the GIF then scales it
    /// to `export.gif_width_px` — so a credit sized for the MP4 alone can arrive
    /// illegible in the other file the app writes. The floor is set against the
    /// thing this change replaced: the snapshotter's burned-in copy measured
    /// **11 px** tall at 1080, i.e. ~5 px once scaled, which is why it could not
    /// be the film's credit either.
    func testTheCreditStaysLegibleAfterTheGifDownscale() throws {
        let config = try shippedExportConfig()
        let scaled = RecapStyle().mapCredit.fontPx
            * CGFloat(config.gifWidthPx) / CGFloat(config.frameWidthPx)
        XCTAssertGreaterThanOrEqual(
            scaled, 10,
            "at \(config.gifWidthPx)/\(config.frameWidthPx) the credit renders \(scaled) px in the GIF"
        )
    }

    /// **Why the film draws its own instead of keeping the snapshotter's.**
    ///
    /// `MLNMapSnapshotter` burns its credit into the image's bottom-right —
    /// measured on the evaluation artifacts at x 709…1059, y 1896…1906 of a
    /// 1080×1920 frame. The render loop then *reprojects* that image onto a run
    /// of frames (`RecapSnapshotStations`), and this asserts the consequence: at
    /// the shipped station padding the credit's own top row is already below the
    /// frame's bottom edge, so it is not in the film at all.
    ///
    /// ⚠️ If this ever fails, crop-scaling changed — it does **not** mean the
    /// snapshotter's credit became usable. Re-measure before concluding
    /// anything (`RecapOverlayMapCreditDrawing` names the other two reasons,
    /// neither of which this test covers).
    func testCropScalingPutsTheSnapshottersOwnCreditOutsideTheFrame() async throws {
        let config = try shippedExportConfig()
        let widthPx = config.frameWidthPx, heightPx = config.frameHeightPx
        // The station is the frame's own camera widened by the padding a station
        // pays the moment it unions two framings — every travelling frame.
        let target = CameraFrame(centerLat: 64.1466, centerLon: -21.9426, spanM: 86_500, bearing: 0)
        let station = CameraFrame(
            centerLat: target.centerLat, centerLon: target.centerLon,
            spanM: target.spanM * config.snapshotStationPadding, bearing: 0
        )
        let snapshot = try await FlatSnapshotProvider().snapshot(
            station, map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        let reprojection = try SnapshotReprojection(
            station: snapshot, stationCamera: station, target: target,
            widthPx: widthPx, heightPx: heightPx
        )
        // The top-left corner of the burned-in credit's glyph box, measured.
        let credit = reprojection.map(CGPoint(x: 709, y: 1896))
        XCTAssertGreaterThan(
            credit.y, Double(heightPx),
            "the snapshotter's credit is still inside the frame at padding "
                + "\(config.snapshotStationPadding) — re-measure before relying on it"
        )
    }

}

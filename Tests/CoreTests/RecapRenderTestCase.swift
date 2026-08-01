import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Shared harness for the §4.5 golden-frame gates, on the render-layers pipeline
/// (`RecapTrip` → `LinearTimeline` → `FrameCompositor` over the deterministic
/// `FlatSnapshotProvider`): a 1 km straight meridian route rendered into a small
/// 216×384 frame (1080×1920 ÷ 5), plus pixel probes for composition assertions.
/// Subclasses hold the actual tests (RecapFrameTests, RecapChromeTests,
/// RecapOverlayRendererTests).
class RecapRenderTestCase: XCTestCase {
    struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    /// A `RecapPhotoResolving` stub: refs → bitmaps via a closure, so a deck
    /// test can give each photo a distinct color and probe which one shows.
    struct StubResolver: RecapPhotoResolving {
        let provide: (PhotoRef) -> CGImage?
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { provide(ref) }
    }

    /// One stop in a test trip, anchored to a route vertex.
    struct StopSpec {
        let routeIndex: Int
        let name: String
        let detail: String?
        let photos: [PhotoRef]

        init(routeIndex: Int, name: String = "Stop", detail: String? = nil, photos: [PhotoRef] = []) {
            self.routeIndex = routeIndex
            self.name = name
            self.detail = detail
            self.photos = photos
        }
    }

    let route: [RecapCoordinate] = (0...10).map {
        RecapCoordinate(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    let widthPx = 216
    let heightPx = 384

    // Style colors as 8-bit sRGB, for pixel assertions.
    let routeRGB = RGB(red: 33, green: 115, blue: 242)
    let backgroundRGB = RGB(red: 237, green: 237, blue: 232)
    let cardRGB = RGB(red: 255, green: 255, blue: 255)

    /// Half the drawn vehicle length in this frame's pixels — probes that want
    /// bare map (or trail) must clear it.
    var vehicleHalfPx: Int {
        Int(RecapStyle().subjectLengthPx * CGFloat(widthPx) / 1080 / 2)
    }

    /// Is this pixel the car's paintwork? The sprite is illustrated artwork, so
    /// tests assert the *hue* (red-dominant) over a region rather than any exact
    /// tone — the sprite's own center is windshield glass, and pinning exact
    /// pixels would make every art change a false failure.
    func isVehiclePaint(_ sample: RGB) -> Bool {
        sample.red > 90 && sample.red > sample.green + 45 && sample.red > sample.blue + 45
    }

    /// How many of the car's painted pixels appear within `radius` of a point.
    func vehiclePaintCount(_ image: CGImage, aroundCol col: Int, row: Int, radius: Int) throws -> Int {
        var count = 0
        for probeRow in max(row - radius, 0)..<min(row + radius, image.height) {
            for probeCol in max(col - radius, 0)..<min(col + radius, image.width)
            where isVehiclePaint(try pixel(image, col: probeCol, row: probeRow)) {
                count += 1
            }
        }
        return count
    }

    func assertVehiclePresent(
        _ image: CGImage, col: Int, row: Int, radius: Int? = nil, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let count = try vehiclePaintCount(image, aroundCol: col, row: row, radius: radius ?? vehicleHalfPx)
        XCTAssertGreaterThan(count, 20, "\(label): no vehicle paint near (\(col),\(row))", file: file, line: line)
    }

    func exportConfig(
        targetDurationS: Double = 6,
        fps: Int = 10,
        keyframeIntervalFrames: Int = 15,
        followHeadingUp: Bool = false
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: widthPx, frameHeightPx: heightPx,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, actSplitKm: 25, followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7, cameraSafeZoneFraction: 0.8,
            cameraResponsiveness: 6.0, endRevealS: 2.5,
            deckPhotoHoldS: 0.8, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 1.0, openingRegionalS: 1.0, countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
            keyframeIntervalFrames: keyframeIntervalFrames,
            titleCardS: 1, endCardS: 1, videoBitrateMbps: 5
        )
    }

    /// Chrome panels at full opacity so their pixels are exactly white
    /// regardless of the background under them.
    var opaqueCardStyle: RecapStyle {
        var style = RecapStyle()
        style.cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        return style
    }

    // MARK: - Pipeline construction

    /// A style-independent test trip from route vertices + stop specs. Each
    /// stop's dwell is photo-count-driven (`RecapDeck.dwellS`) when it has
    /// photos, else the uniform `stop_hold_s` (matches RecapComposer).
    func makeTrip(
        route: [RecapCoordinate]? = nil,
        legs: [RecapTrip.Leg]? = nil,
        stops: [StopSpec] = [],
        title: String = "Trip",
        subtitle: String = "Subtitle",
        statsLines: [String] = ["1 km · 1 stop"],
        callToAction: String = "Record your own journey",
        shareURL: String? = nil,
        config: TrackingConfig.Export
    ) -> RecapTrip {
        let coords = legs.map { $0.flatMap(\.coordinates) } ?? route ?? self.route
        let deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
        let tripStops = stops.map { spec in
            RecapTrip.Stop(
                coordinate: coords[spec.routeIndex], name: spec.name, dayLabel: "Day 1",
                detail: spec.detail, photos: spec.photos,
                dwellS: spec.photos.isEmpty ? config.stopHoldS : deck.dwellS(photoCount: spec.photos.count)
            )
        }
        return RecapTrip(
            legs: legs ?? [RecapTrip.Leg(coordinates: coords, mode: .drive, provenance: .recorded)],
            stops: tripStops, title: title, subtitle: subtitle,
            statsLines: statsLines, callToAction: callToAction, shareURL: shareURL
        )
    }

    func makeTimeline(_ trip: RecapTrip, config: TrackingConfig.Export) throws -> LinearTimeline {
        try XCTUnwrap(LinearTimeline(trip: trip, config: config))
    }

    /// A compositor over the subject + overlay renderers, on the shipped north-up
    /// map. `resolver` supplies deck bitmaps; the default returns none (route /
    /// label / chrome tests need no photos).
    func makeCompositor(
        _ timeline: LinearTimeline,
        style: RecapStyle? = nil,
        resolver: RecapPhotoResolving? = nil
    ) -> FrameCompositor {
        let style = style ?? opaqueCardStyle
        return FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: resolver ?? StubResolver { _ in nil }),
            widthPx: widthPx, heightPx: heightPx
        )
    }

    /// The keyframe background at `time`: a single snapshot taken at the
    /// timeline's own `cameraFrame` (blend 1), the flat provider for determinism.
    func background(
        _ timeline: LinearTimeline, at time: Double, config: TrackingConfig.Export,
        provider: FlatSnapshotProvider = FlatSnapshotProvider()
    ) async throws -> RecapBackground {
        let frame = timeline.cameraFrame(atTime: time)
        let snapshot = try await provider.snapshot(
            CameraFrame(centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: frame.bearing),
            map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        return RecapBackground(current: snapshot)
    }

    /// Renders the frame at `time` over the timeline's own keyframe background.
    func renderFrame(
        _ timeline: LinearTimeline, _ compositor: FrameCompositor, at time: Double, config: TrackingConfig.Export
    ) async throws -> CGImage {
        try compositor.render(atTime: time, background: try await background(timeline, at: time, config: config))
    }

    // MARK: - Timeline scanning helpers

    func activePhotoDeck(_ contents: [OverlayContent]) -> RecapPhotoDeck? {
        for content in contents {
            if case let .photoDeck(deck) = content { return deck }
        }
        return nil
    }

    func hasStopLabel(_ contents: [OverlayContent]) -> Bool {
        contents.contains {
            if case .stopLabel = $0 { return true }
            return false
        }
    }

    // MARK: - Test images

    /// A solid-color test photo for deck rendering — distinct fills let a pixel
    /// probe tell which photo the deck is showing.
    func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat, side: Int = 16) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try XCTUnwrap(context.makeImage())
    }

    // MARK: - Pixel probes

    func pixels(_ image: CGImage) throws -> (data: CFData, bytesPerRow: Int) {
        let data = try XCTUnwrap(image.dataProvider?.data)
        return (data, image.bytesPerRow)
    }

    func pixel(_ image: CGImage, col: Int, row: Int) throws -> RGB {
        let (data, bytesPerRow) = try pixels(image)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let offset = row * bytesPerRow + col * 4
        return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    func assertPixel(
        _ image: CGImage,
        col: Int,
        row: Int,
        is expected: RGB,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try pixel(image, col: col, row: row)
        for (component, want) in [(actual.red, expected.red), (actual.green, expected.green), (actual.blue, expected.blue)] {
            XCTAssertEqual(
                component, want, accuracy: 3,
                "\(label) at (\(col),\(row)): got \(actual), expected \(expected)", file: file, line: line
            )
        }
    }

    func colorCount(_ image: CGImage, matching target: RGB) throws -> Int {
        let (data, bytesPerRow) = try pixels(image)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var count = 0
        for row in 0..<image.height {
            for col in 0..<image.width {
                let offset = row * bytesPerRow + col * 4
                if abs(Int(bytes[offset]) - target.red) <= 3,
                   abs(Int(bytes[offset + 1]) - target.green) <= 3,
                   abs(Int(bytes[offset + 2]) - target.blue) <= 3 {
                    count += 1
                }
            }
        }
        return count
    }
}

/// Counts provider hits so the keyframe cache is provably doing its job.
/// Lock-guarded: the render loop prefetches snapshots concurrently.
final class CountingProvider: MapRenderer {
    private let inner = FlatSnapshotProvider()
    private let lock = NSLock()
    private var count = 0

    var capabilities: MapRendererCapabilities { inner.capabilities }

    var requestCount: Int {
        lock.withLock { count }
    }

    func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        lock.withLock { count += 1 }
        return try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
    }
}

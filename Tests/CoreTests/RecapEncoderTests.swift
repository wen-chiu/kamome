import AVFoundation
import CoreGraphics
import ImageIO
import KamomeConfig
import KamomeExportEngine
import XCTest

/// §4.5 step 5 gate: the encoders turn the deterministic frame stream into a
/// real MP4 and GIF with the promised duration, size, and frame decimation.
final class RecapEncoderTests: XCTestCase {
    private let route: [RecapCoordinate] = (0...10).map {
        RecapCoordinate(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    /// 2 s × 10 fps = 20 frames; GIF at 5 fps → stride 2 → 10 GIF frames.
    private func exportConfig() -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 2, fps: 10, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 5, gifWidthPx: 108, frameWidthPx: 216, frameHeightPx: 384,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, actSplitKm: 25,
            crossingBeatS: 6.0, crossingApexPadding: 1.5, followHeadingUp: false,
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7, cameraSafeZoneFraction: 0.8,
            cameraResponsiveness: 6.0, endRevealS: 2.5, endRevealPadding: 1.9, endCardStyle: "full",
            deckPhotoHoldS: 0.8, deckPhotoMinHoldS: 0.2, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 1.0, openingRegionalS: 1.0, countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
            keyframeIntervalFrames: 5,
            snapshotStationMaxMagnification: 1.5,
            snapshotStationPadding: 1.03,
            crossingFlightMaxLongitudeDeg: 70,
            subjectLengthPx: 300, titleCardS: 0.4, endCardS: 0.4, videoBitrateMbps: 5,
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

    private func makeExporter(config: TrackingConfig.Export) throws -> (exporter: RecapExporter, frameCount: Int) {
        let stop = RecapTrip.Stop(
            coordinate: route[5], name: "Stop", dayLabel: "Day 1", detail: nil, photos: [], dwellS: config.stopHoldS
        )
        let trip = RecapTrip(
            route: route, stops: [stop], title: "Trip", subtitle: "Sub",
            statsLines: [], callToAction: "", shareURL: "kamome://route/test"
        )
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config, pacing: .fixed(totalS: config.targetDurationS)))
        let style = RecapStyle()
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style, config: config),
            overlay: RecapOverlayRenderer(style: style, resolver: NoPhotoResolver()),
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx
        )
        let exporter = RecapExporter(
            timeline: timeline, compositor: compositor, provider: FlatSnapshotProvider(), config: config
        )
        return (exporter, timeline.frameCount)
    }

    private func scratchURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recap-encoder-tests-\(UUID().uuidString)-\(name)")
    }

    func testExportProducesMP4WithTargetDurationAndFrameSize() async throws {
        let config = exportConfig()
        let (exporter, _) = try makeExporter(config: config)
        let videoURL = scratchURL("recap.mp4")
        defer { try? FileManager.default.removeItem(at: videoURL) }

        var lastProgress = 0.0
        let output = try await exporter.export(videoURL: videoURL, progress: { lastProgress = $0 })

        XCTAssertNotNil(output)
        XCTAssertEqual(lastProgress, 1.0, accuracy: 1e-9)
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, config.targetDurationS, accuracy: 0.05)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(Int(size.width), config.frameWidthPx)
        XCTAssertEqual(Int(size.height), config.frameHeightPx)
    }

    func testExportProducesDecimatedScaledGIF() async throws {
        let config = exportConfig()
        let (exporter, frameCount) = try makeExporter(config: config)
        let videoURL = scratchURL("recap.mp4")
        let gifURL = scratchURL("recap.gif")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: gifURL)
        }

        let output = try await exporter.export(videoURL: videoURL, gifURL: gifURL)

        XCTAssertEqual(output?.gifURL, gifURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gifURL as CFURL, nil))
        // fps 10 → gif 5 fps → every 2nd of 20 frames.
        XCTAssertEqual(CGImageSourceGetCount(source), frameCount / 2)
        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(first.width, config.gifWidthPx)
        XCTAssertEqual(first.height, 192, "aspect ratio should survive the downscale")
        // Real-time playback: stride 2 at 10 fps → 0.2 s per GIF frame.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gifProperties = try XCTUnwrap(properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        let delay = try XCTUnwrap(gifProperties[kCGImagePropertyGIFDelayTime] as? Double)
        XCTAssertEqual(delay, 0.2, accuracy: 1e-6)
    }

    func testCancelledExportReturnsNilAndStopsRendering() async throws {
        let config = exportConfig()
        let (exporter, _) = try makeExporter(config: config)
        let videoURL = scratchURL("recap.mp4")
        defer { try? FileManager.default.removeItem(at: videoURL) }

        var framesSeen = 0
        let output = try await exporter.export(
            videoURL: videoURL,
            progress: { _ in framesSeen += 1 },
            shouldContinue: { framesSeen < 5 }
        )

        XCTAssertNil(output, "cancelled export must not report success")
        XCTAssertEqual(framesSeen, 5, "rendering should stop right after cancellation")
    }
}

/// The encoder gates render a route-only trip; no deck photos to resolve.
private struct NoPhotoResolver: RecapPhotoResolving {
    func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
}

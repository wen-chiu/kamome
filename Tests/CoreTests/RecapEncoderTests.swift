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
    private func exportConfig(pipeline: TrackingConfig.ExportPipeline = .handBuilt) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 2, fps: 10, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 5, gifWidthPx: 108, frameWidthPx: 216, frameHeightPx: 384,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, actSplitKm: 25,
            crossingBeatS: 4.0, crossingApexPadding: 1.5, followHeadingUp: false,
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
            recapMode: .highlight, pipeline: pipeline
        )
    }

    private func makeExporter(
        config: TrackingConfig.Export, provider: MapRenderer = FlatSnapshotProvider()
    ) throws -> (exporter: RecapExporter, frameCount: Int) {
        let stop = RecapTrip.Stop(
            coordinate: route[5], name: "Stop", dayLabel: "Day 1", detail: nil, photos: [], dwellS: config.stopHoldS
        )
        let trip = RecapTrip(
            route: route, stops: [stop], title: "Trip", subtitle: "Sub",
            endCardFigures: [], shareURL: "kamome://route/test"
        )
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config, pacing: .fixed(totalS: config.targetDurationS)))
        let style = RecapStyle()
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style, config: config),
            overlay: RecapOverlayRenderer(style: style, resolver: NoPhotoResolver()),
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx,
            // No crossing in this fixture, so neither is ever asked for.
            // Written out because `FrameCompositor` has no defaults: a silent nil
            // is what drew a car across the Pacific for a round (2026-09-04).
            crossingSubject: nil, flightSubject: nil
        )
        let exporter = RecapExporter(
            timeline: timeline, compositor: compositor, provider: provider, config: config
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

    /// A GIF-only export renders only the frames the GIF keeps and writes no
    /// MP4 — and the GIF it writes is the one the two-encoder pass wrote.
    func testGIFOnlyExportMatchesTheTwoEncoderGIF() async throws {
        let config = exportConfig()
        let (exporter, frameCount) = try makeExporter(config: config)
        let videoURL = scratchURL("recap.mp4")
        let bothGIF = scratchURL("both.gif")
        let onlyGIF = scratchURL("only.gif")
        defer {
            [videoURL, bothGIF, onlyGIF].forEach { try? FileManager.default.removeItem(at: $0) }
        }

        _ = try await exporter.export(videoURL: videoURL, gifURL: bothGIF)
        var progressCalls = 0
        var lastProgress = 0.0
        let output = try await exporter.exportGIF(gifURL: onlyGIF, progress: {
            progressCalls += 1
            lastProgress = $0
        })

        XCTAssertNil(output?.videoURL)
        XCTAssertEqual(output?.gifURL, onlyGIF)
        // fps 10 → gif 5 fps → stride 2: half the frames are never composited.
        XCTAssertEqual(output?.stats.frames, frameCount / 2)
        XCTAssertEqual(lastProgress, 1, "progress must finish even when the last frame is skipped")
        XCTAssertEqual(progressCalls, frameCount / 2 + 1)
        let both = try XCTUnwrap(CGImageSourceCreateWithURL(bothGIF as CFURL, nil))
        let only = try XCTUnwrap(CGImageSourceCreateWithURL(onlyGIF as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(only), CGImageSourceGetCount(both))
        for index in 0..<CGImageSourceGetCount(both) {
            let expected = try XCTUnwrap(CGImageSourceCreateImageAtIndex(both, index, nil))
            let actual = try XCTUnwrap(CGImageSourceCreateImageAtIndex(only, index, nil))
            XCTAssertEqual(
                actual.dataProvider?.data as Data?, expected.dataProvider?.data as Data?,
                "GIF frame \(index) must be the frame the two-encoder pass wrote"
            )
        }
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

    /// **A writer that has stopped writing never becomes ready again**, so an
    /// append that only waits for readiness spins forever: Cancel cannot reach
    /// it (the flag is read between frames), the coordinator never clears its
    /// run, and every later export is refused until the process dies
    /// (`Docs/handoff-arch-review-2026-09-24.md` P0-1). The failure must come
    /// back as an error instead. Run on a plain thread with a deadline so the
    /// regression fails this test rather than hanging the suite.
    func testAppendAfterTheWriterStoppedThrowsInsteadOfWaitingForever() throws {
        let videoURL = scratchURL("stopped.mp4")
        defer { try? FileManager.default.removeItem(at: videoURL) }
        let encoder = try RecapVideoEncoder(outputURL: videoURL, widthPx: 64, heightPx: 64, fps: 10, bitrateMbps: 1)
        let image = try XCTUnwrap(Self.blankImage(widthPx: 64, heightPx: 64))
        try encoder.append(image, frame: 0)
        encoder.cancel()

        let returned = expectation(description: "append returned")
        let failure = LockedBox<Error?>(nil)
        Thread.detachNewThread {
            do { try encoder.append(image, frame: 1) } catch { failure.value = error }
            returned.fulfill()
        }
        wait(for: [returned], timeout: 5)
        XCTAssertNotNil(failure.value, "an append to a writer that stopped writing must throw")
    }

    /// **A snapshot that never answers fails the export instead of holding it**
    /// (arch review 2026-09-24, P1-10). Before `snapshot_timeout_s` the render
    /// waited forever, and Cancel — read between frames — could not reach it.
    func testASnapshotThatNeverAnswersFailsTheExportWithinItsDeadline() async throws {
        let config = exportConfig(pipeline: TrackingConfig.ExportPipeline(
            prefetchDepth: 2, compositeConcurrency: 2, snapshotTimeoutS: 0.3, mapCacheMb: 1
        ))
        let (exporter, _) = try makeExporter(config: config, provider: SilentProvider())
        let videoURL = scratchURL("silent.mp4")
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let started = ContinuousClock.now
        do {
            _ = try await exporter.export(videoURL: videoURL)
            XCTFail("an export whose map never answers must not succeed")
        } catch is SnapshotTimeout {
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(10), "the deadline did not bound the wait")
        }
    }

    private static func blankImage(widthPx: Int, heightPx: Int) -> CGImage? {
        CGContext(
            data: nil, width: widthPx, height: heightPx, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )?.makeImage()
    }
}

/// A value two threads hand over — the test's thread writes, the test reads
/// after the expectation, and the lock makes that ordering explicit.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// A substrate whose snapshot never completes — a callback that never fires.
private struct SilentProvider: MapRenderer {
    var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(supportsBearing: false, supportsHeadingUp: false)
    }

    func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        try await withCheckedThrowingContinuation { (_: CheckedContinuation<MapSnapshot, Error>) in }
    }
}

/// The encoder gates render a route-only trip; no deck photos to resolve.
private struct NoPhotoResolver: RecapPhotoResolving {
    func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
}

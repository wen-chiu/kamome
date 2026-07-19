import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Manual §4.5 gates, skipped unless their env var is set — they take real
/// wall time (and the demo needs Apple Maps tiles), so CI never pays for
/// them. Run with `TEST_RUNNER_<VAR>=1` on the xcodebuild command line:
///
///   KAMOME_RENDER_BENCH=1 → full-resolution render-budget measurement
///   KAMOME_DEMO_RENDER=1  → Phase 3 demo artifact (MP4 + GIF, real map)
///
/// The simulator numbers are proxies; the §4.5 bar (< 90 s, 8-day trip) is
/// judged on the physical device via S5's on-screen render-time readout.
final class RecapBudgetAndDemoTests: XCTestCase {
    /// 8-day-scale synthetic trip, post-simplification size: ~5,000 route
    /// vertices and 24 stops is what a 1,200 km drive leaves after the ε=15 m
    /// Douglas-Peucker pass (RecapComposer.route).
    private func syntheticLongTrip() -> (route: [CameraPath.Point], stops: [CameraPath.Point]) {
        // A wandering path so nothing collapses to straight lines.
        let route = (0..<5_000).map { index -> CameraPath.Point in
            let t = Double(index)
            return CameraPath.Point(
                lat: -32.0 + t * 0.002 + 0.01 * sin(t / 40),
                lon: 115.75 + 0.01 * cos(t / 55)
            )
        }
        let stops = (1...24).map { route[$0 * 200] }
        return (route, stops)
    }

    private func fullResolutionConfig() throws -> TrackingConfig.Export {
        try GPXReplay.loadConfig().export  // the shipped 1080×1920@30 defaults
    }

    func testRenderBudgetFullResolutionFlatProvider() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_RENDER_BENCH"] == "1",
            "manual benchmark — set TEST_RUNNER_KAMOME_RENDER_BENCH=1"
        )
        let config = try fullResolutionConfig()
        let (route, stops) = syntheticLongTrip()
        let path = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config))
        let events = OverlayTimeline.build(holds: path.holds, config: config, photosEnabled: true)
        let cards = stops.indices.map {
            RecapFrameCompositor.StopCard(name: "Stop \($0 + 1)", dayLabel: "Day \($0 / 3 + 1)")
        }
        let compositor = RecapFrameCompositor(
            path: path,
            events: events,
            stopCards: cards,
            titleCard: .init(title: "Benchmark Trip", subtitle: "8 days · 1,200 km"),
            endCard: .init(
                statsLines: ["1,200 km · 24 stops"],
                callToAction: "Get this route",
                qrCode: RecapQRCode.image(for: "kamome://route/bench", sidePx: 320)
            ),
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx
        )
        let exporter = RecapExporter(
            path: path, compositor: compositor, provider: FlatSnapshotProvider(), config: config
        )
        let videoURL = FileManager.default.temporaryDirectory.appendingPathComponent("bench.mp4")
        let gifURL = FileManager.default.temporaryDirectory.appendingPathComponent("bench.gif")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: gifURL)
        }

        let started = Date.now
        let output = try await exporter.export(videoURL: videoURL, gifURL: gifURL)
        let seconds = Date.now.timeIntervalSince(started)

        XCTAssertNotNil(output)
        let videoMB = Double((try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0) / 1e6
        let gifMB = Double((try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int) ?? 0) / 1e6
        print(String(format: "KAMOME_BENCH pipeline (flat provider, %d frames @ %d×%d): %.1f s — mp4 %.1f MB, gif %.1f MB",
                     path.frameCount, config.frameWidthPx, config.frameHeightPx, seconds, videoMB, gifMB))
    }

    func testMapKitSnapshotLatency() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_RENDER_BENCH"] == "1",
            "manual benchmark — set TEST_RUNNER_KAMOME_RENDER_BENCH=1"
        )
        let config = try fullResolutionConfig()
        let provider = MapKitSnapshotProvider()
        // Warm-up snapshot excluded from the average (tile cache, GeoServices).
        _ = try await provider.snapshot(
            centerLat: -32.0, centerLon: 115.75, spanM: config.cameraSpanM,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let started = Date.now
        let count = 10
        for index in 0..<count {
            _ = try await provider.snapshot(
                centerLat: -32.0 - Double(index) * 0.05, centerLon: 115.75 + Double(index) * 0.03,
                spanM: config.cameraSpanM, widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            )
        }
        let perSnapshot = Date.now.timeIntervalSince(started) / Double(count)
        let keyframes = Double(try XCTUnwrap(CameraPath(
            route: syntheticLongTrip().route, stops: [], config: config
        )).frameCount) / Double(config.keyframeIntervalFrames)
        print(String(format: "KAMOME_BENCH MapKit snapshot: %.2f s each → ~%.0f s for %.0f keyframes",
                     perSnapshot, perSnapshot * keyframes, keyframes))
    }

    /// Phase 3 demo artifact: the perth fixture rendered over real Apple
    /// Maps tiles at full resolution. Copy the printed files to Docs/demos.
    func testRenderDemoArtifact() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_DEMO_RENDER"] == "1",
            "manual demo render — set TEST_RUNNER_KAMOME_DEMO_RENDER=1"
        )
        let config = try fullResolutionConfig()
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let route = engine.segments.flatMap(\.points).map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stops = engine.stops.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let path = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config))
        let events = OverlayTimeline.build(holds: path.holds, config: config, photosEnabled: true)
        // The fixture is the DemoSeeder trip: same stops, same order.
        let names = ["Mandurah", "Bunbury", "Busselton Jetty", "Margaret River"]
        let cards = stops.indices.map { index in
            RecapFrameCompositor.StopCard(
                name: index < names.count ? names[index] : "Stop \(index + 1)",
                dayLabel: "Day 1"
            )
        }
        let compositor = RecapFrameCompositor(
            path: path,
            events: events,
            stopCards: cards,
            titleCard: .init(title: "Perth → Margaret River", subtitle: "Day 1 · 268 km"),
            endCard: .init(
                statsLines: ["268 km · 4 stops", "6.5 h on the road"],
                callToAction: "Get this route",
                qrCode: RecapQRCode.image(for: "kamome://route/demo", sidePx: 320)
            ),
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx
        )
        let exporter = RecapExporter(
            path: path, compositor: compositor, provider: MapKitSnapshotProvider(), config: config
        )
        // Test clones are destroyed after the run, so honor a host output
        // path (simulator doesn't enforce the file sandbox).
        let outBase = ProcessInfo.processInfo.environment["KAMOME_DEMO_OUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let stampDir = outBase.appendingPathComponent("kamome-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: stampDir, withIntermediateDirectories: true)
        let videoURL = stampDir.appendingPathComponent("kamome-p3-recap.mp4")
        let gifURL = stampDir.appendingPathComponent("kamome-p3-recap.gif")

        let started = Date.now
        let output = try await exporter.export(videoURL: videoURL, gifURL: gifURL)
        XCTAssertNotNil(output)
        print(String(format: "KAMOME_DEMO rendered in %.1f s (simulator, real map tiles):", Date.now.timeIntervalSince(started)))
        print("KAMOME_DEMO mp4: \(videoURL.path)")
        print("KAMOME_DEMO gif: \(gifURL.path)")
    }
}

@testable import Kamome
import KamomeExportEngine
import XCTest

/// The readings behind the `render substrate` and `render thermal` log lines
/// (2026-09-25). A diagnostic that reads zero because its hook never fired is
/// worse than no diagnostic, so the MapLibre half is driven through the real
/// snapshotter, not only through the meter.
final class MapSubstrateMeterTests: XCTestCase {
    // MARK: - Meter (pure)

    func testARepeatIsARevalidationOnlyWhenItIsConditional() throws {
        let meter = MapSubstrateMeter()
        let tile = try XCTUnwrap(URL(string: "https://example.invalid/1/2/3.pbf"))
        let other = try XCTUnwrap(URL(string: "https://example.invalid/1/2/4.pbf"))
        meter.requestSent(url: tile, conditional: false)
        meter.requestSent(url: other, conditional: false)
        meter.requestSent(url: tile, conditional: true)
        meter.requestSent(url: other, conditional: false)
        let reading = meter.read()
        XCTAssertEqual(reading.requests, 4)
        XCTAssertEqual(reading.distinctRequests, 2)
        XCTAssertEqual(reading.revalidations, 1)
        XCTAssertEqual(reading.refetches, 1)
    }

    func testAFailedSnapshotIsNotCountedAsZeroCost() {
        let meter = MapSubstrateMeter()
        meter.snapshotStarted()
        meter.snapshotStarted()
        meter.snapshotFinished(totalS: 2, styleS: 0.5, succeeded: true)
        meter.snapshotFinished(totalS: 9, styleS: nil, succeeded: false)
        let reading = meter.read()
        XCTAssertEqual(reading.snapshots, 1)
        XCTAssertEqual(reading.failedSnapshots, 1)
        XCTAssertEqual(reading.meanSnapshotS, 2)
        XCTAssertEqual(reading.meanStyleS, 0.5)
        XCTAssertEqual(reading.peakInFlight, 2)
    }

    func testAStyleThatNeverReportedReadsAsUnknownNotZero() {
        let meter = MapSubstrateMeter()
        meter.snapshotStarted()
        meter.snapshotFinished(totalS: 3, styleS: nil, succeeded: true)
        XCTAssertNil(meter.read().meanStyleS)
    }

    func testResetStartsAnExportFromNothing() throws {
        let meter = MapSubstrateMeter()
        let tile = try XCTUnwrap(URL(string: "https://example.invalid/t.pbf"))
        meter.requestSent(url: tile, conditional: false)
        meter.snapshotStarted()
        meter.reset()
        meter.requestSent(url: tile, conditional: false)
        let reading = meter.read()
        XCTAssertEqual(reading.requests, 1)
        XCTAssertEqual(reading.distinctRequests, 1, "the distinct set must be cleared too")
        XCTAssertEqual(reading.peakInFlight, 0)
    }

    // MARK: - Thermal watch

    func testTheWatchKeepsTheWorstStateAndTheTimeSpentHot() {
        var state = ProcessInfo.ThermalState.fair
        var now = 100.0
        let center = NotificationCenter()
        let watch = ThermalWatch(state: { state }, center: center, clock: { now })
        watch.begin()
        now = 110
        state = .serious
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        now = 140
        state = .fair
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        now = 150
        let reading = watch.end()
        XCTAssertEqual(reading.start, .fair)
        XCTAssertEqual(reading.worst, .serious)
        XCTAssertEqual(reading.end, .fair)
        XCTAssertEqual(reading.hotS, 30, accuracy: 1e-9)
    }

    func testARenderStillHotAtTheEndCountsUpToTheEnd() {
        var now = 0.0
        let watch = ThermalWatch(state: { .critical }, center: NotificationCenter(), clock: { now })
        watch.begin()
        now = 42
        XCTAssertEqual(watch.end().hotS, 42, accuracy: 1e-9)
    }

    // MARK: - MapLibre hooks (real snapshotter, no reachable host)

    #if canImport(MapLibre)
    /// **The hooks fire.** Every host in the style is replaced with a reserved
    /// name that cannot resolve (the `TileFailureTests` technique), so nothing
    /// leaves the machine, yet MapLibre still has to *send* those requests. A
    /// delegate method whose selector missed MapLibre's would compile and leave
    /// `requests` at zero on every device export; this is the test that would
    /// notice.
    @MainActor
    func testTheNetworkHookAndSnapshotTimingSeeARealSnapshot() async throws {
        let error = await MapLibreSnapshotProvider.prepareForExport(cacheMb: 64, coalesce: true, terrainMaxAgeS: 60, tileMemoryMb: 8)
        XCTAssertNil(error, "setting the ambient cache size must succeed")
        let provider = MapLibreSnapshotProvider(
            styleURL: try unresolvableStyle(), attribution: RecapMapAttribution.openFreeMapBase
        )
        let frame = CameraFrame(centerLat: 35.68, centerLon: 139.76, spanM: 20_000, bearing: 0)
        do {
            _ = try await provider.snapshot(frame, map: MapState(), widthPx: 64, heightPx: 64)
            XCTFail("a style whose every host is unresolvable must not produce a snapshot")
        } catch {}
        let reading = MapLibreSnapshotProvider.meter.read()
        XCTAssertGreaterThan(reading.requests, 0, "willSendRequest: never reached the probe")
        XCTAssertEqual(reading.failedSnapshots, 1)
        XCTAssertEqual(reading.peakInFlight, 1)
    }

    /// **Live tiles** — contacts OpenFreeMap and AWS for one tile's worth of
    /// Tokyo, so it is opt-in:
    ///
    ///     TEST_RUNNER_KAMOME_LIVE_TILES=1 xcodebuild -scheme Kamome test \
    ///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    ///       -only-testing:KamomeTests/MapSubstrateMeterTests
    ///
    /// Proves the success path: the style callback fires, and a second
    /// identical snapshot downloads nothing twice — any repeat request is a
    /// revalidation, never a refetch.
    @MainActor
    func testLiveSnapshotsReportStyleTimeAndHitTheCache() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_LIVE_TILES"] == "1",
            "Live network test — set KAMOME_LIVE_TILES=1."
        )
        _ = await MapLibreSnapshotProvider.prepareForExport(cacheMb: 64, coalesce: true, terrainMaxAgeS: 60, tileMemoryMb: 8)
        let provider = MapLibreSnapshotProvider(
            styleURL: try RecapMapStyle.resolvedNetworkStyleURL(styleResource: "openfreemap-liberty-dark"),
            attribution: RecapMapAttribution.openFreeMapBase
        )
        let frame = CameraFrame(centerLat: 35.68, centerLon: 139.76, spanM: 20_000, bearing: 0)
        _ = try await provider.snapshot(frame, map: MapState(), widthPx: 256, heightPx: 256)
        let first = MapLibreSnapshotProvider.meter.read()
        _ = try await provider.snapshot(frame, map: MapState(), widthPx: 256, heightPx: 256)
        let second = MapLibreSnapshotProvider.meter.read()
        print("live substrate: first \(first) · second \(second)")
        XCTAssertNotNil(second.meanStyleS, "didFinishLoadingStyle never reached the timing delegate")
        XCTAssertGreaterThan(first.distinctRequests, 0)
        XCTAssertEqual(second.refetches, 0, "the same snapshot again must not download a tile twice")
    }

    private func unresolvableStyle() throws -> URL {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "openfreemap-liberty-dark", withExtension: "json"))
        let json = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "tiles.openfreemap.org", with: "tiles.unresolvable.invalid")
            .replacingOccurrences(of: "s3.amazonaws.com", with: "s3.unresolvable.invalid")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("kamome-test-meter-unreachable.json")
        try json.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
    #endif
}

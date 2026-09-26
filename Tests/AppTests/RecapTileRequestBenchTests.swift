#if canImport(MapLibre)
import CoreGraphics
import CryptoKit
@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import MapLibre
import XCTest

/// **What one film asks of the tile hosts, and what the snapshots look like**
/// (2026-09-26). The device export of an Iceland film sent **17,216** tile
/// requests for **1,908** distinct tiles, and its snapshots averaged 9.25 s.
/// This bench replays a committed fixture's real station plan through the
/// production provider, the shipped style and the shipped loop, so a fix to the
/// network side can be priced at the desk instead of by an hour on a phone.
///
/// It also **hashes every station snapshot**. A change that is only about
/// *when* a tile arrives must leave every picture byte-identical, and two runs'
/// PNGs are how that is shown rather than asserted: `KAMOME_TILE_BENCH_OUT`
/// writes a run, `KAMOME_TILE_BENCH_COMPARE` diffs this run against one.
///
///     TEST_RUNNER_KAMOME_TILE_BENCH=iceland \
///     TEST_RUNNER_KAMOME_TILE_BENCH_COLD=1 \
///     TEST_RUNNER_KAMOME_TILE_BENCH_OUT=~/Kamome-wt/bench/before \
///     xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:KamomeTests/RecapTileRequestBenchTests
///
/// `KAMOME_TILE_BENCH_LIMIT` renders only the first N stations. `_COLD=1`
/// empties MapLibre's ambient cache first, which is the device's position on a
/// trip it has never exported. Contacts OpenFreeMap and AWS — opt-in only.
final class RecapTileRequestBenchTests: XCTestCase {
    /// Hashes each snapshot the loop is handed, keyed by the camera it was
    /// taken from. Lock-guarded: the loop prefetches concurrently.
    private final class HashingProvider: MapRenderer {
        let inner: MapRenderer
        private let lock = NSLock()
        private(set) var hashes: [String: String] = [:]
        private(set) var images: [String: CGImage] = [:]

        init(inner: MapRenderer) {
            self.inner = inner
        }

        var capabilities: MapRendererCapabilities { inner.capabilities }

        func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
            let snapshot = try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
            let key = Self.digest(Data(
                "\(frame.centerLat)|\(frame.centerLon)|\(frame.spanM)|\(frame.bearing)|\(widthPx)x\(heightPx)".utf8
            ))
            let pixels = Self.digest(Self.bytes(of: snapshot.image))
            lock.withLock {
                hashes[key] = pixels
                images[key] = snapshot.image
            }
            return snapshot
        }

        static func bytes(of image: CGImage) -> Data {
            // Redrawn into one fixed format so the hash is of pixels, not of
            // whatever row padding or byte order the snapshotter chose.
            let width = image.width, height = image.height
            var data = Data(count: width * height * 4)
            data.withUnsafeMutableBytes { raw in
                guard let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return data
        }

        private static func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct NoPhotoResolver: RecapPhotoResolving {
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
    }

    /// `hashes.json` plus one lossless PNG per station, named by camera hash.
    private func write(_ provider: HashingProvider, to directory: URL) throws {
        let pngs = directory.appendingPathComponent("png")
        try FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: provider.hashes, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: directory.appendingPathComponent("hashes.json"))
        for (key, image) in provider.images {
            let url = pngs.appendingPathComponent("\(key).png") as CFURL
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
        }
        print("KAMOME_TILE_BENCH   \(provider.hashes.count) snapshots → \(directory.path)")
    }

    /// **How different is "different"?** For each station both runs share:
    /// the share of pixels whose largest channel difference exceeds 8 of 255
    /// (a change an eye could plausibly see on a flat map area), and the mean
    /// absolute channel difference. Printed as a distribution, because two
    /// runs of the *unchanged* substrate already differ and a fix is judged
    /// against that floor, not against zero.
    private func compare(_ provider: HashingProvider, against directory: URL) throws {
        let visible: UInt8 = 8
        var identical = 0
        var rows: [(share: Double, mean: Double)] = []
        for (key, image) in provider.images {
            let url = directory.appendingPathComponent("png/\(key).png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let reference = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let a = HashingProvider.bytes(of: image), b = HashingProvider.bytes(of: reference)
            guard a.count == b.count else { continue }
            if a == b {
                identical += 1
                rows.append((0, 0))
                continue
            }
            var changed = 0, total = 0
            a.withUnsafeBytes { pa in
                b.withUnsafeBytes { pb in
                    let x = pa.bindMemory(to: UInt8.self), y = pb.bindMemory(to: UInt8.self)
                    var i = 0
                    while i < x.count {
                        var worst: UInt8 = 0
                        for c in 0..<3 {
                            let d = x[i + c] > y[i + c] ? x[i + c] - y[i + c] : y[i + c] - x[i + c]
                            total += Int(d)
                            worst = max(worst, d)
                        }
                        if worst > visible { changed += 1 }
                        i += 4
                    }
                }
            }
            let pixels = Double(a.count / 4)
            rows.append((Double(changed) / pixels, Double(total) / (pixels * 3)))
        }
        let shares = rows.map(\.share).sorted(), means = rows.map(\.mean).sorted()
        func pct(_ values: [Double], _ q: Double) -> Double {
            values.isEmpty ? 0 : values[min(values.count - 1, Int(Double(values.count) * q))]
        }
        print(String(
            format: "KAMOME_TILE_BENCH   vs reference: %d stations compared, %d byte-identical · "
                + "pixels visibly changed median %.4f%% p90 %.4f%% max %.4f%% · mean |Δ| median %.4f max %.4f",
            rows.count, identical, 100 * pct(shares, 0.5), 100 * pct(shares, 0.9), 100 * (shares.last ?? 0),
            pct(means, 0.5), means.last ?? 0
        ))
    }

    @MainActor
    func testTileRequestsAndPixelsForOneFilm() async throws {
        let fixture = try XCTUnwrap(
            HarnessEnv.value("KAMOME_TILE_BENCH") as String?,
            "Measurement harness — set KAMOME_TILE_BENCH to a fixture name (e.g. iceland)."
        )
        let limit = try HarnessEnv.value("KAMOME_TILE_BENCH_LIMIT").map { raw in
            guard let value = Int(raw), value > 0 else {
                throw HarnessError("KAMOME_TILE_BENCH_LIMIT=\(raw) is not a positive integer")
            }
            return value
        }

        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        let mapLibre = MapLibreSnapshotProvider(
            styleURL: try RecapMapStyle.resolvedNetworkStyleURL(styleResource: "openfreemap-liberty-dark"),
            attribution: RecapMapAttribution.openFreeMapBase
        )
        let timeline = try XCTUnwrap(LinearTimeline(
            trip: trip, config: config, establishing: nil,
            substrateMaxLongitudeDeg: mapLibre.capabilities.maxFramableLongitudeDeg
        ))
        let style = RecapStyle.modernMinimal(.dark).withEndCard(config.endCardStyle)
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style, config: config),
            overlay: RecapOverlayRenderer(style: style, resolver: NoPhotoResolver()),
            style: style, widthPx: config.frameWidthPx, heightPx: config.frameHeightPx,
            crossingSubject: VehicleSubjectRenderer.make(
                style: style, config: config, subjectId: VehicleCatalog.crossingSubjectId
            ),
            flightSubject: VehicleSubjectRenderer.make(
                style: style, config: config, subjectId: VehicleCatalog.planeSubjectId
            )
        )
        let provider = HashingProvider(inner: mapLibre)
        let loop = RecapRenderLoop(timeline: timeline, compositor: compositor, provider: provider, config: config)
        let stations = loop.stations
        let used = limit.map { min($0, stations.count) } ?? stations.count
        // One frame per station is composited: the bench is about the map, and
        // a station none of whose frames is wanted is never fetched.
        let wanted = Set(stations.prefix(used).map(\.frames.lowerBound))

        // `KAMOME_TILE_BENCH_FIX=0` is the "before": no coalescing, no terrain
        // lifetime — the network path the export had until 2026-09-26.
        let fix = HarnessEnv.value("KAMOME_TILE_BENCH_FIX") != "0"
        if HarnessEnv.value("KAMOME_TILE_BENCH_COLD") == "1" {
            let error: Error? = await withCheckedContinuation { continuation in
                MLNOfflineStorage.shared.clearAmbientCache { continuation.resume(returning: $0) }
            }
            XCTAssertNil(error, "could not empty the ambient cache for a cold run")
        }
        _ = await MapLibreSnapshotProvider.prepareForExport(
            cacheMb: config.pipeline.mapCacheMb, coalesce: fix && config.pipeline.coalesceTileRequests,
            terrainMaxAgeS: fix ? config.pipeline.terrainMaxAgeS : 0,
            tileMemoryMb: fix ? config.pipeline.tileMemoryMb : 0
        )

        let started = ContinuousClock.now
        let stats = try await loop.renderFrames(only: { wanted.contains($0) }) { _, _ in true }
        let elapsed = ContinuousClock.now - started
        let map = MapLibreSnapshotProvider.meter.read()

        print(String(
            format: "KAMOME_TILE_BENCH %@ — %d of %d stations · %d fetches · %.1f s wall · "
                + "snapshot mean %.2f s · wait %.1f s · peak in flight %d",
            fixture, used, stations.count, stats.fetches,
            Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18,
            map.meanSnapshotS, stats.waitS, map.peakInFlight
        ))
        let hub = TileRequestCoalescer.shared.read()
        print("KAMOME_TILE_BENCH   fix \(fix ? "on" : "off") · downloads \(hub.downloads) · "
              + "joined \(hub.joined) · remembered \(hub.remembered) · terrain aged \(hub.terrainAged)")
        print("KAMOME_TILE_BENCH   requests \(map.requests) / \(map.distinctRequests) distinct · "
              + "\(map.revalidations) revalidated · \(map.refetches) refetched")
        for kind in MapSubstrateMeter.TileKind.allCases {
            let counts = map.counts(kind)
            let gap = counts.medianRepeatGapS.map { String(format: "%.1f s", $0) } ?? "n/a"
            print("KAMOME_TILE_BENCH   \(kind.rawValue): \(counts.requests) requests / \(counts.distinct) distinct · "
                  + "\(counts.revalidations) revalidated · \(counts.refetches) refetched · median repeat gap \(gap)")
        }

        if let out = HarnessEnv.value("KAMOME_TILE_BENCH_OUT") {
            try write(provider, to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
        }
        if let reference = HarnessEnv.value("KAMOME_TILE_BENCH_COMPARE") {
            try compare(provider, against: URL(fileURLWithPath: (reference as NSString).expandingTildeInPath))
        }
        XCTAssertEqual(map.failedSnapshots, 0)
    }
}
#endif

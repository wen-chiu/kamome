import CoreLocation
@testable import Kamome
import KamomeExportEngine
import MapKit
import XCTest

/// **What MapKit actually does with a requested display scale** — measured
/// against the live SDK, because the deterministic half of this seam
/// (`MapKitSnapshotScaleTests`) can only pin Kamome's own arithmetic.
///
/// Written 2026-08-22 after a scale-2 render was refused by the provider's own
/// guard: MapKit returned a 1620x2880px image for the 540x960pt canvas it was
/// given — **3x, the simulator device's native scale, not the 2x requested**.
/// That is the second-order behaviour a scale experiment has to know about, and
/// it is not documented anywhere Kamome controls.
///
/// The question `testPointForAnswersInTheCanvasNotTheImage` settles is the one
/// the whole correction rests on, and it had to be measured rather than reasoned
/// about: if `point(for:)` spoke pixels instead of points, the correction in
/// `MapKitSnapshotProvider.pixel(_:displayScale:)` would be wrong by whatever
/// scale MapKit chose — wrong by a constant, which is the failure that looks
/// plausible in a still frame and drifts in motion.
///
/// These need the network (Apple Maps tiles), so they are env-gated like every
/// other live-substrate harness in this target:
///
///   TEST_RUNNER_KAMOME_MAP_PROBE=1 \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/MapKitSnapshotProbeTests
final class MapKitSnapshotProbeTests: XCTestCase {
    /// A public landmark, never a fixture coordinate (CLAUDE.md §0).
    private let center = CLLocationCoordinate2D(latitude: 64.1466, longitude: -21.9426)
    private let widthPx = 1080
    private let heightPx = 1920

    private func requireProbe() throws {
        try XCTSkipUnless(
            HarnessEnv.value("KAMOME_MAP_PROBE") == "1",
            "Live MapKit probe — set TEST_RUNNER_KAMOME_MAP_PROBE=1."
        )
    }

    /// One probe result: what was asked for, and what came back.
    private struct Probe {
        let snapshot: MKMapSnapshotter.Snapshot
        let canvas: CGSize
        let image: CGImage
    }

    private func snapshot(displayScale: Int, spanM: Double = 20_000) async throws -> Probe {
        let canvas = try MapKitSnapshotProvider.pointSize(
            widthPx: widthPx, heightPx: heightPx, displayScale: displayScale
        )
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center, latitudinalMeters: spanM * Double(heightPx) / Double(widthPx),
            longitudinalMeters: spanM
        )
        options.size = canvas
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: CGFloat(displayScale)),
            UITraitCollection(userInterfaceStyle: .dark)
        ])
        let snapshot = try await MKMapSnapshotter(options: options).start()
        return Probe(snapshot: snapshot, canvas: canvas, image: try XCTUnwrap(snapshot.image.cgImage))
    }

    /// **The finding the projection rests on.** `point(for:)` answers in the
    /// point canvas the snapshotter was handed — a 540x960pt canvas puts the
    /// region's centre at (270, 480), not at the image's (540, 960).
    func testPointForAnswersInTheCanvasNotTheImage() async throws {
        try requireProbe()
        for displayScale in 1...3 {
            let probe = try await snapshot(displayScale: displayScale)
            let atCenter = probe.snapshot.point(for: center)
            let halfCanvas = CGPoint(x: probe.canvas.width / 2, y: probe.canvas.height / 2)
            print(String(
                format: "KAMOME_MAP_PROBE requested %d — canvas %.0fx%.0fpt · image %dx%dpx "
                    + "(actual %.2f) · point(for: centre) = (%.1f, %.1f)",
                displayScale, probe.canvas.width, probe.canvas.height,
                probe.image.width, probe.image.height,
                Double(probe.image.width) / Double(probe.canvas.width), atCenter.x, atCenter.y
            ))
            XCTAssertEqual(atCenter.x, halfCanvas.x, accuracy: 1, "the centre must land mid-canvas, in points")
            XCTAssertEqual(atCenter.y, halfCanvas.y, accuracy: 1, "the centre must land mid-canvas, in points")
        }
    }

    /// Whatever MapKit rasters at, it must be *uniform* — that is the one thing
    /// the provider refuses, so it is the one thing worth measuring live.
    func testEveryRasterIsAUniformMultipleOfItsCanvas() async throws {
        try requireProbe()
        for displayScale in 1...3 {
            for spanM in [20_000.0, 200_000.0, 900_000.0] {
                let probe = try await snapshot(displayScale: displayScale, spanM: spanM)
                let raster = try MapKitSnapshotProvider.rasterScale(
                    imageWidth: probe.image.width, imageHeight: probe.image.height, canvas: probe.canvas
                )
                print(String(
                    format: "KAMOME_MAP_PROBE scale %d · span %.0fkm — image %dx%dpx · raster %.2f%@",
                    displayScale, spanM / 1000, probe.image.width, probe.image.height, raster,
                    abs(raster - Double(displayScale)) < 0.001 ? "" : "  <- NOT what was requested"
                ))
            }
        }
    }

    /// The render loop fires its snapshots as unstructured concurrent tasks
    /// (`RecapRenderLoop`), which was the first suspect for the 3x deviation.
    func testConcurrentRequestsDoNotChangeTheRasterScale() async throws {
        try requireProbe()
        let canvas = try MapKitSnapshotProvider.pointSize(widthPx: widthPx, heightPx: heightPx, displayScale: 2)
        let scales = try await withThrowingTaskGroup(of: Double.self) { group -> [Double] in
            for index in 0..<8 {
                group.addTask {
                    let options = MKMapSnapshotter.Options()
                    options.region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: self.center.latitude + Double(index) * 0.05, longitude: self.center.longitude
                        ),
                        latitudinalMeters: 20_000 * Double(self.heightPx) / Double(self.widthPx),
                        longitudinalMeters: 20_000
                    )
                    options.size = canvas
                    options.traitCollection = UITraitCollection(traitsFrom: [
                        UITraitCollection(displayScale: 2),
                        UITraitCollection(userInterfaceStyle: .dark)
                    ])
                    let snapshot = try await MKMapSnapshotter(options: options).start()
                    return Double(snapshot.image.cgImage?.width ?? 0) / Double(canvas.width)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        print("KAMOME_MAP_PROBE 8 concurrent at scale 2 — rasters \(scales.sorted())")
    }
}

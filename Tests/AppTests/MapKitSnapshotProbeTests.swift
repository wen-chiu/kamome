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
/// The question this settles, and the reason it must be measured rather than
/// reasoned about: `snapshot.point(for:)` answers in the **point** canvas, not
/// in the image's pixels. If it were the other way round, the correction in
/// `MapKitSnapshotProvider.pixel(_:displayScale:)` would be wrong by whatever
/// scale MapKit chose — and wrong by a constant, which is the failure mode that
/// looks plausible in a still frame and drifts in motion.
///
/// Needs the network (Apple Maps tiles), so it is env-gated like every other
/// live-substrate harness in this target:
///
///   TEST_RUNNER_KAMOME_MAP_PROBE=1 \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/MapKitSnapshotProbeTests
final class MapKitSnapshotProbeTests: XCTestCase {
    func testWhatMapKitDoesWithARequestedDisplayScale() async throws {
        try XCTSkipUnless(
            HarnessEnv.value("KAMOME_MAP_PROBE") == "1",
            "Live MapKit probe — set TEST_RUNNER_KAMOME_MAP_PROBE=1."
        )
        // A public landmark, not a fixture coordinate (CLAUDE.md §0).
        let center = CLLocationCoordinate2D(latitude: 64.1466, longitude: -21.9426)
        let widthPx = 1080, heightPx = 1920

        for displayScale in 1...3 {
            let size = try MapKitSnapshotProvider.pointSize(
                widthPx: widthPx, heightPx: heightPx, displayScale: displayScale
            )
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: center, latitudinalMeters: 20_000 * Double(heightPx) / Double(widthPx),
                longitudinalMeters: 20_000
            )
            options.size = size
            options.traitCollection = UITraitCollection(traitsFrom: [
                UITraitCollection(displayScale: CGFloat(displayScale)),
                UITraitCollection(userInterfaceStyle: .dark)
            ])

            let snapshot = try await MKMapSnapshotter(options: options).start()
            let image = try XCTUnwrap(snapshot.image.cgImage)
            let atCenter = snapshot.point(for: center)

            print(String(
                format: "KAMOME_MAP_PROBE requested %d — canvas %.0fx%.0fpt · image %dx%dpx "
                    + "(actual scale %.2f) · UIImage.scale %.1f · point(for: centre) = (%.1f, %.1f)",
                displayScale, size.width, size.height, image.width, image.height,
                Double(image.width) / Double(size.width), snapshot.image.scale,
                atCenter.x, atCenter.y
            ))

            // The centre of the region must land at the centre of whichever
            // space `point(for:)` speaks. Which space that is, is the finding.
            let halfCanvas = CGPoint(x: size.width / 2, y: size.height / 2)
            let halfImage = CGPoint(x: Double(image.width) / 2, y: Double(image.height) / 2)
            print(String(
                format: "KAMOME_MAP_PROBE   → half-canvas (%.1f, %.1f) · half-image (%.1f, %.1f) · "
                    + "answer is in %@",
                halfCanvas.x, halfCanvas.y, halfImage.x, halfImage.y,
                abs(atCenter.x - halfCanvas.x) < abs(atCenter.x - halfImage.x) ? "POINTS" : "PIXELS"
            ))
        }

        // Which variable makes MapKit deviate? The render that hit 3x was asking
        // for Iceland's country beat — a span two orders of magnitude wider than
        // the probe above — and was doing it from several concurrent tasks.
        for spanM in [20_000.0, 200_000.0, 900_000.0] {
            let size = try MapKitSnapshotProvider.pointSize(widthPx: widthPx, heightPx: heightPx, displayScale: 2)
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: center, latitudinalMeters: spanM * Double(heightPx) / Double(widthPx),
                longitudinalMeters: spanM
            )
            options.size = size
            options.traitCollection = UITraitCollection(traitsFrom: [
                UITraitCollection(displayScale: 2),
                UITraitCollection(userInterfaceStyle: .dark)
            ])
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let image = try XCTUnwrap(snapshot.image.cgImage)
            print(String(
                format: "KAMOME_MAP_PROBE span %.0fkm at scale 2 — image %dx%dpx (actual scale %.2f)",
                spanM / 1000, image.width, image.height, Double(image.width) / Double(size.width)
            ))
        }

        // The render loop fires its snapshots as unstructured concurrent tasks
        // (`RecapRenderLoop` line 84). Same request, several at once.
        let size = try MapKitSnapshotProvider.pointSize(widthPx: widthPx, heightPx: heightPx, displayScale: 2)
        let scales = try await withThrowingTaskGroup(of: Double.self) { group -> [Double] in
            for index in 0..<8 {
                group.addTask {
                    let options = MKMapSnapshotter.Options()
                    options.region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: center.latitude + Double(index) * 0.05, longitude: center.longitude
                        ),
                        latitudinalMeters: 20_000 * Double(heightPx) / Double(widthPx), longitudinalMeters: 20_000
                    )
                    options.size = size
                    options.traitCollection = UITraitCollection(traitsFrom: [
                        UITraitCollection(displayScale: 2),
                        UITraitCollection(userInterfaceStyle: .dark)
                    ])
                    let snapshot = try await MKMapSnapshotter(options: options).start()
                    let image = snapshot.image.cgImage
                    return Double(image?.width ?? 0) / Double(size.width)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        print("KAMOME_MAP_PROBE 8 concurrent at scale 2 — actual scales \(scales.sorted())")
    }
}

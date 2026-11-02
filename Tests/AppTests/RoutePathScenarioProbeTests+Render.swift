import CoreGraphics
@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

// The opt-in renders, apart from the audit (file length).
extension RoutePathScenarioProbeTests {
    // MARK: - Full renders (the real exporter, over a flat Mercator map)

    /// The shipped compositor, overlays, sprites and encoder, over a map that
    /// draws the stub's land boxes on Mercator — so a film can be watched and
    /// the render loop's own containment check runs on every frame.
    ///
    /// **Opt-in**, a minute a film: `TEST_RUNNER_KAMOME_PATH_PROBE_RENDER` names
    /// the scenarios by code (`L1,E1`). Films land in `~/Kamome-films/probe/`,
    /// never in the repository.
    func testRenderTheRiskiestScenarios() async throws {
        let codes = HarnessEnv.value("KAMOME_PATH_PROBE_RENDER")
        try XCTSkipUnless(codes != nil, "set TEST_RUNNER_KAMOME_PATH_PROBE_RENDER=L1,E1 to render scenarios")
        let full = try AppConfig.loadOrDie()
        let wanted = (codes ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let folder = URL(fileURLWithPath: home).appendingPathComponent("Kamome-films/probe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var failures: [String] = []
        for scenario in RoutePathScenarios.all where wanted.contains(where: { scenario.name.hasPrefix($0 + " ") }) {
            do {
                try await render(scenario, full: full, into: folder)
            } catch {
                failures.append("\(scenario.name): the export threw \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    /// One scenario through import, routing, composition and the real exporter.
    private func render(_ scenario: Scenario, full: TrackingConfig, into folder: URL) async throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try await ImportService(repository: repository, config: full)
            .importTrip(title: nil, photos: scenario.photos)
        await RouteMatchService(
            repository: repository, matching: full.matching.withBaseURL("https://probe.invalid"),
            reconstructor: scenario.routing
        ).matchTrip(tripId: tripId)
        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        let trip = try XCTUnwrap(RecapComposer.filmComposition(
            detail: detail, config: full, photosEnabled: true, length: .standard
        )).trip
        let config = full.export
        let line = try XCTUnwrap(Self.exportPlan(trip, config: config)).0
        let style = RecapStyle.modernMinimal(.dark).withEndCard(config.endCardStyle)
        let compositor = FrameCompositor(
            timeline: line,
            subject: VehicleSubjectRenderer.make(style: style, config: config, subjectId: detail.trip.vehicle),
            overlay: RecapOverlayRenderer(style: style, resolver: SolidPhotos()),
            style: style, widthPx: config.frameWidthPx, heightPx: config.frameHeightPx,
            crossingSubject: VehicleSubjectRenderer.make(
                style: style, config: config, subjectId: VehicleCatalog.crossingSubjectId
            ),
            flightSubject: VehicleSubjectRenderer.make(
                style: style, config: config, subjectId: VehicleCatalog.planeSubjectId
            )
        )
        let code = String(scenario.name.prefix { $0 != " " })
        let url = folder.appendingPathComponent("\(code).mp4")
        try? FileManager.default.removeItem(at: url)
        let started = ContinuousClock.now
        let output = try await RecapExporter(
            timeline: line, compositor: compositor, provider: MercatorFlatProvider(), config: config
        ).export(videoURL: url)
        print("KAMOME_PROBE_RENDER \(code) · \(line.frameCount) frames · \(ContinuousClock.now - started)"
            + " · \(output?.videoURL.path ?? "cancelled")")
    }

    struct SolidPhotos: RecapPhotoResolving {
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
            let side = max(64, min(targetPx, 512))
            guard let context = CGContext(
                data: nil, width: side, height: side * 4 / 3, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.setFillColor(CGColor(srgbRed: 0.85, green: 0.55, blue: 0.35, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side * 4 / 3))
            return context.makeImage()
        }
    }

    /// A map that is only the stub's land boxes, projected the way MapLibre
    /// projects (Web Mercator, wrapped to the copy nearest the centre).
    struct MercatorFlatProvider: MapRenderer {
        struct RenderError: Error {}

        var capabilities: MapRendererCapabilities {
            MapRendererCapabilities(
                supportsBearing: true, supportsHeadingUp: true,
                maxFramableLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg
            )
        }

        func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
            let band = MercatorBand(
                maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg, widthPx: widthPx, heightPx: heightPx
            )
            let drawn = band.fitted(frame)
            let world = band.worldPx(drawn)
            let project = { (lat: Double, lon: Double) -> CGPoint in
                var dx = (lon - drawn.centerLon) / 360 * world
                dx -= (dx / world).rounded() * world
                return CGPoint(
                    x: dx + Double(widthPx) / 2,
                    y: (MercatorBand.mercatorY(lat) - MercatorBand.mercatorY(drawn.centerLat)) * world
                        + Double(heightPx) / 2
                )
            }
            guard let context = CGContext(
                data: nil, width: widthPx, height: heightPx, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw RenderError() }
            context.setFillColor(CGColor(srgbRed: 0.10, green: 0.13, blue: 0.18, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
            context.setFillColor(CGColor(srgbRed: 0.20, green: 0.24, blue: 0.22, alpha: 1))
            for box in RoutePathScenarios.Land.boxes where box.name != nil {
                let corner = project(box.maxLat, box.minLon), far = project(box.minLat, box.maxLon)
                // Image rows run downward; CGContext's y runs upward.
                context.fill(CGRect(x: corner.x, y: Double(heightPx) - far.y,
                                    width: far.x - corner.x, height: far.y - corner.y))
            }
            guard let image = context.makeImage() else { throw RenderError() }
            return MapSnapshot(image: image, project: project)
        }
    }
}

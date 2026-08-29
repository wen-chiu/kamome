import CoreGraphics
import ImageIO
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import UniformTypeIdentifiers

/// Everything a **manual review render** needs, built once: a real imported trip
/// (photos → legs → road reconstruction), its timeline, the live MapLibre
/// souvenir map, and a photo resolver over real photographs.
///
/// Shared by the two review harnesses so they differ only in what they *do* with
/// the scene — `RecapStopStillTests` writes one frame, `RecapPilotFilmTests`
/// encodes the opening minute. Neither is a CI test; both are env-gated.
///
/// Real photographs matter: a synthetic gradient tile cannot tell you whether a
/// white keyline and a drop shadow read as a photo card, or whether a deck's
/// cross-fade reads as one place. Point `KAMOME_STOP_PHOTOS` at a folder of
/// images and they are dealt across the trip's photo slots in filename order.
struct RecapReviewScene {
    /// **`noRegion` is gone deliberately** (2026-08-27). Having no installed map
    /// region is not a failure — Apple Maps is the shipping substrate since the
    /// 2026-08-08 ADR — and this case additionally stood in for two unrelated
    /// failures, so any one of the three read as "you forgot the tiles path".
    enum SetupError: Error, CustomStringConvertible {
        /// The trip has no usable route geometry, so no timeline could be built.
        case noTimeline
        /// CoreGraphics would not give us a bitmap for the stand-in photo.
        case noPhotoTile

        var description: String {
            switch self {
            case .noTimeline: return "the trip produced no timeline — it has no usable route geometry"
            case .noPhotoTile: return "could not create the stand-in photo bitmap"
            }
        }
    }

    let trip: RecapTrip
    let config: TrackingConfig.Export
    let timeline: LinearTimeline
    let compositor: FrameCompositor
    let provider: MapRenderer
    /// The appearance this scene actually rendered in — the reviewer's request
    /// after the substrate has had its say, exactly as `RecapModel` resolves it.
    let appearance: RecapAppearance
    /// The style the compositor was built with, kept so a still can be *named*
    /// after what varies in it (`variantSuffix`).
    let style: RecapStyle

    static func make(fixture: String) async throws -> RecapReviewScene {
        let (trip, imported) = try await RecapDemoFilmTests.importedRecap(named: fixture)
        let config = keyframeIntervalOverride(imported)
        adoptTilesPathForTerrain()
        // **No installed region is not a failure** — the second of the two places
        // this rule was written (see `ReviewSubstrate`). Until 2026-08-27 this
        // threw, which made every harness built on this scene impossible to run
        // once MapLibre was parked on 2026-08-15: the length-limited film
        // (`RecapPilotFilmTests`) and every still (`RecapStopStillTests`).
        let region = GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) })
            .flatMap { RecapMapRegionResolver.resolve(covering: $0) }
        // The establishing shot is the region's bounds when there is a region.
        // With none it is nil — exactly what the shipped app passes, and what
        // `buildWideOpening` already has a branch for.
        let establishing = region.map {
            RecapBounds(
                minLat: $0.bounds.minLat, minLon: $0.bounds.minLon,
                maxLat: $0.bounds.maxLat, maxLon: $0.bounds.maxLon
            )
        }
        guard let timeline = LinearTimeline(trip: trip, config: config, establishing: establishing) else {
            throw SetupError.noTimeline
        }

        // The provider first, because it can veto the appearance: the souvenir map
        // has no light variant and declares so. Resolving it here — rather than
        // building the style from what the reviewer typed — is what keeps a review
        // still equal to the film the app would render (`RecapModel.runExport`).
        let provider = try ReviewSubstrate.renderer(region: region, reporting: "KAMOME_REVIEW")
        let appearance = provider.capabilities.appearance(
            honouring: try ReviewSubstrate.experiment().appearance
        )
        let style = try ReviewPalette.style(appearance).withEndCard(config.endCardStyle)
        return RecapReviewScene(
            trip: trip, config: config, timeline: timeline,
            compositor: FrameCompositor(
                timeline: timeline,
                subject: Self.subjectRenderer(style: style, config: config),
                overlay: RecapOverlayRenderer(style: style, resolver: try Self.resolver(for: trip)),
                style: style,
                widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            ),
            provider: provider,
            appearance: appearance,
            style: style
        )
    }

    /// The subject under review. **Two review-only overrides**, because the
    /// judgement Chiu is making is "is this the right size?" and "how does each
    /// set look?" — one variable at a time, same trip, same frame.
    ///
    /// `KAMOME_SUBJECT_LENGTH_PX` overrides `export.subject_length_px`, and
    /// `KAMOME_SUBJECT` picks the folder. Neither touches the config file, so a
    /// setting for one still can never be committed.
    private static func subjectRenderer(
        style: RecapStyle, config: TrackingConfig.Export
    ) -> VehicleSubjectRenderer {
        let lengthPx = HarnessEnv.value("KAMOME_SUBJECT_LENGTH_PX")
            .flatMap(Double.init).map { CGFloat($0) } ?? CGFloat(config.subjectLengthPx)
        let subjectId = HarnessEnv.value("KAMOME_SUBJECT")
        // Not `Int(lengthPx)`: a sweep may ask for a fractional size (157.5 is
        // 30% below 225), and truncating it to "157px" in the one line a reviewer
        // reads is how a still gets judged against a number nobody rendered.
        print("KAMOME_REVIEW subject \(subjectId ?? VehicleCatalog.defaultSubjectId) at \(lengthPx)px")
        // `KAMOME_FORCE_FALLBACK_MARKER` drives the **failure** visual on purpose
        // (2026-08-29). `make`'s doc comment used to say that path "only fires
        // when the app's own resource bundle cannot be found — a state no test can
        // arrange"; on 2026-08-28 it fired by itself in one review render out of
        // four, silently, and the wrong still survived review. A token whose job
        // is now partly to make that failure visible has to be renderable on
        // demand, or its colour can only ever be judged by accident.
        guard HarnessEnv.value("KAMOME_FORCE_FALLBACK_MARKER") == nil else {
            print("KAMOME_REVIEW FORCING the fallback marker — the sprite path is deliberately bypassed")
            return VehicleSubjectRenderer.make(
                style: style, subjectId: subjectId, lengthPx: lengthPx, resolve: { _ in nil }
            )
        }
        return VehicleSubjectRenderer.make(style: style, subjectId: subjectId, lengthPx: lengthPx)
    }

    /// Names a still by what varies in it, so a sweep does not overwrite itself.
    ///
    /// An instance property since 2026-08-28: the palette overrides change the
    /// image, and a suffix that could not see them would have let a three-colour
    /// sweep write three times to one filename.
    var variantSuffix: String {
        let subject = HarnessEnv.value("KAMOME_SUBJECT") ?? VehicleCatalog.defaultSubjectId
        let length = HarnessEnv.value("KAMOME_SUBJECT_LENGTH_PX") ?? "default"
        let palette = ReviewPalette.variantSuffix(style)
        return "\(subject)-\(length)px-\(appearance.rawValue)"
            + (palette.isEmpty ? "" : "-\(palette)")
    }

    /// `KAMOME_KEYFRAME_INTERVAL` renders the same film at a different snapshot
    /// rate (2026-08-15). Export time is snapshot-bound, so this is the single
    /// biggest lever on it — and what a coarser interval spends is cross-fade
    /// smoothness, which can only be judged by watching two renders of one trip.
    /// Review-only, applied per run, so an experiment never lands in
    /// `TrackingConfig.json`.
    private static func keyframeIntervalOverride(_ config: TrackingConfig.Export) -> TrackingConfig.Export {
        guard let interval = HarnessEnv.value("KAMOME_KEYFRAME_INTERVAL").flatMap(Int.init)
        else { return config }
        print("KAMOME_KEYFRAME_INTERVAL \(interval) (was \(config.keyframeIntervalFrames))")
        return config.withKeyframeIntervalFrames(interval)
    }

    /// Terrain lives behind its **own** environment variable, and every review
    /// render made before 2026-07-31 silently had no hillshade because only the
    /// tiles path was ever set. A missing DEM does not fail — it just renders a
    /// flat map, which reads as a styling regression rather than as a forgotten
    /// variable, so it can go unnoticed for weeks.
    ///
    /// A reviewer who supplied tiles wants terrain: point it at the same data root
    /// (`…/kamome-osrm/tiles` → `…/kamome-osrm`, whose `terrain/` folder the
    /// lookup now also scans). Explicit settings are never overridden, and the
    /// resolved DEM is printed either way, so a flat render says so out loud.
    private static func adoptTilesPathForTerrain() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KAMOME_TERRAIN_PATH"]?.isEmpty ?? true,
              let tiles = environment["KAMOME_TILES_PATH"], !tiles.isEmpty else { return }
        let root = URL(fileURLWithPath: tiles).deletingLastPathComponent()
        setenv("KAMOME_TERRAIN_PATH", root.path, 1)
    }

    /// One composited frame at `time`, over a fresh snapshot at the timeline's own
    /// camera — the same path the exporter takes, minus the keyframe cache.
    func frame(at time: Double) async throws -> CGImage {
        let camera = timeline.cameraFrame(atTime: time)
        let background = try await provider.snapshot(
            camera, map: MapState(), widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        return try compositor.render(atTime: time, background: RecapBackground(current: background))
    }

    // MARK: - Construction

    private struct FolderResolver: RecapPhotoResolving {
        let images: [String: CGImage]
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
            if case let .asset(id) = ref { return images[id] }
            return nil
        }
    }

    /// **Matched by filename first** (2026-08-02). `exif-to-fixture.sh` writes each
    /// photo's own basename as its id, so a fixture dumped from a real folder can
    /// show each stop the photographs actually taken there — which is the whole
    /// point of a Stage 1 "is this worth publishing?" judgement. Dealing images
    /// round-robin puts a mountain on a harbour and tells you nothing.
    ///
    /// Falls back to dealing in filename order for hand-written fixtures, whose
    /// ids are labels like `tek-1` rather than files, and to a generated tile when
    /// there are no real photos at all.
    private static func resolver(for trip: RecapTrip) throws -> RecapPhotoResolving {
        let files = photoFiles()
        if files.isEmpty { print("KAMOME_REVIEW no real photos — set KAMOME_STOP_PHOTOS for a truthful render") }
        let byName = Dictionary(files.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })

        var images: [String: CGImage] = [:]
        var matched = 0
        for (index, ref) in trip.stops.flatMap(\.photos).enumerated() {
            guard case let .asset(id) = ref else { continue }
            if let exact = byName[id], let image = load(exact) {
                images[id] = image
                matched += 1
                continue
            }
            let dealt = files.isEmpty ? nil : load(files[index % files.count])
            images[id] = try dealt ?? photoTile(index: index)
        }
        if !files.isEmpty {
            print("KAMOME_REVIEW deck photos: \(matched)/\(images.count) matched by filename"
                + (matched == images.count ? "" : " — the rest dealt in order"))
        }
        return FolderResolver(images: images)
    }

    private static func photoFiles() -> [URL] {
        guard let path = HarnessEnv.value("KAMOME_STOP_PHOTOS") else { return [] }
        let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil
        )
        return (contents ?? [])
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The fallback "photo": a flat gradient, so a render made without real images
    /// is obviously a layout check and not a look check.
    private static func photoTile(index: Int) throws -> CGImage {
        let side = 900
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw SetupError.noPhotoTile }
        let hue = CGFloat(index % 5) / 5
        if let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.25 + hue * 0.5, green: 0.45, blue: 0.7 - hue * 0.4, alpha: 1),
            CGColor(srgbRed: 0.12 + hue * 0.25, green: 0.22, blue: 0.35 - hue * 0.2, alpha: 1)
        ] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        }
        guard let image = context.makeImage() else { throw SetupError.noPhotoTile }
        return image
    }

    // MARK: - Output

    static func outputDirectory() -> URL {
        if let override = HarnessEnv.value("KAMOME_RENDER_OUT") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kamome-review", isDirectory: true)
    }
}

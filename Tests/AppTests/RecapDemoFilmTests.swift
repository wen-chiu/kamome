import AVFoundation
import CoreGraphics
import CoreText
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import UniformTypeIdentifiers
import XCTest

/// Renders a **complete recap film** end to end for review — not a CI test.
///
/// Everything the shipped app would do: the real Perth → Margaret River GPX
/// replayed through the tracking engine, its live ∪ derived stops, the Modern
/// Minimal theme over MapLibre souvenir-map tiles, the 8-direction car, the
/// two-beat stop scenes with photo decks, title and end chrome, encoded to MP4.
///
/// Needs corridor tiles — the committed fixture crop covers ~20 km around
/// Margaret River, and this trip runs 290 km, so point `KAMOME_TILES_PATH` at a
/// corridor build (`Tests/Fixtures/tiles/generate_tiles.sh` with the bounds
/// widened; that artifact is far too large for git).
///
///   TEST_RUNNER_KAMOME_DEMO_FILM=1 \
///   TEST_RUNNER_KAMOME_TILES_PATH=/path/to/corridor.pmtiles \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapDemoFilmTests
final class RecapDemoFilmTests: XCTestCase {
    private struct DeckResolver: RecapPhotoResolving {
        let images: [String: CGImage]
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
            if case let .asset(id) = ref { return images[id] }
            return nil
        }
    }

    func testRenderDemoFilm() async throws {
        try XCTSkipUnless(
            HarnessEnv.value("KAMOME_DEMO_FILM") == "1",
            "Manual demo render — set KAMOME_DEMO_FILM=1."
        )
        let config = try AppConfig.loadOrDie().export
        try await renderFilm(trip: try demoTrip(config: config), config: config, named: "kamome-demo-film")
    }

    /// Renders `trip` the way the shipped app would and prints where it landed.
    private func renderFilm(trip: RecapTrip, config: TrackingConfig.Export, named: String) async throws {
        let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
        let region = RecapMapRegionResolver.resolve(covering: bounds)
        let establishing = region.map {
            RecapBounds(
                minLat: $0.bounds.minLat, minLon: $0.bounds.minLon,
                maxLat: $0.bounds.maxLat, maxLon: $0.bounds.maxLon
            )
        }
        let timeline = try XCTUnwrap(
            LinearTimeline(trip: trip, config: config, establishing: establishing)
        )
        // Stand-in photos: the simulator has no real library, and the deck beats
        // are the thing under review. One tile per selected photo.
        var images: [String: CGImage] = [:]
        for (index, ref) in trip.stops.flatMap(\.photos).enumerated() {
            if case let .asset(id) = ref { images[id] = try photoTile(index: index) }
        }

        // Provider before style, and the style built from the *resolved*
        // appearance — the order `RecapModel.runExport` uses, for its reason: a
        // substrate that is locked to one appearance (the souvenir map) must not
        // end up under a palette tuned for the other.
        let provider = try snapshotProvider(region: region)
        let appearance = provider.capabilities.appearance(
            honouring: try ReviewSubstrate.experiment().appearance
        )
        let style = try ReviewPalette.style(appearance)
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: Self.subjectRenderer(style: style, config: config),
            overlay: RecapOverlayRenderer(style: style, resolver: DeckResolver(images: images)),
            style: style,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let exporter = RecapExporter(
            timeline: timeline, compositor: compositor, provider: provider, config: config
        )

        let outDir = outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let videoURL = outDir.appendingPathComponent("\(named).mp4")
        try? FileManager.default.removeItem(at: videoURL)

        let started = Date.now
        let output = try await exporter.export(videoURL: videoURL)
        let seconds = Date.now.timeIntervalSince(started)
        XCTAssertNotNil(output, "the demo film must render to completion")

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let sizeMB = Double(
            (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
        ) / 1e6
        print(String(
            format: "KAMOME_DEMO_FILM %@  %d stops · %d legs · %d frames · %.1fs video · %.1f MB · rendered in %.0fs",
            videoURL.path, trip.stops.count, trip.legs.count, timeline.frameCount, duration, sizeMB, seconds
        ))
        reportPacing(timeline, trip: trip)
    }

    /// Measures what the film actually does — dwell per stop read off the
    /// timeline rather than assumed — so a before/after comparison reports
    /// observed pacing instead of intended pacing.
    private func reportPacing(_ timeline: LinearTimeline, trip: RecapTrip) {
        let dwells = trip.stops.map { stop -> Double in
            var first: Double?, last: Double?
            var time = 0.0
            while time <= timeline.durationS {
                if let deck = activeDeck(timeline.overlayContents(atTime: time)),
                   deck.photos.first == stop.photos.first, deck.opacity > 0.001 {
                    if first == nil { first = time }
                    last = time
                }
                time += 1.0 / 30
            }
            guard let first, let last else { return 0 }
            return last - first
        }
        let mean = dwells.isEmpty ? 0 : dwells.reduce(0, +) / Double(dwells.count)
        print(String(
            format: "KAMOME_DEMO_PACING opening %.1fs · dwell mean %.1fs · range %.1f-%.1fs · per-stop %@",
            timeline.openingS, mean, dwells.min() ?? 0, dwells.max() ?? 0,
            dwells.map { String(format: "%.1f", $0) }.joined(separator: "/")
        ))
    }

    private func activeDeck(_ contents: [OverlayContent]) -> RecapPhotoDeck? {
        for content in contents {
            if case let .photoDeck(deck) = content { return deck }
        }
        return nil
    }

    // MARK: - Imported film (photos → legs → routing → recap)

    /// The **whole Replay MVP loop** in one artifact: geotagged photos →
    /// `ImportService` (per-leg segments) → Geoapify `/v1/routing` reconstruction with the
    /// intermediate photos as via-waypoints → `RecapComposer` typed legs → film.
    ///
    /// This is where the honesty shows: the drives reconstruct against the road
    /// network and draw solid, while the coastal walk — never routed, because a
    /// car profile would snap it to the nearest street (PD-8) — draws dashed.
    /// Both are in the same frame, which is the point of PD-1.
    ///
    /// The trip is read from `Tests/Fixtures/trips/<name>.json` — one file per
    /// dogfood region, so a render is a fixture swap rather than a code change,
    /// and a real photo library can be dumped straight into that shape
    /// (`Tools/exif-to-fixture.sh`).
    ///
    /// Needs a routing key in `Config/Secrets.xcconfig` and tiles for the region:
    ///
    ///   KAMOME_DEMO_FILM_IMPORT=iceland \
    ///   KAMOME_TILES_PATH=~/kamome-osrm/tiles \
    ///   KAMOME_RENDER_OUT=/path/to/out
    func testRenderImportedFilm() async throws {
        let requested = HarnessEnv.value("KAMOME_DEMO_FILM_IMPORT") ?? ""
        try XCTSkipUnless(
            !requested.isEmpty,
            "Manual demo render — set KAMOME_DEMO_FILM_IMPORT to a fixture name (e.g. iceland)."
        )
        let fixture = requested == "1" ? "margaret-river" : requested
        // **The crossing fixture is routed by the offline sea provider, never by
        // the live endpoint** — the same rule `RecapReviewScene` and
        // `RecapSnapshotBudgetTests` already follow. Its "no road here" is a
        // fixture fact authored with the coordinates; routed live, the crossing is
        // not a crossing, no arc is built, and this renders a different film while
        // looking like it worked.
        let sea = UnroutableSeaProvider.forFixture(fixture)
        let (recap, config) = try await Self.importedRecap(
            named: fixture, baseURL: sea == nil ? nil : "", reconstructor: sea
        )
        try await renderFilm(trip: recap, config: config, named: "kamome-\(fixture)")
    }

    /// `baseURL` nil takes the ambient routing endpoint (review renders want
    /// real roads); passing `""` forces every leg to stay raw, which is what the
    /// offline continuity gate needs — and what the shipped app does today,
    /// since `matching.base_url` ships empty.
    ///
    /// The default is the live provider (2026-08-20): a render with a key in
    /// `Config/Secrets.xcconfig` routes against Geoapify, and one without it
    /// gets 401s reported as an unreachable provider. Every caller that reaches
    /// this default is env-gated and never runs in CI.
    ///
    /// `reconstructor` replaces the routing provider outright. The offline gates
    /// need it because their `baseURL: ""` disables routing altogether, which
    /// means **nothing is ever established** about any leg — and a crossing is a
    /// leg something *was* established about (`SegmentRoutability`). A stub is
    /// the only way to render a crossing without a live endpoint, and it is the
    /// same seam `RouteMatchService` already offers the app.
    static func importedRecap(
        named fixture: String,
        baseURL requestedBaseURL: String? = nil,
        reconstructor: RouteReconstructing? = nil
    ) async throws -> (RecapTrip, TrackingConfig.Export) {
        let full = try AppConfig.loadOrDie()
        let baseURL = requestedBaseURL
            ?? HarnessEnv.value("KAMOME_ROUTING_BASE_URL")
            ?? "https://api.geoapify.com"
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: full)
        // Routing became its own step on 2026-08-15 (`importTrip` returns as
        // soon as the trip is saved, so the import sheet stops blocking). A desk
        // render still wants roads, so it asks for them — and waits, which the
        // app deliberately does not.
        let routing = RouteMatchService(
            repository: repository, matching: full.matching,
            reconstructor: reconstructor
                ?? GeoapifyRouteProvider(config: full.matching.withBaseURL(baseURL))
        )

        let trip = try Self.tripFixture(named: fixture)
        let tripId = try await service.importTrip(title: trip.title, photos: trip.photos)
        await routing.matchTrip(tripId: tripId)
        // Real stop names, opt-in and cached (`RecapReviewGeocoder`). Without this
        // the harness composes straight out of the importer, which cannot name a
        // stop, and every card in the pilot reads "Unnamed stop" — a difference
        // from the shipped app that has twice been mistaken for a regression.
        if RecapReviewGeocoder.isEnabled {
            try await Self.nameStops(tripId: tripId, fixture: fixture, repository: repository, config: full)
        }
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        let legs = RecapComposer.legs(
            from: detail.segments, epsilonM: full.simplify.epsilonM, matchedEpsilonM: full.matching.displayEpsilonM
        )
        print("KAMOME_DEMO_FILM_IMPORT legs: "
            + legs.map { "\($0.mode.rawValue)/\($0.provenance)\($0.isCrossing ? "/CROSSING" : "")" }
                .joined(separator: ", "))

        // TEMPORARY (2026-08-04, duration-ratio experiment): pin the film length
        // for a review render without editing the config between runs.
        let config = try Self.reviewConfig(full.export)
        let selections = Self.stopPhotoSelections(detail: detail, full: full)
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: detail.stops, stats: nil,
            photosByStop: selections.photosByStop,
            deck: RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        ),
            stopHoldS: config.stopHoldS,
            rawPhotoCounts: selections.rawPhotoCounts,
            favoriteCounts: selections.favoriteCounts,
            weighting: config,
            everyLegRoutabilityEstablished:
                RecapComposer.everyLegRoutabilityEstablished(detail.segments)
        ))
        print("KAMOME_DEMO_FILM_IMPORT film type: \(recap.filmType) "
            + "(\(RecapFilmType.distinctJourneyCount(legs: recap.legs)) local journeys, "
            + "routing established for every leg: "
            + "\(RecapComposer.everyLegRoutabilityEstablished(detail.segments)))")
        let waypoints = recap.stops.filter(\.photos.isEmpty).count
        print("KAMOME_STOP_WEIGHTS \(recap.stops.count) stops · \(waypoints) waypoints · "
            + "\(recap.stops.count - waypoints) highlights · weighting "
            + (config.stopWeightingEnabled ? "ON" : "off"))
        return (recap, config)
    }

    /// The two review-only overrides, applied per run so a setting for one render
    /// never gets committed in `TrackingConfig.json`.
    ///
    /// `KAMOME_RECAP_MODE` picks **Variant A** (`full` — every clustered stop
    /// presented, no duration cap) against the shipped **Variant B**
    /// (`highlight`). `KAMOME_FORCE_DURATION_S` pins a length for a length
    /// experiment; it is marked temporary where it was introduced (2026-08-04).
    static func reviewConfig(_ base: TrackingConfig.Export) throws -> TrackingConfig.Export {
        var config = base
        if let requested = HarnessEnv.value("KAMOME_RECAP_MODE") {
            guard let mode = RecapMode(rawValue: requested) else {
                XCTFail("KAMOME_RECAP_MODE=\(requested) is not a RecapMode")
                throw CocoaError(.featureUnsupported)
            }
            config = config.withRecapMode(mode)
            print("KAMOME_RECAP_MODE \(requested)")
            // Variant A means "see the whole trip", and a stop with a beat but no
            // photograph is still empty to the viewer — so the allocator's zero
            // share, which is right for a highlight reel, is wrong here. Scoped to
            // the mode so Variant B's shipped 0.4 is untouched.
            //
            // Explicitly overridable so the *before* of this change stays
            // measurable: comparing Variant A against Variant B would have
            // compared two things at once.
            if case .full = mode {
                let share = HarnessEnv.value("KAMOME_ALLOCATION_ZERO_SHARE")
                    .flatMap(Double.init) ?? 0
                config = config.withAllocationZeroShare(share)
                print("KAMOME_ALLOCATION_ZERO_SHARE \(share) (Variant A)")
            }
        }
        if let forced = HarnessEnv.value("KAMOME_FORCE_DURATION_S").flatMap(Double.init) {
            config = config.withTotalDuration(min: forced, max: forced)
            print("KAMOME_FORCE_DURATION_S \(forced)")
        }
        return config
    }

    /// Runs the **shipped** `StopNamer` over the trip's stops and waits for it to
    /// finish, so what the pilot renders is what the app would have written.
    private static func nameStops(
        tripId: String, fixture: String, repository: TripRepository, config: TrackingConfig
    ) async throws {
        let stops = try XCTUnwrap(try repository.detail(tripId: tripId)).stops
        let geocoder = RecapReviewGeocoder(fixture: fixture)
        let namer = StopNamer(config: config.geocode, repository: repository, geocoder: geocoder)
        let started = Date.now
        await withCheckedContinuation { continuation in
            var resumed = false
            namer.nameUnnamedStops(stops) { progress in
                guard progress.isFinished, !resumed else { return }
                resumed = true
                continuation.resume()
            }
        }
        print(String(
            format: "KAMOME_GEOCODE_STOPS %d/%d named · %d cached, %d looked up · %.0fs",
            namer.progress.named, namer.progress.total, geocoder.hits, geocoder.misses,
            Date.now.timeIntervalSince(started)
        ))
    }

    // MARK: - Trip

    /// The committed day-1 GPX through the real engine, then the same composition
    /// the app performs: matched/simplified route, live ∪ derived stops, real
    /// stop names, photo-count-driven dwells.
    private func demoTrip(config: TrackingConfig.Export) throws -> RecapTrip {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/perth_margaret_river_day1.gpx")
        let samples = try GPXFilmParser().parse(contentsOf: fixture)
        let full = try AppConfig.loadOrDie()
        let engine = TrackingEngine(config: full, vehicle: .car)
        engine.start(at: try XCTUnwrap(samples.first).ts)
        for sample in samples { engine.process(sample) }
        engine.finish(at: try XCTUnwrap(samples.last).ts)

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: full)
        let stops = (engine.stops + derived).sorted { $0.arrivedAt < $1.arrivedAt }
        let names = ["Mandurah", "Bunbury", "Busselton Jetty", "Margaret River"]
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS
        )

        // One leg per engine segment, as the app now composes (typed-leg pass
        // 2026-07-26). This trip is real recorded GPS end to end, so every leg
        // is `.recorded` and draws solid — the dashed treatment is exercised by
        // the imported film below, where it belongs.
        let legs = engine.segments.compactMap { segment -> RecapTrip.Leg? in
            let points = segment.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }
            let simplified = Simplifier.douglasPeucker(points, epsilonM: full.simplify.epsilonM)
                .map { RecapCoordinate(lat: $0.lat, lon: $0.lon) }
            guard simplified.count >= 2 else { return nil }
            return RecapTrip.Leg(coordinates: simplified, mode: segment.mode, provenance: .recorded)
        }

        let tripStops = stops.enumerated().map { index, stop -> RecapTrip.Stop in
            let photos = (0..<3).map { PhotoRef.asset("stop\(index)-photo\($0)") }
            return RecapTrip.Stop(
                coordinate: RecapCoordinate(lat: stop.lat, lon: stop.lon),
                name: index < names.count ? names[index] : "停留 \(index + 1)",
                dayLabel: "Day 1", detail: nil, photos: photos,
                dwellS: deck.dwellS(photoCount: photos.count)
            )
        }
        return RecapTrip(
            legs: legs, stops: tripStops,
            title: "Perth → Margaret River", subtitle: "Day 1 · 291 km",
            statsLines: ["291 km · \(tripStops.count) 停留", "5.8 小時"],
            callToAction: "Record your own journey"
        )
    }

    // MARK: - Assets

    private func outputDirectory() -> URL {
        if let override = HarnessEnv.value("KAMOME_RENDER_OUT") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kamome-demo-film", isDirectory: true)
    }

}

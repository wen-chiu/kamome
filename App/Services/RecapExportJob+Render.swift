import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence

/// The half of the export that turns a composed trip into frames and a file.
/// Split from `RecapExportJob` so each stage stays readable; nothing here
/// changed in the move out of `RecapModel` (Chiu 2026-09-10).
extension RecapExportJob {
    /// Everything resolved once, before a frame is drawn, and never asked again.
    struct Plan {
        let timeline: LinearTimeline
        let provider: MapRenderer
        let style: RecapStyle
        let config: TrackingConfig.Export
        let appearance: RecapAppearance
    }

    // MARK: - Planning

    func plan(_ composed: Composed) -> Plan? {
        // Layer 3 pipeline. The map stays north-up (product decision, Chiu
        // 2026-07-25) and the 8-direction car sprite carries the heading, so the
        // subject looks identical whichever base map renders underneath.
        //
        // One question, asked once (`RecapMapRegion` is the seam): which region
        // covers this trip? Its tiles feed the renderer, its DEM feeds hillshade,
        // and its extent is what the opening establishing shot frames.
        let tripBox = GeoBox.enclosing(composed.trip.route.map { (lat: $0.lat, lon: $0.lon) })
        let region = tripBox.flatMap { RecapMapRegionResolver.resolve(covering: $0) }
        let provider: MapRenderer
        do {
            provider = try Self.snapshotProvider(for: region, appearance: request.appearance, tripBox: tripBox)
        } catch {
            KamomeLog.recap.error("snapshotProvider failed: \(error, privacy: .public)")
            return nil
        }
        // Resolved once, here, and never asked again — the substrate can veto the
        // device's choice (the MapLibre souvenir map has no light variant), and
        // the palette below must follow whatever the *base map* actually is, not
        // what the device asked for. Same shape as the heading-up line under it:
        // a capability the renderer declares rather than silently ignores.
        //
        // `follow_heading_up` ships false; the capability check only stops a
        // renderer that cannot rotate from being handed a bearing it would drop.
        let appearance = provider.capabilities.appearance(honouring: request.appearance)
        let exportConfig = config.export.withFollowHeadingUp(
            config.export.followHeadingUp && provider.capabilities.supportsHeadingUp
        )
        // The region's extent drives the opening establishing shot (Chiu
        // 2026-07-30). No region means the establishing shot frames the route's
        // own bounds instead of a named region — pacing is `.contentDerived`
        // either way (`LinearTimelinePacing.pacing`, unconditional on
        // `establishing`).
        let establishing = region.map {
            RecapBounds(
                minLat: $0.bounds.minLat, minLon: $0.bounds.minLon,
                maxLat: $0.bounds.maxLat, maxLon: $0.bounds.maxLon
            )
        }
        guard let timeline = LinearTimeline(
            trip: composed.trip, config: exportConfig, establishing: establishing,
            // The capability layer reaching the film's form: the substrate says
            // how wide a frame it can draw, and the type-2 opening picks between
            // its two forms accordingly rather than discovering the answer one
            // snapshot at a time (`CrossingFraming`).
            substrateMaxLongitudeDeg: provider.capabilities.maxFramableLongitudeDeg
        ) else { return nil }
        announce(timeline: timeline, trip: composed.trip, region: region, appearance: appearance)
        return Plan(
            timeline: timeline, provider: provider,
            style: RecapStyle.modernMinimal(appearance).withEndCard(config.export.endCardStyle),
            config: exportConfig, appearance: appearance
        )
    }

    /// The single most useful line in the log when a film comes out wrong
    /// (2026-08-01), and the only record of the appearance a finished film was
    /// drawn in before `film.appearance` existed to store it.
    private func announce(
        timeline: LinearTimeline, trip: RecapTrip, region: RecapMapRegion?, appearance: RecapAppearance
    ) {
        // ⚠️ **Corrected 2026-09-22.** This used to say the export falls back to
        // Apple's map with no prologue and a fixed 30s duration — true before the
        // OpenFreeMap production switch (ADR 2026-09-16), false since:
        // `snapshotProvider` now falls through to live OpenFreeMap tiles rather
        // than Apple or the dormant `.pmtiles` path, and pacing has been
        // `.contentDerived` regardless of `establishing` since before that. What a
        // missing region still costs, confirmed by reading both call sites: the
        // opening's establishing shot has no named region extent to frame from
        // (it uses the route's own bounds instead), and the souvenir map's own
        // tile set. A misdiagnosed export used to read this line and stop
        // looking further — it no longer says something that is not happening.
        if region == nil {
            KamomeLog.recap.error("""
                no installed map region covers this trip — the opening establishing shot has no \
                named region extent to frame from, and the souvenir map falls through to live \
                OpenFreeMap tiles. Duration and the type-2 opening are unaffected.
                """)
        }
        KamomeLog.recap.notice("""
            film: \(timeline.durationS, format: .fixed(precision: 1))s · \
            \(timeline.frameCount) frames · opening \(timeline.openingS, format: .fixed(precision: 1))s · \
            \(trip.stops.count) stops · \(trip.legs.filter(\.provenance.isInferred).count)/\(trip.legs.count) legs dashed · \
            \(appearance.rawValue, privacy: .public) appearance\
            \(appearance == request.appearance
                ? ""
                : " (device asked for \(request.appearance.rawValue), the substrate is fixed)", privacy: .public)
            """)
    }

    // MARK: - Rendering

    func render(
        composed: Composed, plan: Plan,
        resolver: PhotoLibraryPhotoResolver, channel: RecapExportChannel
    ) async -> RecapExportOutcome {
        let compositor = compositor(composed: composed, plan: plan, resolver: resolver)
        let exporter = RecapExporter(
            timeline: plan.timeline,
            compositor: compositor,
            provider: plan.provider,
            config: plan.config
        )
        // **The bill, before it is paid.** `stations` is pure, so the number of
        // snapshots an export will take is knowable in milliseconds — and it is
        // the number that decides how long the export runs. Logged first so a
        // film that is going to cost half an hour says so at second one rather
        // than at minute thirty.
        let stationCount = RecapRenderLoop(
            timeline: plan.timeline, compositor: compositor,
            provider: plan.provider, config: plan.config
        ).stations.count
        KamomeLog.recap.notice(
            "render plan: \(stationCount) stations for \(plan.timeline.frameCount) frames"
        )
        let scratch = FileManager.default.temporaryDirectory
        let stamp = Int(Date.now.timeIntervalSince1970)
        let videoURL = scratch.appendingPathComponent("kamome-recap-\(stamp).mp4")
        let gifURL = request.format == .gif ? scratch.appendingPathComponent("kamome-recap-\(stamp).gif") : nil
        try? FileManager.default.removeItem(at: videoURL)

        let started = ContinuousClock.now
        do {
            let output = try await runDetached(
                exporter: exporter, videoURL: videoURL, gifURL: gifURL, channel: channel
            )
            // Asked again on the main actor after the last frame: a trip deleted
            // meanwhile (`TripDeletion`) stores nothing (arch review 2026-09-24).
            guard let output, channel.shouldContinue() else {
                cleanup(videoURL: videoURL, gifURL: gifURL)
                return .cancelled
            }
            let seconds = elapsed(since: started)
            report(output: output, seconds: seconds)
            return try store(output: output, plan: plan, seconds: seconds)
        } catch {
            cleanup(videoURL: videoURL, gifURL: gifURL)
            return .failed(message: String(describing: error))
        }
    }

    /// **Where the export's minutes went**, in one line, at the only altitude a
    /// device run can be read from.
    ///
    /// Durations and counts only — nothing here names a place (`CLAUDE.md` §0).
    ///
    /// How to read it: `snapshots` is the substrate's own bill, summed across
    /// concurrent fetches, so it can exceed the total; `wait` is what the loop
    /// actually stalled for, and the gap between the two is what prefetching
    /// already hid. A `wait` close to the total means the render is starved on
    /// the provider and more concurrency is the lever; a large `composite` says
    /// it is not.
    private func report(output: RecapExporter.Output, seconds: Double) {
        let stats = output.stats
        KamomeLog.recap.notice("""
            render cost: \(seconds, format: .fixed(precision: 1))s total · \
            \(stats.frames) frames · \(stats.stations) stations / \(stats.fetches) fetches · \
            snapshots \(stats.snapshotS, format: .fixed(precision: 1))s \
            (mean \(stats.meanSnapshotS, format: .fixed(precision: 2))s, \
            wait \(stats.waitS, format: .fixed(precision: 1))s) · \
            composite \(stats.compositeS, format: .fixed(precision: 1))s · \
            encode \(stats.deliverS, format: .fixed(precision: 1))s · \
            finish \(output.finishS, format: .fixed(precision: 1))s
            """)
    }

    private func compositor(
        composed: Composed, plan: Plan, resolver: PhotoLibraryPhotoResolver
    ) -> FrameCompositor {
        FrameCompositor(
            timeline: plan.timeline,
            subject: VehicleSubjectRenderer.make(
                style: plan.style, config: plan.config, subjectId: composed.detail.trip.vehicle
            ),
            overlay: RecapOverlayRenderer(style: plan.style, resolver: resolver),
            style: plan.style,
            widthPx: config.export.frameWidthPx,
            heightPx: config.export.frameHeightPx,
            // Built for every film, not only for a trip that has a crossing:
            // whether one exists is a fact the timeline discovers, and a
            // compositor that had to be told in advance would be a second place
            // for the answer to be wrong. Unused films pay one sprite decode.
            crossingSubject: VehicleSubjectRenderer.make(
                style: plan.style, config: plan.config, subjectId: VehicleCatalog.crossingSubjectId
            ),
            // What flies a crossing the film has issued a boarding pass for
            // (ADR 2026-09-04). Built for every film for the same reason the
            // seagull is: whether one is needed is the timeline's discovery.
            flightSubject: VehicleSubjectRenderer.make(
                style: plan.style, config: plan.config, subjectId: VehicleCatalog.planeSubjectId
            )
        )
    }

    /// The render loop is CPU-bound; keep it off the main actor and hop back
    /// only for progress updates. Cancellation reads the lock-guarded flag
    /// directly on the render thread.
    private func runDetached(
        exporter: RecapExporter, videoURL: URL, gifURL: URL?, channel: RecapExportChannel
    ) async throws -> RecapExporter.Output? {
        let progress = channel.progress
        let shouldContinue = channel.shouldContinue
        return try await Task.detached(priority: .userInitiated) {
            // `RecapExporter` calls this once per frame (2,700+ times for a
            // typical film); this caps what crosses the main-actor boundary
            // to ~10/s rather than hopping on every one. `export`'s own
            // `progress` argument is still called every frame, unthrottled —
            // `RecapEncoderTests` reads that directly and sees no change.
            var lastEmitted: ContinuousClock.Instant?
            let throttled: (Double) -> Void = { fraction in
                let now = ContinuousClock.now
                if let lastEmitted, fraction < 1, now - lastEmitted < Self.progressInterval { return }
                lastEmitted = now
                Task { @MainActor in progress(fraction) }
            }
            // A GIF export renders only the frames the GIF keeps, and no MP4.
            if let gifURL {
                return try await exporter.exportGIF(
                    gifURL: gifURL, progress: throttled, shouldContinue: shouldContinue
                )
            }
            return try await exporter.export(videoURL: videoURL, progress: throttled, shouldContinue: shouldContinue)
        }.value
    }

    /// ~10/s. `nonisolated`: read from the detached render task above, off
    /// the main actor `RecapExportJob` otherwise runs on.
    private nonisolated static let progressInterval: Duration = .milliseconds(100)

    private func elapsed(since started: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }

    private func cleanup(videoURL: URL, gifURL: URL?) {
        try? FileManager.default.removeItem(at: videoURL)
        if let gifURL { try? FileManager.default.removeItem(at: gifURL) }
    }

    /// The style resource for each appearance — two frozen forks of
    /// OpenFreeMap's Liberty, bundled as `Config/RecapThemes/` assets.
    private static func openFreeMapStyleResource(for appearance: RecapAppearance) -> String {
        switch appearance {
        case .dark:  return "openfreemap-liberty-dark"
        case .light: return "openfreemap-liberty-light"
        }
    }

    /// The base map to render on: **OpenFreeMap + MapLibre**, with no Apple
    /// fallback (Chiu 2026-09-16; ADR to be written this round).
    ///
    /// 🔴 **If the tiles cannot be reached, the export fails.** It must never
    /// quietly fall back to Apple Maps, because that is the use the licence
    /// forbids (DPLA Attachment 6 §2.3/§2.5, ADR 2026-09-09). A fallback
    /// would reintroduce the exact problem this round exists to remove.
    ///
    /// **Failure paths** (MapLibre Native iOS 6.x):
    ///
    /// 1. *Style missing from bundle* — `resolvedNetworkStyleURL` throws
    ///    `themeNotFound`; `plan()` returns nil → `.failed`. Build-time invariant:
    ///    the two frozen styles are `project.yml` resources.
    /// 2. *Style file unwritable at render time* — `resolvedNetworkStyleURL` throws
    ///    an I/O error (full disk); same `.failed` path. Only possible if the temp
    ///    directory was purged or the disk filled between plan and render.
    /// 3. *Tile host unreachable* — two sub-cases measured:
    ///    - All hosts unreachable: VERIFIED 2026-09-17 (`TileFailureTests`),
    ///      `MLNMapSnapshotter` fires its completion with an `NSError`.
    ///    - Tiles only unreachable (sprite/glyphs/terrain reachable): VERIFIED
    ///      2026-09-17 (`TileFailureTests`): `MLNErrorDomain` code 6.
    ///    - Terrain only unreachable (vector tiles/sprite/glyphs reachable):
    ///      VERIFIED 2026-09-18 (`TileFailureTests`): the snapshotter still
    ///      errors. A terrain host failure blocks the film.
    ///    All three rethrow via `MapLibreSnapshotProvider.snapshot` →
    ///    `RecapExporter` propagates → `render()` catches → `.failed(message:)`.
    /// 4. *Tile host reachable but returns HTTP errors* (5xx, rate limit) — same
    ///    path as (3); INFERRED from MapLibre source (non-200 tile → load error).
    /// 5. *Partial tile failure* (some zoom levels cached, some not) — MapLibre
    ///    renders cached tiles and leaves unfetched areas transparent. The
    ///    snapshotter may complete *successfully* with a partially blank image. No
    ///    error is thrown. INFERRED — this is the one silent degradation: the film
    ///    would have blank map patches rather than failing. Mitigation: OpenFreeMap
    ///    serves a full planet, and the style pins `minzoom`/`maxzoom` to the ranges
    ///    the CDN covers, so partial failure requires a mid-render network drop —
    ///    unlikely and self-correcting on retry.
    ///
    /// **In-app maps stay MapKit and are not touched.** `TripDetailView` and
    /// `RecordingView` are sanctioned use: MapKit draws its own logo and legal
    /// link there. The licence problem is the *exported video*, not the live map.
    ///
    /// **The `.pmtiles` path is checked first, not dormant** (corrected
    /// 2026-09-24): a covering region overrides OpenFreeMap (fixed dark, OSM
    /// credit only). No region is bundled, and the side-load folders are searched
    /// only behind `RecapMapTiles.sideloadEnabled`. Never an Apple fallback.
    private static func snapshotProvider(
        for region: RecapMapRegion?, appearance: RecapAppearance, tripBox: GeoBox?
    ) throws -> MapRenderer {
        if let region,
           let styleURL = try? RecapMapStyle.resolvedStyleURL(
               styleResource: RecapMapTiles.styleResource,
               tilesURL: region.tilesURL,
               terrainURL: region.terrainURL
           ) {
            return MapLibreSnapshotProvider(
                styleURL: styleURL, fixedAppearance: .dark,
                attribution: RecapMapAttribution.openStreetMap
            )
        }
        let resource = openFreeMapStyleResource(for: appearance)
        let styleURL = try RecapMapStyle.resolvedNetworkStyleURL(
            styleResource: resource
        )
        let credit: String
        if let box = tripBox {
            credit = RecapMapAttribution.openFreeMap(
                minLat: box.minLat, maxLat: box.maxLat,
                minLon: box.minLon, maxLon: box.maxLon
            )
        } else {
            credit = RecapMapAttribution.openFreeMapBase
        }
        return MapLibreSnapshotProvider(
            styleURL: styleURL, appearance: appearance,
            attribution: credit
        )
    }
}

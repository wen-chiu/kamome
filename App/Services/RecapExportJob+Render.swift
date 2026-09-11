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
        let region = GeoBox.enclosing(composed.trip.route.map { (lat: $0.lat, lon: $0.lon) })
            .flatMap { RecapMapRegionResolver.resolve(covering: $0) }
        let provider = Self.snapshotProvider(for: region, appearance: request.appearance)
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
        // The region's extent drives the opening establishing shot and switches
        // the film onto content-derived pacing (Chiu 2026-07-30). No region means
        // Apple's map, no prologue, and the previous fixed duration.
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
        announce(timeline: timeline, trip: composed.trip, region: region,
                 config: exportConfig, appearance: appearance)
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
        timeline: LinearTimeline, trip: RecapTrip, region: RecapMapRegion?,
        config exportConfig: TrackingConfig.Export, appearance: RecapAppearance
    ) {
        // No covering region silently costs the souvenir map, the opening
        // prologue *and* content-derived pacing at once — a six-day trip
        // rendering as a 30-second Apple-map film looked like three separate bugs
        // and was one missing tile set.
        if region == nil {
            KamomeLog.recap.error("""
                no installed map region covers this trip — falling back to Apple's map, \
                no prologue, and the legacy \(exportConfig.targetDurationS, format: .fixed(precision: 0))s duration. \
                A trip spanning two regions hits this (handoff §"Trips that span two map regions").
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
        let exporter = RecapExporter(
            timeline: plan.timeline,
            compositor: compositor(composed: composed, plan: plan, resolver: resolver),
            provider: plan.provider,
            config: plan.config
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
            guard let output else {
                cleanup(videoURL: videoURL, gifURL: gifURL)
                return .cancelled
            }
            return try store(output: output, plan: plan, seconds: elapsed(since: started))
        } catch {
            cleanup(videoURL: videoURL, gifURL: gifURL)
            return .failed(message: String(describing: error))
        }
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
            try await exporter.export(
                videoURL: videoURL,
                gifURL: gifURL,
                progress: { fraction in
                    Task { @MainActor in progress(fraction) }
                },
                shouldContinue: shouldContinue
            )
        }.value
    }

    private func elapsed(since started: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }

    // MARK: - The record

    /// Moves the rendered file out of tmp and inserts its record, then resolves
    /// the stored path once. **This is what makes a completion nobody was
    /// looking at lose nothing** — the film exists before the outcome is
    /// published, so no screen has to be open for it to be kept.
    private func store(
        output: RecapExporter.Output, plan: Plan, seconds: Double
    ) throws -> RecapExportOutcome {
        // The primary file: GIF when the user chose GIF, MP4 otherwise.
        let primaryURL = output.gifURL ?? output.videoURL
        let record = try persistFilm(
            tempURL: primaryURL,
            format: output.gifURL != nil ? "gif" : "mp4",
            appearance: plan.appearance,
            durationS: plan.timeline.durationS,
            renderSeconds: seconds
        )
        // The other format's tmp file, if any, is cleaned up — only the chosen
        // format is stored.
        if output.gifURL != nil {
            try? FileManager.default.removeItem(at: output.videoURL)
        }
        guard let fileURL = FilmStore.resolvedURL(relativePath: record.relativePath) else {
            return .failed(message: String(localized: "recap_failed"))
        }
        return .finished(film: record, fileURL: fileURL)
    }

    private func persistFilm(
        tempURL: URL, format: String, appearance: RecapAppearance,
        durationS: Double, renderSeconds: Double
    ) throws -> FilmRecord {
        let relativePath = try FilmStore.moveToStore(from: tempURL)
        let fileURL = FilmStore.resolvedURL(relativePath: relativePath)
        let fileBytes = fileURL.flatMap(FilmStore.fileSize(at:))
        let record = FilmRecord(
            id: UUID().uuidString,
            tripId: request.tripId,
            relativePath: relativePath,
            format: format,
            createdAt: Date.now.timeIntervalSince1970,
            durationS: durationS,
            renderSeconds: renderSeconds,
            appearance: appearance.rawValue,
            recapMode: config.export.recapMode.rawValue,
            fileBytes: fileBytes
        )
        try repository.saveFilm(record)
        KamomeLog.recap.notice(
            "film stored: \(record.relativePath, privacy: .public) · \(fileBytes ?? 0) bytes"
        )
        return record
    }

    private func cleanup(videoURL: URL, gifURL: URL?) {
        try? FileManager.default.removeItem(at: videoURL)
        if let gifURL { try? FileManager.default.removeItem(at: gifURL) }
    }

    /// The base map to render on: the Kamome souvenir map when vector tiles
    /// covering **this trip** are on hand, Apple's otherwise.
    ///
    /// This is the §3 "MapLibre production switch", made conditional on purpose.
    /// A `.pmtiles` file covers a bounded region and there is no planet-sized
    /// file to bundle, so until tile provisioning exists (spec P7) a hard
    /// retirement of MapKit would render blank frames for any trip outside the
    /// installed regions. Falling back keeps every trip exportable; the moment
    /// tiles for its area are present the film is the designed one.
    ///
    /// `appearance` is what the *device* asked for. Only Apple Maps can honour
    /// it; the souvenir map answers `.dark` through its capabilities and the
    /// caller resolves the two.
    private static func snapshotProvider(
        for region: RecapMapRegion?, appearance: RecapAppearance
    ) -> MapRenderer {
        guard let region,
              let styleURL = try? RecapMapStyle.resolvedStyleURL(
                  styleResource: RecapMapTiles.styleResource,
                  tilesURL: region.tilesURL,
                  // Hillshade when a DEM for this area is installed; the style
                  // strips the layer when it is not (Chiu 2026-07-30).
                  terrainURL: region.terrainURL
              )
        else { return MapKitSnapshotProvider(appearance: appearance) }
        return MapLibreSnapshotProvider(styleURL: styleURL)
    }
}

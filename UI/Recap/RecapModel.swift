import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer
import Observation

/// Backs S5: builds recap content from the trip DB, runs `RecapExporter`
/// off the main actor, and publishes progress / the finished files.
@Observable
@MainActor
final class RecapModel {
    enum Format: String, CaseIterable {
        case mp4
        case gif
    }

    enum Phase: Equatable {
        case idle
        case rendering(progress: Double)
        case finished(shareURL: URL, renderSeconds: Double)
        case failed(message: String)
    }

    /// Set on main, read from the render thread every frame — a plain Bool
    /// on the model would need actor hops the render loop can't make.
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.withLock { value = true }
        }

        var isSet: Bool {
            lock.withLock { value }
        }
    }

    /// Photo overlays only (decisions.md 2026-07-18 recap-chrome, Chiu):
    /// off removes stop photo cards; title/end cards always render.
    var photosEnabled = true
    var format: Format = .mp4
    private(set) var phase: Phase = .idle

    /// Set when warming could not load every deck photo — see
    /// `PhotoLibraryPhotoResolver.WarmSummary`. Surfaced rather than swallowed:
    /// the symptom is blank cards in a finished film, which reads as a rendering
    /// bug rather than as photos that are not on this device.
    private(set) var photoShortfall: PhotoLibraryPhotoResolver.WarmSummary?

    /// What road reconstruction managed for this trip, surfaced for the same
    /// reason `photoShortfall` is (2026-08-15): a film whose legs draw dashed
    /// looks like a rendering bug, and the four reasons it can happen — no road
    /// route exists, the provider could not be reached, it refused for load, or
    /// the budget ran out — need four different responses from the user. Only
    /// one of them means "this is simply what the journey looks like".
    private(set) var routing: RouteMatchReport?

    private let tripId: String
    private let config: TrackingConfig
    private let repository: TripRepository
    private var cancelFlag = CancelFlag()
    private var exportTask: Task<Void, Never>?
    /// Holds the screen awake and a background-task assertion for the duration
    /// of a render (2026-08-15): a locked screen or a brief app switch used to
    /// kill an export outright, and a film takes minutes.
    private let lifecycle = ExportLifecycleGuard()

    init(tripId: String, config: TrackingConfig, repository: TripRepository) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
    }

    var isRendering: Bool {
        if case .rendering = phase { return true } else { return false }
    }

    /// Starts the render. **`appearance` is captured by the caller at the tap**,
    /// not read here.
    ///
    /// This is the composition boundary in the sense `Docs/decisions.md`
    /// 2026-08-15 means it: the place where a trip becomes *a specific film*. The
    /// ADR requires export variation to enter as an explicit value chosen here
    /// and held constant, never sampled from the environment while rendering —
    /// written for the photo-selection seed, and binding on this for the same
    /// reason. The appearance is ambient device state, so left unbound it would
    /// be exactly the coin toss the ADR names: a film that changes if the user
    /// toggles dark mode mid-render, and a failing golden frame nobody can
    /// reproduce.
    ///
    /// So it arrives as a parameter from `RecapView`, which reads
    /// `@Environment(\.colorScheme)` on the main actor at the moment the button
    /// is pressed, and from here it is a `let` that crosses into the detached
    /// render task unchanged.
    ///
    /// **What is not yet met:** the ADR also says a seed that is not stored is
    /// not a seed. There is no export record in the schema to store this in — the
    /// seed feature that would create one is deferred by the same ADR — so the
    /// resolved value goes into the film's log line below and the gap is written
    /// down (`Docs/eng-session-appearance.md` §4.1) rather than assumed away.
    func startExport(appearance: RecapAppearance) {
        guard !isRendering else { return }
        cancelFlag = CancelFlag()
        phase = .rendering(progress: 0)
        // Taken before the render starts and released on every exit below —
        // finished, cancelled, failed. On expiry the export cancels itself at a
        // frame boundary rather than being suspended mid-write.
        lifecycle.begin { [weak self] in
            KamomeLog.recap.error("export: the background assertion expired — cancelling at the next frame")
            self?.cancelFlag.set()
        }
        exportTask = Task { [weak self] in
            await self?.runExport(appearance: appearance)
            self?.lifecycle.end()
        }
    }

    func cancel() {
        cancelFlag.set()
    }

    // MARK: - Pipeline

    private func runExport(appearance requested: RecapAppearance) async {
        // Best-effort §4.4 matching before composing: an instant no-op while
        // base_url is empty, and now bounded by `matching.trip_budget_s` for the
        // whole trip rather than only per request. The replay should follow
        // roads whenever a server is around.
        //
        // Through the coordinator, so a film started seconds after an import
        // **joins** that import's run instead of starting a second one over the
        // same legs (2026-08-15). Concurrent runs were verified not to corrupt
        // anything — `DatabaseQueue` serialises, and the write is one column
        // that does not read itself — but two runs mean two budgets and two
        // verdicts for one trip, and the screen can only show one.
        routing = await RouteMatchCoordinator.shared.result(
            tripId: tripId,
            service: RouteMatchService(repository: repository, matching: config.matching)
        )
        guard let detail = try? repository.detail(tripId: tripId) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        let stats = TripStats.from(jsonString: detail.trip.statsJson)
        // Deck photo refs are selected here (data); the resolver loads the
        // bitmaps. Refs stay out of the render size.
        let photoRefs = photosEnabled ? selectStopPhotoRefs(detail: detail) : [:]
        let deck = RecapDeck(
            photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS,
            labelLeadS: config.export.deckLabelLeadS, photoMinHoldS: config.export.deckPhotoMinHoldS
        )
        // Typed legs (Fable review 2026-07-26): each stretch reaches the film
        // with its own transport mode and provenance, so a leg Kamome could not
        // reconstruct renders visibly as a guess rather than as road (PD-1).
        let legs = RecapComposer.legs(
            from: detail.segments,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        guard let trip = RecapComposer.trip(
            trip: detail.trip,
            legs: legs,
            stops: detail.stops,
            stats: stats,
            photosByStop: photoRefs,
            deck: deck,
            stopHoldS: config.export.stopHoldS,
            rawPhotoCounts: rawPhotoCounts(detail: detail),
            favoriteCounts: favoriteCounts(detail: detail),
            weighting: config.export,
            // For the Journey Card's two dates — `taken_at` lives only on these
            // rows, and neither the timeline nor the renderer may go looking for
            // a date (`RecapTrip.crossingDates`).
            photos: detail.photos,
            everyLegRoutabilityEstablished:
                RecapComposer.everyLegRoutabilityEstablished(detail.segments)
        ) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        // The film type is derived, never stored (`RecapFilmType`), so it is
        // resolved here — after routing has had whatever time it has had — and
        // announced. `.unknown` renders the local film, and saying so is the
        // difference between a declared fallback and a silent one: a trip whose
        // crossing has not been routed yet looks exactly like a trip with no
        // crossing, and only this line tells them apart (`Arch.md` §6).
        let journeyCount = RecapFilmType.distinctJourneyCount(legs: trip.legs)
        switch trip.filmType {
        case .unknown:
            KamomeLog.recap.notice(
                "recap: film type UNKNOWN — routing has not answered for every leg, so a crossing may not have been found; rendering the local film and a later export may differ"
            )
        case .multiRegion:
            KamomeLog.recap.notice(
                "recap: film type multi-region, \(journeyCount, privacy: .public) local journeys — that film is not built, rendering the local one"
            )
        case .local:
            KamomeLog.recap.notice("recap: film type local — one journey, no crossing")
        case .oneDestination:
            KamomeLog.recap.notice("recap: film type one destination abroad — 2 local journeys")
        }

        // Layer 3 pipeline. The map stays north-up (product decision, Chiu
        // 2026-07-25) and the 8-direction car sprite carries the heading, so the
        // subject looks identical whichever base map renders underneath.
        //
        // `follow_heading_up` ships false; the capability check only stops a
        // renderer that cannot rotate from being handed a bearing it would drop,
        // should the flag ever be turned on.
        // One question, asked once (`RecapMapRegion` is the seam): which region
        // covers this trip? Its tiles feed the renderer, its DEM feeds hillshade,
        // and its extent is what the opening establishing shot frames.
        let region = GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) })
            .flatMap { RecapMapRegionResolver.resolve(covering: $0) }
        let provider = Self.snapshotProvider(for: region, appearance: requested)
        // Resolved once, here, and never asked again — the substrate can veto the
        // device's choice (the MapLibre souvenir map has no light variant), and
        // the palette below must follow whatever the *base map* actually is, not
        // what the device asked for. Same shape as the heading-up line under it:
        // a capability the renderer declares rather than silently ignores.
        let appearance = provider.capabilities.appearance(honouring: requested)
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
            trip: trip, config: exportConfig, establishing: establishing,
            // The capability layer reaching the film's form: the substrate says
            // how wide a frame it can draw, and the type-2 opening picks between
            // its two forms accordingly rather than discovering the answer one
            // snapshot at a time (`CrossingFraming`).
            substrateMaxLongitudeDeg: provider.capabilities.maxFramableLongitudeDeg
        ) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        // The single most useful line in the log when a film comes out wrong
        // (2026-08-01). No covering region silently costs the souvenir map, the
        // opening prologue *and* content-derived pacing at once — a six-day trip
        // rendering as a 30-second Apple-map film looked like three separate bugs
        // and was one missing tile set.
        if region == nil {
            KamomeLog.recap.error("""
                no installed map region covers this trip — falling back to Apple's map, \
                no prologue, and the legacy \(exportConfig.targetDurationS, format: .fixed(precision: 0))s duration. \
                A trip spanning two regions hits this (handoff §"Trips that span two map regions").
                """)
        }
        // The appearance is on this line because it is the only record of it.
        // With no export table to persist it in, the log is where a finished
        // film's palette can still be recovered from — which is the difference
        // between "we do not store it yet" and "we cannot tell you what you got".
        KamomeLog.recap.notice("""
            film: \(timeline.durationS, format: .fixed(precision: 1))s · \
            \(timeline.frameCount) frames · opening \(timeline.openingS, format: .fixed(precision: 1))s · \
            \(trip.stops.count) stops · \(trip.legs.filter(\.provenance.isInferred).count)/\(trip.legs.count) legs dashed · \
            \(appearance.rawValue, privacy: .public) appearance\
            \(appearance == requested ? "" : " (device asked for \(requested.rawValue), the substrate is fixed)", privacy: .public)
            """)
        let style = RecapStyle.modernMinimal(appearance).withEndCard(config.export.endCardStyle)
        let resolver = PhotoLibraryPhotoResolver()
        await warmDeckPhotos(trip: trip, style: style, resolver: resolver)
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(
                style: style, config: exportConfig, subjectId: detail.trip.vehicle
            ),
            overlay: RecapOverlayRenderer(style: style, resolver: resolver),
            style: style,
            widthPx: config.export.frameWidthPx,
            heightPx: config.export.frameHeightPx,
            // Built for every film, not only for a trip that has a crossing:
            // whether one exists is a fact the timeline discovers, and a
            // compositor that had to be told in advance would be a second place
            // for the answer to be wrong. Unused films pay one sprite decode.
            crossingSubject: VehicleSubjectRenderer.make(
                style: style, config: exportConfig, subjectId: VehicleCatalog.crossingSubjectId
            )
        )
        let exporter = RecapExporter(
            timeline: timeline,
            compositor: compositor,
            provider: provider,
            config: exportConfig
        )

        let scratch = FileManager.default.temporaryDirectory
        let stamp = Int(Date.now.timeIntervalSince1970)
        let videoURL = scratch.appendingPathComponent("kamome-recap-\(stamp).mp4")
        let gifURL = format == .gif ? scratch.appendingPathComponent("kamome-recap-\(stamp).gif") : nil
        try? FileManager.default.removeItem(at: videoURL)

        let started = ContinuousClock.now
        do {
            let output = try await runDetached(exporter: exporter, videoURL: videoURL, gifURL: gifURL)
            guard let output else {
                cleanup(videoURL: videoURL, gifURL: gifURL)
                phase = .idle
                return
            }
            let elapsed = ContinuousClock.now - started
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) * 1e-18
            phase = .finished(shareURL: output.gifURL ?? output.videoURL, renderSeconds: seconds)
        } catch {
            cleanup(videoURL: videoURL, gifURL: gifURL)
            phase = .failed(message: String(describing: error))
        }
    }

    /// The render loop is CPU-bound; keep it off the main actor and hop back
    /// only for progress updates. Cancellation reads the lock-guarded flag
    /// directly on the render thread.
    private func runDetached(
        exporter: RecapExporter,
        videoURL: URL,
        gifURL: URL?
    ) async throws -> RecapExporter.Output? {
        let model = self
        let flag = cancelFlag
        return try await Task.detached(priority: .userInitiated) {
            try await exporter.export(
                videoURL: videoURL,
                gifURL: gifURL,
                progress: { fraction in
                    Task { @MainActor in
                        if model.isRendering { model.phase = .rendering(progress: fraction) }
                    }
                },
                shouldContinue: { !flag.isSet }
            )
        }.value
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
    /// The region is chosen per trip (Fable review 2026-07-26): the §6 gate is
    /// three real trips in three places, side-loaded over Finder, so the lookup
    /// matches each render against what it actually covers.
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

    private func cleanup(videoURL: URL, gifURL: URL?) {
        try? FileManager.default.removeItem(at: videoURL)
        if let gifURL { try? FileManager.default.removeItem(at: gifURL) }
    }

    // MARK: - Photos

    /// Selects each stop's deck photo *refs* (§5): highlight first, then the rest
    /// evenly spread across the visit, capped at `deck_max_photos` so a
    /// photo-dense stop samples the whole visit rather than just its first burst
    /// (`PhotoDeckSelector`, shared with import). Pure data — no PhotoKit, no
    /// bitmaps; the render layer resolves the refs.
    /// Decodes every deck photo up front, so a stop that will render a blank card
    /// is reported before the export rather than discovered in the finished film.
    /// iCloud-optimised originals are the usual cause (`PhotoLibraryPhotoResolver`).
    private func warmDeckPhotos(
        trip: RecapTrip, style: RecapStyle, resolver: PhotoLibraryPhotoResolver
    ) async {
        photoShortfall = nil
        guard photosEnabled else { return }
        let targetPx = Int(CGFloat(config.export.frameWidthPx) * style.deckPhotoMaxWidthFraction)
        let warmed = await resolver.warm(trip.stops.flatMap(\.photos), targetPx: max(targetPx, 1))
        guard warmed.missing > 0 else { return }
        photoShortfall = warmed
        KamomeLog.recap.error("""
            \(warmed.missing) of \(warmed.requested) deck photos could not be loaded \
            (\(warmed.inCloud) are in iCloud, not on this device) — those stops will render \
            blank cards. The route is unaffected: EXIF place and time need no download.
            """)
    }

    /// Every stop's **raw** photograph count — what `StopWeighting` judges the
    /// place on, before `deck_max_photos` caps what the film can show.
    private func rawPhotoCounts(detail: TripRepository.TripDetail) -> [String: Int] {
        var counts: [String: Int] = [:]
        for photo in detail.photos {
            guard let stopId = photo.stopId else { continue }
            counts[stopId, default: 0] += 1
        }
        return counts
    }

    /// Favourited photographs per stop — `PHAsset.isFavorite` at import time,
    /// stored in `is_highlight`. Zero on trips imported before that landed.
    private func favoriteCounts(detail: TripRepository.TripDetail) -> [String: Int] {
        var counts: [String: Int] = [:]
        for photo in detail.photos where photo.isHighlight != 0 {
            guard let stopId = photo.stopId else { continue }
            counts[stopId, default: 0] += 1
        }
        return counts
    }

    private func selectStopPhotoRefs(detail: TripRepository.TripDetail) -> [String: [PhotoRef]] {
        var result: [String: [PhotoRef]] = [:]
        for stop in detail.stops {
            let ordered = detail.photos
                .filter { $0.stopId == stop.id }
                .sorted { lhs, rhs in
                    if lhs.isHighlight != rhs.isHighlight { return lhs.isHighlight > rhs.isHighlight }
                    return (lhs.takenAt ?? 0) < (rhs.takenAt ?? 0)
                }
                .map(\.phAssetId)
            let selected = PhotoDeckSelector.evenlySpread(
                ordered,
                min: config.photoImport.deckMinPhotos,
                max: config.photoImport.deckMaxPhotos
            )
            if !selected.isEmpty { result[stop.id] = selected.map(PhotoRef.asset) }
        }
        return result
    }
}

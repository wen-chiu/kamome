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

    private let tripId: String
    private let config: TrackingConfig
    private let repository: TripRepository
    private var cancelFlag = CancelFlag()
    private var exportTask: Task<Void, Never>?

    init(tripId: String, config: TrackingConfig, repository: TripRepository) {
        self.tripId = tripId
        self.config = config
        self.repository = repository
    }

    var isRendering: Bool {
        if case .rendering = phase { return true } else { return false }
    }

    func startExport() {
        guard !isRendering else { return }
        cancelFlag = CancelFlag()
        phase = .rendering(progress: 0)
        exportTask = Task { [weak self] in
            await self?.runExport()
        }
    }

    func cancel() {
        cancelFlag.set()
    }

    // MARK: - Pipeline

    private func runExport() async {
        // Best-effort §4.4 matching before composing: idempotent, bounded by
        // matching.timeout_s per request, an instant no-op while base_url is
        // empty. The replay should follow roads whenever a server is around.
        await RouteMatchService(repository: repository, config: config).matchTrip(tripId: tripId)
        guard let detail = try? repository.detail(tripId: tripId) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        let stats = TripStats.from(jsonString: detail.trip.statsJson)
        // Deck photo refs are selected here (data); the resolver loads the
        // bitmaps. Refs stay out of the render size.
        let photoRefs = photosEnabled ? selectStopPhotoRefs(detail: detail) : [:]
        let deck = RecapDeck(photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS, labelLeadS: config.export.deckLabelLeadS)
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
            stopHoldS: config.export.stopHoldS
        ) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        // Layer 3 pipeline. The map stays north-up (product decision, Chiu
        // 2026-07-25) and the 8-direction car sprite carries the heading, so the
        // subject looks identical whichever base map renders underneath.
        //
        // `follow_heading_up` ships false; the capability check only stops a
        // renderer that cannot rotate from being handed a bearing it would drop,
        // should the flag ever be turned on.
        let provider = Self.snapshotProvider(covering: trip.route)
        let exportConfig = config.export.withFollowHeadingUp(
            config.export.followHeadingUp && provider.capabilities.supportsHeadingUp
        )
        guard let timeline = LinearTimeline(trip: trip, config: exportConfig) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        let style = RecapStyle.modernMinimal
        let resolver = PhotoLibraryPhotoResolver()
        if photosEnabled {
            let targetPx = Int(CGFloat(config.export.frameWidthPx) * style.deckPhotoMaxWidthFraction)
            await resolver.warm(trip.stops.flatMap(\.photos), targetPx: max(targetPx, 1))
        }
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: resolver),
            style: style,
            widthPx: config.export.frameWidthPx,
            heightPx: config.export.frameHeightPx
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
    private static func snapshotProvider(covering route: [RecapCoordinate]) -> MapRenderer {
        guard let bounds = GeoBox.enclosing(route.map { (lat: $0.lat, lon: $0.lon) }),
              let tiles = RecapMapTiles.tilesURL(covering: bounds),
              let styleURL = try? RecapMapStyle.resolvedStyleURL(
                  styleResource: RecapMapTiles.styleResource, tilesURL: tiles
              )
        else { return MapKitSnapshotProvider() }
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

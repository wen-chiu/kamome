import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer
import Observation
import Photos

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
        // Deck photo refs are selected here (data); bitmaps are loaded below only
        // for the current compositor bridge. Refs stay out of the render size.
        let photoRefs = photosEnabled ? selectStopPhotoRefs(detail: detail) : [:]
        let deck = RecapDeck(photoHoldS: config.export.deckPhotoHoldS, zoomS: config.export.deckZoomS, labelLeadS: config.export.deckLabelLeadS)
        let route = RecapComposer.route(
            from: detail.segments,
            epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        guard let trip = RecapComposer.trip(
            trip: detail.trip,
            route: route,
            stops: detail.stops,
            stats: stats,
            photosByStop: photoRefs,
            deck: deck,
            stopHoldS: config.export.stopHoldS
        ) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        let routePoints = trip.route.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stopPoints = trip.stops.map { CameraPath.Point(lat: $0.coordinate.lat, lon: $0.coordinate.lon) }
        guard let path = CameraPath(
            route: routePoints, stops: stopPoints, config: config.export,
            stopHoldsS: trip.stops.map(\.dwellS)
        ) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }

        // Bridge the style-independent RecapTrip into today's compositor inputs:
        // resolve refs → bitmaps and generate the QR from shareURL (both move into
        // the OverlayRenderer when the render-layers migration lands).
        let stopImages = photosEnabled ? await loadDeckImages(refs: photoRefs) : [:]
        let events = OverlayTimeline.build(holds: path.holds, config: config.export, photosEnabled: photosEnabled)
        let compositor = RecapFrameCompositor(
            path: path,
            events: events,
            stopCards: zip(trip.stops, detail.stops).map { tripStop, record in
                RecapFrameCompositor.StopCard(
                    name: tripStop.name, dayLabel: tripStop.dayLabel, detail: tripStop.detail,
                    photos: stopImages[record.id] ?? []
                )
            },
            titleCard: RecapFrameCompositor.TitleCard(title: trip.title, subtitle: trip.subtitle),
            endCard: RecapFrameCompositor.EndCard(
                statsLines: trip.statsLines, callToAction: trip.callToAction,
                qrCode: RecapQRCode.image(for: trip.shareURL, sidePx: Int(RecapStyle().qrSidePx))
            ),
            widthPx: config.export.frameWidthPx,
            heightPx: config.export.frameHeightPx,
            deck: deck
        )
        let exporter = RecapExporter(
            path: path,
            compositor: compositor,
            provider: MapKitSnapshotProvider(),
            config: config.export
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

    /// Resolves selected refs → bitmaps for the current compositor bridge
    /// (moves into the `OverlayRenderer` at the render-layers migration). Needs
    /// library access — undetermined means no photos; never prompt here.
    private func loadDeckImages(refs: [String: [PhotoRef]]) async -> [String: [CGImage]] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return [:] }
        var result: [String: [CGImage]] = [:]
        for (stopID, stopRefs) in refs {
            var images: [CGImage] = []
            for case let .asset(assetId) in stopRefs {
                if let image = await loadImage(assetId: assetId) { images.append(image) }
            }
            if !images.isEmpty { result[stopID] = images }
        }
        return result
    }

    private func loadImage(assetId: String) async -> CGImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            var resumed = false
            // Decoded for the deck's enlarged peak (~0.64 × 1080-wide card); the
            // compositor aspect-fills, so a generous square covers any crop.
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 900, height: 900),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}

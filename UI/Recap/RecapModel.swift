import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
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
        guard let detail = try? repository.detail(tripId: tripId) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }
        let stats = TripStats.from(jsonString: detail.trip.statsJson)
        // Stop-card photos are only needed when photo overlays are on.
        let photos = photosEnabled ? await loadStopPhotos(detail: detail) : [:]
        guard let content = RecapComposer.content(
            trip: detail.trip,
            segments: detail.segments,
            stops: detail.stops,
            stats: stats,
            photosByStop: photos
        ), let path = CameraPath(route: content.route, stops: content.stops, config: config.export) else {
            phase = .failed(message: String(localized: "recap_failed"))
            return
        }

        let events = OverlayTimeline.build(holds: path.holds, config: config.export, photosEnabled: photosEnabled)
        let compositor = RecapFrameCompositor(
            path: path,
            events: events,
            stopCards: content.stopCards,
            titleCard: content.titleCard,
            endCard: content.endCard,
            widthPx: config.export.frameWidthPx,
            heightPx: config.export.frameHeightPx
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

    /// Highlight photo first, else the stop's earliest photo. Card size is
    /// the frame's photo square (~450 px) — no full-res decodes.
    private func loadStopPhotos(detail: TripRepository.TripDetail) async -> [String: CGImage] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return [:] }
        var result: [String: CGImage] = [:]
        for stop in detail.stops {
            let candidates = detail.photos
                .filter { $0.stopId == stop.id }
                .sorted { lhs, rhs in
                    if lhs.isHighlight != rhs.isHighlight { return lhs.isHighlight > rhs.isHighlight }
                    return (lhs.takenAt ?? 0) < (rhs.takenAt ?? 0)
                }
            guard let chosen = candidates.first else { continue }
            if let image = await loadImage(assetId: chosen.phAssetId) {
                result[stop.id] = image
            }
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
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 450, height: 450),
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

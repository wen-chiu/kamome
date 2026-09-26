import Foundation
import KamomeConfig
import KamomePersistence
import Observation
import Photos

/// **One background analysis run per trip** (ADR 2026-09-25 (d)) — the same
/// single-flight shape as `RouteMatchCoordinator`, with the opposite contract:
/// **nothing ever waits for it.** The export and the photo picker read whatever
/// rows exist; until every photograph at a stop has one, the trip picks by
/// time exactly as before, and the pick changes once, when the run completes.
///
/// Each photograph's row is written as soon as it is analysed, so a run the
/// system kills (or a delete cancels) resumes where it stopped on the next
/// start. Started after an import and whenever a trip is opened, which also
/// catches every trip imported before this existed.
@MainActor
@Observable
final class PhotoAnalysisCoordinator {
    static let shared = PhotoAnalysisCoordinator()

    /// Photographs analysed so far in the run in flight, per trip.
    private(set) var progress: [String: (done: Int, total: Int)] = [:]

    private var running: [String: Task<Void, Never>] = [:]
    private var flags: [String: SharedFlag] = [:]
    /// Runs finished per trip — what an open screen observes to re-read its
    /// decks, so the export sheet never shows a pick the export will not use.
    private(set) var finishedRuns: [String: Int] = [:]

    /// Runs that stepped aside for a film, resumed when it ends (arch review
    /// 2026-09-26 round 2 point 5). Vision at background priority was only
    /// INFERRED not to slow a render (ADR 2026-09-25 (d)); not running beside
    /// one needs no measurement. Rows already written stay, so nothing is redone.
    private var deferred: [String: (repository: TripRepository, config: TrackingConfig.PhotoAnalysis)] = [:]
    private let exports: RecapExportCoordinator

    init(exports: RecapExportCoordinator = .shared) {
        self.exports = exports
        exports.whenIdle { [weak self] in self?.resumeDeferred() }
    }

    /// Whether this trip's analysis is waiting for a film to finish.
    func isDeferred(_ tripId: String) -> Bool { deferred[tripId] != nil }

    /// Starts analysing the trip's photographs if nothing is running for it.
    /// Returns at once. Without photo-library access it does nothing: a
    /// denied read must not be recorded as "these photographs have no pixels".
    func start(tripId: String, repository: TripRepository, config: TrackingConfig.PhotoAnalysis) {
        guard running[tripId] == nil else { return }
        guard !exports.rendering.isSet else {
            deferred[tripId] = (repository, config)
            return
        }
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited else { return }
        let pending = Stored.read("assetsNeedingAnalysis") {
            try repository.assetsNeedingAnalysis(tripId: tripId, version: PhotoAnalysisVersion.current)
        } ?? []
        guard !pending.isEmpty else { return }

        let flag = SharedFlag()
        flags[tripId] = flag
        progress[tripId] = (0, pending.count)
        let rendering = exports.rendering
        running[tripId] = Task { [weak self] in
            // Background priority: this is never what the person is waiting on,
            // and an export rendering at the same time must not feel it.
            let (done, yielded) = await Task.detached(priority: .background) {
                await Self.run(pending, repository: repository, config: config, flag: flag, rendering: rendering) { done in
                    Task { @MainActor in self?.progress[tripId] = (done, pending.count) }
                }
            }.value
            // Counts only — which photographs, never where (§0).
            let paused = yielded ? " — paused for a film, resumes when it ends" : ""
            KamomeLog.importing.notice(
                "photo analysis: \(done) of \(pending.count) photographs analysed\(paused, privacy: .public)"
            )
            self?.finish(tripId: tripId)
            // Not if the trip was deleted meanwhile (`cancel` set the flag).
            guard yielded, !flag.isSet, let self else { return }
            self.deferred[tripId] = (repository, config)
            // The film may already have ended before this line ran, in which
            // case its idle call found nothing waiting: pick up now.
            if !self.exports.rendering.isSet { self.resumeDeferred() }
        }
    }

    private func resumeDeferred() {
        let waiting = deferred
        deferred = [:]
        for (tripId, run) in waiting {
            start(tripId: tripId, repository: run.repository, config: run.config)
        }
    }

    /// Stops the run before its next photograph; rows already written stay.
    func cancel(tripId: String) {
        flags[tripId]?.set()
        deferred[tripId] = nil
    }

    func isRunning(_ tripId: String) -> Bool {
        running[tripId] != nil
    }

    private func finish(tripId: String) {
        running[tripId] = nil
        flags[tripId] = nil
        progress[tripId] = nil
        finishedRuns[tripId, default: 0] += 1
    }

    /// Analyses `assetIds` one at a time, writing each row as it lands.
    /// Returns how many were written, and whether it stopped for a film.
    private nonisolated static func run(
        _ assetIds: [String], repository: TripRepository, config: TrackingConfig.PhotoAnalysis,
        flag: SharedFlag, rendering: SharedFlag, progress: @escaping @Sendable (Int) -> Void
    ) async -> (done: Int, yielded: Bool) {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var assets: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }
        var done = 0
        for assetId in assetIds {
            guard !flag.isSet, !Task.isCancelled else { break }
            // A film started: step aside and resume when it ends.
            guard !rendering.isSet else { return (done, true) }
            let result = await PhotoAnalyzer.analyze(asset: assets[assetId], assetId: assetId, config: config)
            guard Stored.write("savePhotoAnalysis", { try repository.savePhotoAnalysis(result.record) }) else { break }
            done += 1
            progress(done)
        }
        return (done, false)
    }
}

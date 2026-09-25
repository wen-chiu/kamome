import Foundation
import KamomeConfig
import KamomePersistence
import Observation
import Photos

/// **One background analysis run per trip** (ADR 2026-09-25 (c)) — the same
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
    private var flags: [String: CancelFlag] = [:]
    /// Runs finished per trip — what an open screen observes to re-read its
    /// decks, so the export sheet never shows a pick the export will not use.
    private(set) var finishedRuns: [String: Int] = [:]

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    private init() {}

    /// Starts analysing the trip's photographs if nothing is running for it.
    /// Returns at once. Without photo-library access it does nothing: a
    /// denied read must not be recorded as "these photographs have no pixels".
    func start(tripId: String, repository: TripRepository, config: TrackingConfig.PhotoAnalysis) {
        guard running[tripId] == nil else { return }
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited else { return }
        let pending = Stored.read("assetsNeedingAnalysis") {
            try repository.assetsNeedingAnalysis(tripId: tripId, version: PhotoAnalysisVersion.current)
        } ?? []
        guard !pending.isEmpty else { return }

        let flag = CancelFlag()
        flags[tripId] = flag
        progress[tripId] = (0, pending.count)
        running[tripId] = Task { [weak self] in
            // Background priority: this is never what the person is waiting on,
            // and an export rendering at the same time must not feel it.
            let done = await Task.detached(priority: .background) {
                await Self.run(pending, repository: repository, config: config, flag: flag) { done in
                    Task { @MainActor in self?.progress[tripId] = (done, pending.count) }
                }
            }.value
            // Counts only — which photographs, never where (§0).
            KamomeLog.importing.notice("photo analysis: \(done) of \(pending.count) photographs analysed")
            self?.finish(tripId: tripId)
        }
    }

    /// Stops the run before its next photograph; rows already written stay.
    func cancel(tripId: String) {
        flags[tripId]?.set()
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
    /// Returns how many were written.
    private nonisolated static func run(
        _ assetIds: [String], repository: TripRepository, config: TrackingConfig.PhotoAnalysis,
        flag: CancelFlag, progress: @escaping @Sendable (Int) -> Void
    ) async -> Int {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var assets: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }
        var done = 0
        for assetId in assetIds {
            guard !flag.isSet, !Task.isCancelled else { break }
            let result = await PhotoAnalyzer.analyze(asset: assets[assetId], assetId: assetId, config: config)
            guard Stored.write("savePhotoAnalysis", { try repository.savePhotoAnalysis(result.record) }) else { break }
            done += 1
            progress(done)
        }
        return done
    }
}

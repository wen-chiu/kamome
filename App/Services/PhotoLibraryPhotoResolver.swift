import CoreGraphics
import Foundation
import ImageIO
import KamomeExportEngine
import Photos

/// PhotoKit-backed `RecapPhotoResolving` — the render layer's window onto the
/// photo library, confining `import Photos` to the app (the export core stays
/// SDK-free and deterministic). PhotoKit fetches are async, but the overlay
/// renderer resolves a `PhotoRef` synchronously once per frame, so every ref is
/// loaded into an in-memory cache by `warm(_:targetPx:)` before compositing
/// starts; the (detached) render thread then only reads the cache. Missing
/// library access or an absent asset resolves to nil — the deck still blooms its
/// matte (replaces `RecapModel.loadDeckImages`).
final class PhotoLibraryPhotoResolver: RecapPhotoResolving, @unchecked Sendable {
    /// What warming actually managed to load.
    ///
    /// Reported rather than inferred, because the failure it exists for is
    /// **silent**: an asset whose full-size data lives in iCloud rather than on
    /// the device resolves to nil, and the deck blooms an empty grey matte. The
    /// route is unaffected — place and time are metadata that need no download —
    /// so a trip imports perfectly and then renders a film of blank cards, with
    /// nothing anywhere saying why (Chiu 2026-08-02).
    struct WarmSummary: Equatable {
        let requested: Int
        let resolved: Int
        /// Of the failures, how many PhotoKit attributed to the asset being in
        /// iCloud — i.e. photos Kamome asked iCloud for and did not get.
        let inCloud: Int
        /// How many of `resolved` had to come down from iCloud. Zero for a trip
        /// whose photos are all on the device; logged, never shown.
        var downloaded = 0

        var missing: Int { max(requested - resolved, 0) }
    }

    /// The iCloud phase of a warm, for the export screen. `total` is only the
    /// photos that are **not on this device** — a photo PhotoKit already holds
    /// locally is never counted, never requested over the network.
    struct PreloadProgress: Equatable, Sendable {
        /// Photos whose download has finished, successfully or not.
        let completed: Int
        let total: Int
        /// Overall 0…1, including the photo currently downloading.
        let fraction: Double
    }

    private let lock = NSLock()
    private var cache: [String: CGImage] = [:]

    /// Loads every ref's bitmap into the cache. Call once, off the render
    /// thread, before compositing. Needs library access — undetermined means no
    /// photos; never prompt here.
    ///
    /// **Two passes, so nothing already on the device is ever downloaded** and the
    /// screen can say how many are not:
    ///  1. Every ref is asked for **without network access**. Whatever PhotoKit
    ///     holds locally resolves here, at the size the film draws it.
    ///  2. Only the refs PhotoKit reported as iCloud-only (`.inCloud`) are asked
    ///     for again **with** network access, one at a time — bounded memory,
    ///     honest `n / total`, and one stalled photo cannot hold the others.
    ///
    /// Only the photos the film draws reach this (`RecapComposer` has already
    /// applied the stop selection and per-stop allocation). The downloaded pixels
    /// are decoded straight into `cache`; nothing is written to disk and nothing
    /// goes back into the Photos library.
    ///
    /// **Cancellable.** `shouldContinue` is polled between photos and, while one
    /// is downloading, on a short timer that cancels the PhotoKit request. A
    /// photo that fails or exceeds `icloud_fetch_timeout_s` is counted as missing
    /// and the warm carries on — it never throws and never blocks the film.
    @discardableResult
    func warm(
        _ refs: [PhotoRef], targetPx: Int, timeoutS: Double,
        progress: (@Sendable (PreloadProgress) -> Void)? = nil,
        shouldContinue: @escaping @Sendable () -> Bool = { true }
    ) async -> WarmSummary {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else {
            return WarmSummary(requested: refs.count, resolved: 0, inCloud: 0)
        }
        let (resolved, pending) = await resolveLocally(refs, targetPx: targetPx, shouldContinue: shouldContinue)
        let downloaded = await download(
            pending, targetPx: targetPx, timeoutS: timeoutS, progress: progress, shouldContinue: shouldContinue
        )
        return WarmSummary(
            requested: refs.count, resolved: resolved + downloaded,
            inCloud: pending.count - downloaded, downloaded: downloaded
        )
    }

    /// Phase 1: everything PhotoKit holds locally, with network access **off**.
    /// Returns how many resolved and the iCloud-only assets left for phase 2.
    private func resolveLocally(
        _ refs: [PhotoRef], targetPx: Int, shouldContinue: @Sendable () -> Bool
    ) async -> (resolved: Int, pending: [(key: String, asset: PHAsset)]) {
        var resolved = 0
        var pending: [(key: String, asset: PHAsset)] = []
        let assets = Self.assets(for: refs)
        for ref in refs {
            guard shouldContinue() else { break }
            let key = Self.key(for: ref)
            switch await resolveLocally(ref, key: key, assets: assets, targetPx: targetPx) {
            case .resolved: resolved += 1
            case let .inCloud(asset): pending.append((key, asset))
            case .missing: break
            }
        }
        return (resolved, pending)
    }

    private enum LocalResult {
        case resolved
        case inCloud(PHAsset)
        case missing
    }

    private func resolveLocally(
        _ ref: PhotoRef, key: String, assets: [String: PHAsset], targetPx: Int
    ) async -> LocalResult {
        if lock.withLock({ cache[key] }) != nil { return .resolved }
        switch ref {
        case let .file(url):
            guard let image = loadFile(url) else { return .missing }
            store(image, key: key)
            return .resolved
        case let .asset(id):
            guard let asset = assets[id] else { return .missing } // deleted
            switch await PhotoKitImageLoader.image(
                for: asset, targetPx: targetPx, profile: .deck, allowNetwork: false
            ) {
            case let .loaded(image):
                guard let cgImage = image.cgImage else { return .missing }
                store(cgImage, key: key)
                return .resolved
            case .inCloud: return .inCloud(asset)
            case .failed, .cancelled: return .missing
            }
        }
    }

    /// Phase 2: the iCloud-only photos, sequentially. Returns how many arrived.
    private func download(
        _ pending: [(key: String, asset: PHAsset)], targetPx: Int, timeoutS: Double,
        progress: (@Sendable (PreloadProgress) -> Void)?, shouldContinue: @escaping @Sendable () -> Bool
    ) async -> Int {
        guard !pending.isEmpty, shouldContinue() else { return 0 }
        let total = pending.count
        var arrived = 0
        progress?(PreloadProgress(completed: 0, total: total, fraction: 0))
        for (index, item) in pending.enumerated() {
            guard shouldContinue() else { break }
            let outcome = await fetchFromICloud(
                item.asset, targetPx: targetPx, timeoutS: timeoutS, shouldContinue: shouldContinue
            ) { fraction in
                progress?(PreloadProgress(
                    completed: index, total: total, fraction: (Double(index) + fraction) / Double(total)
                ))
            }
            if case let .loaded(image) = outcome, let cgImage = image.cgImage {
                store(cgImage, key: item.key)
                arrived += 1
            }
            progress?(PreloadProgress(
                completed: index + 1, total: total, fraction: Double(index + 1) / Double(total)
            ))
        }
        return arrived
    }

    /// One photo's download, ended by whichever comes first: PhotoKit, the
    /// timeout, or the user. The request is a child task so that cancelling it is
    /// what cancels PhotoKit (`PhotoKitImageLoader`); the watcher only decides
    /// *when*.
    private func fetchFromICloud(
        _ asset: PHAsset, targetPx: Int, timeoutS: Double,
        shouldContinue: @escaping @Sendable () -> Bool, progress: @escaping @Sendable (Double) -> Void
    ) async -> PhotoFetch {
        let request = Task {
            await PhotoKitImageLoader.image(
                for: asset, targetPx: targetPx, profile: .deck, allowNetwork: true, progress: progress
            )
        }
        let watcher = Task {
            let deadline = ContinuousClock.now + .seconds(timeoutS)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if !shouldContinue() || ContinuousClock.now >= deadline {
                    request.cancel()
                    return
                }
            }
        }
        let outcome = await request.value
        watcher.cancel()
        return outcome
    }

    private func store(_ image: CGImage, key: String) {
        lock.withLock { cache[key] = image }
    }

    /// One fetch for every asset ref, instead of one per photo.
    private static func assets(for refs: [PhotoRef]) -> [String: PHAsset] {
        let ids = refs.compactMap { ref -> String? in
            if case let .asset(id) = ref { return id }
            return nil
        }
        guard !ids.isEmpty else { return [:] }
        var found: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            found[asset.localIdentifier] = asset
        }
        return found
    }

    func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
        lock.withLock { cache[Self.key(for: ref)] }
    }

    private static func key(for ref: PhotoRef) -> String {
        switch ref {
        case let .asset(id): return "asset:\(id)"
        case let .file(url): return "file:\(url.path)"
        }
    }

    private func loadFile(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

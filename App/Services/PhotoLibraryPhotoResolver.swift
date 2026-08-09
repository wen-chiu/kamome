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
        /// iCloud. Worth separating: only these are fixed by opening the photos
        /// in Photos and letting them download.
        let inCloud: Int

        var missing: Int { max(requested - resolved, 0) }
    }

    private let lock = NSLock()
    private var cache: [String: CGImage] = [:]

    /// Loads every ref's bitmap into the cache. Call once, off the render
    /// thread, before compositing. Needs library access — undetermined means no
    /// photos; never prompt here.
    ///
    /// **Downloads nothing** (`isNetworkAccessAllowed` stays false). Fetching
    /// iCloud originals here would be an unbounded, uncancellable stall behind a
    /// progress bar that reports *render* progress and has not started yet; doing
    /// it properly needs its own phase and copy, and is scoped separately. What
    /// this does instead is *report* the shortfall so the film's blank cards have
    /// a stated cause.
    @discardableResult
    func warm(_ refs: [PhotoRef], targetPx: Int) async -> WarmSummary {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else {
            return WarmSummary(requested: refs.count, resolved: 0, inCloud: 0)
        }
        var resolved = 0
        var inCloud = 0
        for ref in refs {
            let key = Self.key(for: ref)
            if lock.withLock({ cache[key] }) != nil { resolved += 1; continue }
            let outcome = await load(ref, targetPx: targetPx)
            if let image = outcome.image {
                lock.withLock { cache[key] = image }
                resolved += 1
            } else if outcome.isInCloud {
                inCloud += 1
            }
        }
        return WarmSummary(requested: refs.count, resolved: resolved, inCloud: inCloud)
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

    private func load(_ ref: PhotoRef, targetPx: Int) async -> (image: CGImage?, isInCloud: Bool) {
        switch ref {
        case let .asset(id): return await loadAsset(id: id, targetPx: targetPx)
        case let .file(url): return (loadFile(url), false)
        }
    }

    /// Decoded for the deck's enlarged peak; the compositor aspect-fills, so a
    /// generous square covers any crop.
    private func loadAsset(id: String, targetPx: Int) async -> (image: CGImage?, isInCloud: Bool) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return (nil, false) }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        let side = CGFloat(max(targetPx, 1))
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !resumed else { return }
                resumed = true
                // PhotoKit says outright when the only copy is in iCloud, which
                // is the difference between "download these" and "these are gone".
                let inCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
                continuation.resume(returning: (image?.cgImage, inCloud))
            }
        }
    }

    private func loadFile(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

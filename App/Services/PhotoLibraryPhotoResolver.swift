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
    private let lock = NSLock()
    private var cache: [String: CGImage] = [:]

    /// Loads every ref's bitmap into the cache. Call once, off the render
    /// thread, before compositing. Needs library access — undetermined means no
    /// photos; never prompt here.
    func warm(_ refs: [PhotoRef], targetPx: Int) async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .notDetermined else { return }
        for ref in refs {
            let key = Self.key(for: ref)
            if lock.withLock({ cache[key] }) != nil { continue }
            if let image = await load(ref, targetPx: targetPx) {
                lock.withLock { cache[key] = image }
            }
        }
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

    private func load(_ ref: PhotoRef, targetPx: Int) async -> CGImage? {
        switch ref {
        case let .asset(id): return await loadAsset(id: id, targetPx: targetPx)
        case let .file(url): return loadFile(url)
        }
    }

    /// Decoded for the deck's enlarged peak; the compositor aspect-fills, so a
    /// generous square covers any crop.
    private func loadAsset(id: String, targetPx: Int) async -> CGImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }
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
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    private func loadFile(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

import CoreGraphics
import Foundation
import Photos
import UIKit

/// How one PhotoKit image request ended. A value rather than `UIImage?` because
/// the callers need the *reason* an image is missing: "it is in iCloud and you
/// did not ask me to fetch it" is a queue for the download phase, "PhotoKit tried
/// and could not" is a shortfall, and neither is the same as the user cancelling.
enum PhotoFetch {
    case loaded(UIImage)
    /// The only copy is in iCloud and this request was not allowed to go and get
    /// it (`isNetworkAccessAllowed == false`). Never produced by a request that
    /// was allowed to download.
    case inCloud
    /// PhotoKit could not produce an image: no network, a failed iCloud download,
    /// an asset that is gone, an unreadable resource.
    case failed
    case cancelled
}

/// The one place Kamome asks PhotoKit for pixels — `requestImage`, never the
/// resource manager.
///
/// **Why `requestImage` and not `PHAssetResourceManager`.** The resource manager
/// hands back the *original* resource, written to a file: a full-resolution
/// download plus a copy on disk, for a card that is drawn at ~600 px. `requestImage`
/// with a `targetSize` lets Photos fetch and decode a derivative at that size, so
/// the download is smaller, the decode is smaller, and nothing is written to
/// Kamome's storage (`PHAsset` metadata scan → this → an in-memory `CGImage`).
///
/// Two profiles, because a thumbnail and a film card want opposite things:
///  - `.preview` — `.opportunistic` + `.fast`. The first image PhotoKit has is good
///    enough for a 36–160 pt tile, so the request is cancelled the moment it
///    arrives instead of letting a better version download for nothing.
///  - `.deck` — `.highQualityFormat` + `.exact`. One final image at the size the
///    film draws it, so the bitmap Kamome holds is bounded by `targetPx` rather
///    than by whatever the asset's original happens to be (`.none`, the default,
///    may return more than was asked for).
enum PhotoKitImageLoader {
    enum Profile {
        case preview
        case deck
    }

    /// Fetches one asset's image at roughly `targetPx` on its longest side.
    ///
    /// - Parameters:
    ///   - allowNetwork: `false` reads only what is on the device and reports
    ///     `.inCloud` for the rest; `true` lets PhotoKit download from iCloud.
    ///   - progress: iCloud download fraction 0…1, on an arbitrary queue.
    ///     Only called when the request actually downloads.
    ///
    /// **Cancellable**: cancelling the calling task cancels the PhotoKit request
    /// (`cancelImageRequest`), and this returns `.cancelled` at once even if
    /// Photos never calls back.
    static func image(
        for asset: PHAsset, targetPx: Int, profile: Profile,
        allowNetwork: Bool, progress: (@Sendable (Double) -> Void)? = nil
    ) async -> PhotoFetch {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        switch profile {
        case .preview:
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
        case .deck:
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
        }
        if allowNetwork, let progress {
            options.progressHandler = { fraction, _, _, _ in progress(fraction) }
        }
        let side = CGFloat(max(targetPx, 1))
        let pending = PendingRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard pending.install(continuation) else { return }
                let id = PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: side, height: side),
                    contentMode: .aspectFill, options: options
                ) { image, info in
                    pending.finish(
                        Self.outcome(image: image, info: info, allowNetwork: allowNetwork),
                        stopRequest: profile == .preview
                    )
                }
                pending.attach(id)
            }
        } onCancel: {
            pending.cancel()
        }
    }

    /// Maps one PhotoKit callback to an outcome. The first callback is the answer:
    /// `.highQualityFormat` delivers a single final image, and `.preview` wants
    /// the first one PhotoKit has.
    static func outcome(image: UIImage?, info: [AnyHashable: Any]?, allowNetwork: Bool) -> PhotoFetch {
        func flag(_ key: String) -> Bool { (info?[key] as? NSNumber)?.boolValue ?? false }
        if flag(PHImageCancelledKey) { return .cancelled }
        if let image { return .loaded(image) }
        // PhotoKit says outright when the only copy is in iCloud, which is the
        // difference between "download these" and "these are gone".
        if !allowNetwork, flag(PHImageResultIsInCloudKey) { return .inCloud }
        return .failed
    }
}

/// The half of a PhotoKit request that outlives the closure that made it: the
/// continuation to resume exactly once, and the request id to cancel. Locked,
/// because the result handler, the cancellation handler and the issuing thread
/// can all arrive here at once.
///
/// PhotoKit and the continuation are only ever touched **after** the lock is
/// released: `cancelImageRequest` may call the result handler back, which comes
/// straight into `finish`, and `NSLock` is not re-entrant.
final class PendingRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PhotoFetch, Never>?
    private var requestID: PHImageRequestID?
    private var isCancelled = false
    private var isFinished = false

    /// False when the task was cancelled before the request was made — the
    /// continuation has then been resumed and no request should be issued.
    func install(_ continuation: CheckedContinuation<PhotoFetch, Never>) -> Bool {
        let alreadyCancelled: Bool = lock.withLock {
            if !isCancelled { self.continuation = continuation }
            return isCancelled
        }
        if alreadyCancelled { continuation.resume(returning: .cancelled) }
        return !alreadyCancelled
    }

    func attach(_ id: PHImageRequestID) {
        let stopNow: Bool = lock.withLock {
            let stop = isCancelled || isFinished
            if !stop { requestID = id }
            return stop
        }
        if stopNow { PHImageManager.default().cancelImageRequest(id) }
    }

    func finish(_ outcome: PhotoFetch, stopRequest: Bool) {
        conclude(outcome, cancelRequest: stopRequest)
    }

    func cancel() {
        lock.withLock { isCancelled = true }
        conclude(.cancelled, cancelRequest: true)
    }

    private func conclude(_ outcome: PhotoFetch, cancelRequest: Bool) {
        let (continuation, id): (CheckedContinuation<PhotoFetch, Never>?, PHImageRequestID?) = lock.withLock {
            guard !isFinished else { return (nil, nil) }
            isFinished = true
            defer { self.continuation = nil }
            return (self.continuation, cancelRequest ? requestID : nil)
        }
        if let id { PHImageManager.default().cancelImageRequest(id) }
        continuation?.resume(returning: outcome)
    }
}

import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 step 2 orchestration: walks the camera path frame by frame, requests
/// one base-map snapshot per keyframe (`export.keyframe_interval_frames`),
/// and cross-fades between neighboring keyframes for the frames in between —
/// snapshotting all 900 frames would blow the < 90 s render budget.
///
/// Snapshots are prefetched a few keyframes ahead so network-bound
/// MKMapSnapshotter fetches overlap CPU-bound compositing (2026-07-19
/// benchmark: serial fetches alone cost ~40 s of the budget). Prefetch only
/// changes timing, never pixels — frames are still delivered strictly in
/// order, so encoders (AVAssetWriter, GIF) consume them as a stream.
public struct RecapRenderLoop {
    /// Keyframes requested ahead of the one being composited. Bounds both
    /// network concurrency and cache memory (~8 MB per 1080×1920 snapshot).
    private static let prefetchDepth = 4

    private let path: CameraPath
    private let compositor: RecapFrameCompositor
    private let provider: RecapSnapshotProviding
    private let config: TrackingConfig.Export

    public init(
        path: CameraPath,
        compositor: RecapFrameCompositor,
        provider: RecapSnapshotProviding,
        config: TrackingConfig.Export
    ) {
        self.path = path
        self.compositor = compositor
        self.provider = provider
        self.config = config
    }

    /// Renders every frame in order. `frame` is the frame index; the closure
    /// returns false to cancel the render (user backed out of S5).
    public func renderFrames(_ deliver: (Int, CGImage) throws -> Bool) async throws {
        let interval = max(config.keyframeIntervalFrames, 1)
        // The last frame blends toward this keyframe; never fetch past it.
        let lastKeyframe = (path.frameCount - 1) / interval + 1
        var fetches: [Int: Task<MapSnapshot, Error>] = [:]
        defer { fetches.values.forEach { $0.cancel() } }

        func fetch(_ keyframe: Int) -> Task<MapSnapshot, Error> {
            if let running = fetches[keyframe] { return running }
            let time = Double(keyframe * interval) / Double(config.fps)
            let position = path.position(atTime: min(time, path.durationS))
            let spanM = config.cameraSpanM
            let widthPx = config.frameWidthPx
            let heightPx = config.frameHeightPx
            let provider = self.provider
            let task = Task {
                try await provider.snapshot(
                    centerLat: position.lat,
                    centerLon: position.lon,
                    spanM: spanM,
                    widthPx: widthPx,
                    heightPx: heightPx
                )
            }
            fetches[keyframe] = task
            return task
        }

        for frame in 0..<path.frameCount {
            let keyframe = frame / interval
            for ahead in 2...(2 + Self.prefetchDepth) where keyframe + ahead <= lastKeyframe {
                _ = fetch(keyframe + ahead)
            }
            let previous = try await fetch(keyframe).value
            let next = try await fetch(keyframe + 1).value
            // Only the current window and prefetches ahead stay live.
            fetches = fetches.filter { $0.key >= keyframe }
            let blend = Double(frame % interval) / Double(interval)
            let background = RecapBackground(current: next, previous: previous, blend: blend)
            let image = try compositor.render(atTime: Double(frame) / Double(config.fps), background: background)
            if try !deliver(frame, image) { return }
        }
    }
}

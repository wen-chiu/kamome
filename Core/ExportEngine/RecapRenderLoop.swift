import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 step 2 orchestration: walks the camera path frame by frame, requests
/// one base-map snapshot per keyframe (`export.keyframe_interval_frames`),
/// and cross-fades between neighboring keyframes for the frames in between —
/// snapshotting all 900 frames would blow the < 90 s render budget.
///
/// Frames are delivered strictly in order; encoders (AVAssetWriter, GIF)
/// consume them as a stream and never need random access.
public struct RecapRenderLoop {
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
        var keyframeCache: [Int: MapSnapshot] = [:]

        func keyframeSnapshot(_ keyframe: Int) async throws -> MapSnapshot {
            if let cached = keyframeCache[keyframe] { return cached }
            let time = Double(keyframe * interval) / Double(config.fps)
            let position = path.position(atTime: min(time, path.durationS))
            let snapshot = try await provider.snapshot(
                centerLat: position.lat,
                centerLon: position.lon,
                spanM: config.cameraSpanM,
                widthPx: config.frameWidthPx,
                heightPx: config.frameHeightPx
            )
            // Only the two keyframes bracketing the current frame are live.
            keyframeCache = keyframeCache.filter { $0.key >= keyframe - 1 }
            keyframeCache[keyframe] = snapshot
            return snapshot
        }

        for frame in 0..<path.frameCount {
            let keyframe = frame / interval
            let previous = try await keyframeSnapshot(keyframe)
            let next = try await keyframeSnapshot(keyframe + 1)
            let blend = Double(frame % interval) / Double(interval)
            let background = RecapBackground(current: next, previous: previous, blend: blend)
            let image = try compositor.render(atTime: Double(frame) / Double(config.fps), background: background)
            if try !deliver(frame, image) { return }
        }
    }
}

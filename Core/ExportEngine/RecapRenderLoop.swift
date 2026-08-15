import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 step 2 orchestration: walks the timeline frame by frame, requests
/// base-map snapshots, and cross-fades between neighboring keyframes for the
/// frames in between — snapshotting all 900 frames would blow the < 90 s render
/// budget.
///
/// Snapshots are taken at the timeline's `cameraFrame`, so the base map is
/// always framed exactly as the film is. Prefetched a few keyframes ahead so
/// network-bound snapshot fetches overlap CPU-bound compositing (2026-07-19
/// benchmark: serial fetches alone cost ~40 s of the budget). Prefetch only
/// changes timing, never pixels — frames are delivered strictly in order, so
/// encoders consume them as a stream.
///
/// **Snapshots are cached by camera value, not by keyframe index** (Fable
/// review 2026-07-26). Since the camera went static (Chiu 2026-07-25) it holds
/// one fixed frame per act, so on a single-act trip — the common case — every
/// keyframe asks for the *same* view. Keying the cache by index re-fetched that
/// identical snapshot ~60 times per film; keying it by `CameraFrame` fetches it
/// once. The cross-fade is untouched at act boundaries, where the frames really
/// do differ; within an act the two keyframes now resolve to one snapshot and
/// the redundant full-frame alpha blend is skipped rather than composited over
/// itself.
public struct RecapRenderLoop {
    /// Keyframes requested ahead of the one being composited. Bounds both
    /// network concurrency and cache memory (~8 MB per 1080×1920 snapshot).
    private static let prefetchDepth = 4

    /// What a snapshot is a function of. Two keyframes with equal keys are the
    /// same picture, so they share one fetch.
    private struct SnapshotKey: Hashable {
        let camera: CameraFrame
        let map: MapState
    }

    private let timeline: LinearTimeline
    private let compositor: FrameCompositor
    private let provider: MapRenderer
    private let config: TrackingConfig.Export

    public init(
        timeline: LinearTimeline,
        compositor: FrameCompositor,
        provider: MapRenderer,
        config: TrackingConfig.Export
    ) {
        self.timeline = timeline
        self.compositor = compositor
        self.provider = provider
        self.config = config
    }

    /// Renders every frame in order. `frame` is the frame index; the closure
    /// returns false to cancel the render (user backed out of S5).
    public func renderFrames(_ deliver: (Int, CGImage) throws -> Bool) async throws {
        // `keyframe_interval_frames` (15 → two map updates a second) is sized for
        // a **static** camera, where consecutive keyframes are identical and the
        // value cache makes them free. The opening prologue is the one stretch
        // where the camera actually moves, and at that interval the map steps
        // twice a second while the overlays run at 30 — which is exactly what
        // read as a janky zoom. Snapshot every frame there and nowhere else.
        let interval = max(config.keyframeIntervalFrames, 1)
        let movingUntilFrame = Int((timeline.openingS * Double(config.fps)).rounded())
        // The last frame blends toward this keyframe; never fetch past it. Uses
        // the coarse interval because the fine one only applies to the opening.
        let lastKeyframe = (timeline.frameCount - 1) / interval + 1
        var fetches: [SnapshotKey: Task<MapSnapshot, Error>] = [:]
        defer { fetches.values.forEach { $0.cancel() } }

        /// What the camera and map are doing at a keyframe — pure, so it is
        /// cheap to ask repeatedly.
        func key(_ keyframe: Int, interval: Int) -> SnapshotKey {
            let time = min(Double(keyframe * interval) / Double(config.fps), timeline.durationS)
            return SnapshotKey(camera: timeline.cameraFrame(atTime: time), map: timeline.mapState(atTime: time))
        }

        func fetch(_ key: SnapshotKey) -> Task<MapSnapshot, Error> {
            if let running = fetches[key] { return running }
            let widthPx = config.frameWidthPx
            let heightPx = config.frameHeightPx
            let provider = self.provider
            let task = Task {
                try await provider.snapshot(key.camera, map: key.map, widthPx: widthPx, heightPx: heightPx)
            }
            fetches[key] = task
            return task
        }

        var currentKeyframe = -1
        for frame in 0..<timeline.frameCount {
            let interval = frame < movingUntilFrame ? 1 : interval
            let keyframe = frame / interval
            let previousKey = key(keyframe, interval: interval)
            let nextKey = key(keyframe + 1, interval: interval)

            if keyframe != currentKeyframe || interval == 1 {
                currentKeyframe = keyframe
                // Evict anything outside the live window — with value keys the
                // window has to be named explicitly rather than compared by index.
                var live: Set<SnapshotKey> = [previousKey, nextKey]
                for ahead in 2...(2 + Self.prefetchDepth) where keyframe + ahead <= lastKeyframe {
                    let ahead = key(keyframe + ahead, interval: interval)
                    live.insert(ahead)
                    _ = fetch(ahead)
                }
                fetches = fetches.filter { live.contains($0.key) }
            }

            let previous = try await fetch(previousKey).value
            let background: RecapBackground
            if previousKey == nextKey {
                // Same view either side: compositing the picture over itself at
                // a partial alpha is a wasted full-frame blend per frame.
                background = RecapBackground(current: previous)
            } else {
                let next = try await fetch(nextKey).value
                let blend = Double(frame % interval) / Double(interval)
                background = RecapBackground(current: next, previous: previous, blend: blend)
            }
            let image = try compositor.render(atTime: Double(frame) / Double(config.fps), background: background)
            if try !deliver(frame, image) { return }
        }
    }
}

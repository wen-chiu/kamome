import CoreGraphics
import Foundation
import KamomeConfig

/// §4.5 step 2 orchestration: walks the timeline frame by frame and paints each
/// one over a base map produced by **reprojecting one station snapshot**
/// (`Docs/camera-arcs.md` §7).
///
/// ## What this used to do, and why it stopped
///
/// It snapshotted every `keyframe_interval_frames` and filled the frames in
/// between by alpha-blending the two neighbouring snapshots. While the camera
/// moves those two are the same map at two different geographic positions, so
/// every coastline and label was drawn twice, offset — Chiu's P0, 殘影 for the
/// double image and 晃動 for it stepping forward twice a second (`HANDOFF.md`
/// 2026-08-30 finding 1, confirmed end to end by a rendered falsification pair).
///
/// The workaround was to snapshot *every* frame wherever the camera moves — the
/// opening, then crossing arcs too. That is why 91% of a crossing film's 367
/// snapshots were camera movement, and why an export cost 4.4–9.5 minutes on
/// device for a 69-second film.
///
/// **Both were one mechanism, and reprojection ends both.** Between two cameras
/// the correct operation is not a blend; it is a translate and a scale. The
/// result is geometrically exact, so there is nothing to fine-sample against,
/// and one snapshot serves as many frames as its magnification budget allows.
/// `RecapSnapshotStations` decides where those stations fall.
///
/// **Cost stops depending on how long a move takes and depends only on how far
/// it zooms** (`Docs/camera-arcs.md` §7 consequence 1). A held frame is still
/// free — a parked camera magnifies by 1.0 and its station never expires — so
/// the value-cache property that made stop beats cost one snapshot survives as
/// a special case of the general rule rather than as its own mechanism.
///
/// Stations are prefetched a few ahead so provider-bound fetches overlap
/// CPU-bound compositing; prefetch only changes timing, never pixels, and frames
/// are delivered strictly in order so encoders consume them as a stream.
public struct RecapRenderLoop {
    /// Stations requested ahead of the one being composited. Bounds both
    /// provider concurrency and cache memory (~8 MB per 1080×1920 snapshot).
    private static let prefetchDepth = 4

    /// What a snapshot is a function of. Two stations with equal keys are the
    /// same picture, so they share one fetch — a trip that returns to a framing
    /// it has already held pays for it once.
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

    /// The stations this film will render from — pure, so a caller can price an
    /// export without taking a single snapshot. `RecapSnapshotBudgetTests` reads
    /// it, and so does anything that wants the number before paying it.
    public var stations: [RecapSnapshotStations.Station] {
        let timeline = self.timeline
        let camera = { (time: Double) in timeline.cameraFrame(atTime: time) }
        return RecapSnapshotStations.plan(
            frameCount: timeline.frameCount, fps: config.fps,
            camera: camera,
            map: { timeline.mapState(atTime: $0) },
            // A stop beat gets its own station, so the frames the viewer is asked
            // to look at longest are the ones reprojected least.
            mustStartAt: RecapSnapshotStations.splitFrames(
                holds: timeline.holds, frameCount: timeline.frameCount,
                fps: config.fps, camera: camera
            ),
            config: config
        )
    }

    /// Renders every frame in order. `frame` is the frame index; the closure
    /// returns false to cancel the render (user backed out of S5).
    public func renderFrames(_ deliver: (Int, CGImage) throws -> Bool) async throws {
        let plan = stations
        guard !plan.isEmpty else { return }
        var fetches: [SnapshotKey: Task<MapSnapshot, Error>] = [:]
        defer { fetches.values.forEach { $0.cancel() } }

        func key(_ station: RecapSnapshotStations.Station) -> SnapshotKey {
            SnapshotKey(camera: station.camera, map: station.map)
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

        for (index, station) in plan.enumerated() {
            // Evict anything outside the live window. Named explicitly rather
            // than compared by index, because the keys are values and two distant
            // stations may legitimately be the same picture.
            var live: Set<SnapshotKey> = [key(station)]
            for ahead in 1...Self.prefetchDepth where index + ahead < plan.count {
                let next = key(plan[index + ahead])
                live.insert(next)
                _ = fetch(next)
            }
            fetches = fetches.filter { live.contains($0.key) }

            let snapshot = try await fetch(key(station)).value
            for frame in station.frames {
                let time = Double(frame) / Double(config.fps)
                // Throws rather than drawing a frame with an edge of nothing. A
                // station that does not contain its own frame is a planner bug,
                // and the one thing that must never happen quietly is a film that
                // renders anyway (`Arch.md` §6).
                let reprojection = try SnapshotReprojection(
                    station: snapshot, stationCamera: station.camera,
                    target: timeline.cameraFrame(atTime: time),
                    widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
                )
                let image = try compositor.render(
                    atTime: time,
                    background: RecapBackground(station: snapshot, reprojection: reprojection)
                )
                if try !deliver(frame, image) { return }
            }
        }
    }
}

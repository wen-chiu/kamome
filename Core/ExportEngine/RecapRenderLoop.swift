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
    /// provider concurrency and cache memory (~8 MB per 1080×1920 snapshot,
    /// so 8 deep is a further ~64 MB peak over depth 4 — named, not measured
    /// on device). Raised from 4 (`Docs/handoff-export-performance.md` §4):
    /// whether this buys anything depends on whether `MLNMapSnapshotter`
    /// actually renders more than one snapshot at a time, which is exactly
    /// what the `wait` vs `snapshots` reading in the "render cost" log line
    /// settles — read it against this value, not assumed from it.
    private static let prefetchDepth = 8

    /// Frames within one station composited at once. A station is one
    /// snapshot reprojected onto a run of frames (`Docs/camera-arcs.md` §7),
    /// and reprojection is a pure function of each frame's own camera — two
    /// frames of the same station never read or write anything the other
    /// touches — so compositing them is embarrassingly parallel. Bounded for
    /// the same reason `prefetchDepth` is: each in-flight frame is a fresh
    /// ~8 MB RGBA bitmap, so this number times ~8 MB is the peak this stage
    /// adds on top of the station snapshot(s) already live.
    public static let compositeConcurrency = 4

    /// What a snapshot is a function of. Two stations with equal keys are the
    /// same picture, so they share one fetch — a trip that returns to a framing
    /// it has already held pays for it once.
    private struct SnapshotKey: Hashable {
        let camera: CameraFrame
        let map: MapState
    }

    /// **Where an export's minutes actually went** — measured, not modelled.
    ///
    /// The export is snapshot-bound, but "how bound" was never a number anyone
    /// held: the log said how many frames a film has and the budget harness says
    /// how many stations it plans, and nothing said how long either cost on the
    /// device that paid for it. A 31-minute export is 300 snapshots at 6 s or 900
    /// at 2 s, and those are opposite problems with opposite fixes.
    ///
    /// Durations only — no coordinate, no place, no camera ever reaches a log
    /// line from here (`CLAUDE.md` §0).
    public struct RenderStats: Sendable {
        /// Stations the plan asked for.
        public var stations = 0
        /// Snapshots actually requested. Fewer than `stations` when two stations
        /// are the same picture and share one fetch.
        public var fetches = 0
        public var frames = 0
        /// Wall time **summed over the fetches**, each measured around the
        /// provider call. Prefetch overlaps them, so this exceeds the render's
        /// own duration — it is the substrate's bill, not the loop's stall.
        public var snapshotS = 0.0
        /// Wall time the loop was **blocked** waiting for the station it needed.
        /// `snapshotS - waitS` is what prefetching hid; a `waitS` near the render
        /// duration means the loop is starved and more concurrency would pay.
        public var waitS = 0.0
        public var compositeS = 0.0
        /// Whatever the caller does with each frame — encoding, for the exporter.
        public var deliverS = 0.0

        public var meanSnapshotS: Double { fetches > 0 ? snapshotS / Double(fetches) : 0 }

        public init() {}
    }

    /// Fetches run concurrently, so their meter is shared mutable state.
    private final class SnapshotMeter: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var fetches = 0
        private(set) var totalS = 0.0

        func record(_ seconds: Double) {
            lock.lock()
            defer { lock.unlock() }
            fetches += 1
            totalS += seconds
        }
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
    ///
    /// Returns what the pass cost, stage by stage (`RenderStats`). A cancelled
    /// render returns what it had spent up to that frame — an abandoned export is
    /// still a measurement of the stage that was slow.
    @discardableResult
    public func renderFrames(_ deliver: (Int, CGImage) throws -> Bool) async throws -> RenderStats {
        let plan = stations
        var stats = RenderStats()
        stats.stations = plan.count
        guard !plan.isEmpty else { return stats }
        let meter = SnapshotMeter()
        // Folded in at every exit rather than in a `defer`: a deferred write
        // lands *after* the return value is copied, so the cancelled path would
        // have reported zero snapshots — the one case where the measurement
        // matters most.
        func measured() -> RenderStats {
            var out = stats
            out.fetches = meter.fetches
            out.snapshotS = meter.totalS
            return out
        }
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
                let started = ContinuousClock.now
                defer { meter.record(Self.seconds(since: started)) }
                return try await provider.snapshot(
                    key.camera, map: key.map, widthPx: widthPx, heightPx: heightPx
                )
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

            let blocked = ContinuousClock.now
            let snapshot = try await fetch(key(station)).value
            stats.waitS += Self.seconds(since: blocked)
            guard try await renderStation(station, snapshot: snapshot, stats: &stats, deliver: deliver) else {
                return measured()
            }
        }
        return measured()
    }

    /// Every frame one station serves, composited on a bounded worker pool and
    /// **delivered to `deliver` strictly in order** regardless of which frame's
    /// composite finishes first — the encoder is the one thing here that is not
    /// safe to hand frames to out of order. Split out of `renderFrames` only so
    /// each stays readable; returns false when the caller cancelled.
    ///
    /// Safe to parallelise because a station's frames share nothing mutable:
    /// `SnapshotReprojection` is a value computed fresh per frame,
    /// `compositor.render` allocates its own `CGContext` per call (verified by
    /// reading `FrameCompositor` — no stored `var`, and `VehicleSubjectRenderer`
    /// / `RecapOverlayRenderer` carry none either), and the one place two frames
    /// of the same station *do* share state — `MapSnapshot`'s per-station
    /// projection cache — is lock-guarded and, on a miss, serialises the
    /// underlying call rather than risk two threads inside MapLibre's
    /// Objective-C++ bridge at once (`RecapSnapshot.swift`).
    private func renderStation(
        _ station: RecapSnapshotStations.Station, snapshot: MapSnapshot,
        stats: inout RenderStats, deliver: (Int, CGImage) throws -> Bool
    ) async throws -> Bool {
        // `station.frames` is a `Range<Int>` of frame *numbers*, not a
        // zero-based sequence — its own subscript takes a number back, not a
        // position. Everything below indexes by position (submission order,
        // delivery order), so it needs the array, not the range.
        let frames = Array(station.frames)
        guard !frames.isEmpty else { return true }
        let stationCamera = station.camera
        let credit = provider.capabilities.attribution

        return try await withThrowingTaskGroup(of: CompositedFrame.self) { group in
            var nextToSubmit = 0
            func submitOne() {
                guard nextToSubmit < frames.count else { return }
                let frame = frames[nextToSubmit]
                nextToSubmit += 1
                group.addTask {
                    try self.composite(frame: frame, snapshot: snapshot, stationCamera: stationCamera, credit: credit)
                }
            }
            for _ in 0..<min(Self.compositeConcurrency, frames.count) { submitOne() }

            var pending: [Int: CompositedFrame] = [:]
            var nextToDeliver = 0
            var carryOn = true
            while carryOn, nextToDeliver < frames.count {
                guard let done = try await group.next() else { break }
                pending[done.frame] = done
                submitOne()
                while carryOn, nextToDeliver < frames.count,
                      let ready = pending.removeValue(forKey: frames[nextToDeliver]) {
                    stats.compositeS += ready.composeS
                    let delivered = ContinuousClock.now
                    carryOn = try deliver(frames[nextToDeliver], ready.image)
                    stats.deliverS += Self.seconds(since: delivered)
                    stats.frames += 1
                    nextToDeliver += 1
                }
            }
            if !carryOn { group.cancelAll() }
            return carryOn
        }
    }

    /// One composited frame, on its way back from a worker task to the
    /// ordered delivery loop.
    private struct CompositedFrame: Sendable {
        let frame: Int
        let image: CGImage
        let composeS: Double
    }

    /// One frame's work, pulled out of `renderStation` only to keep its body
    /// short — reads `self` for its `let` properties alone (`config`,
    /// `timeline`, `compositor`), so more than one frame can call it at once.
    private func composite(
        frame: Int, snapshot: MapSnapshot, stationCamera: CameraFrame, credit: String?
    ) throws -> CompositedFrame {
        let time = Double(frame) / Double(config.fps)
        // Throws rather than drawing a frame with an edge of nothing. A
        // station that does not contain its own frame is a planner bug, and
        // the one thing that must never happen quietly is a film that
        // renders anyway (`Arch.md` §6).
        let reprojection = try SnapshotReprojection(
            station: snapshot, stationCamera: stationCamera,
            target: timeline.cameraFrame(atTime: time),
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let composeStarted = ContinuousClock.now
        // **Asked of the provider, here, rather than wired in by the app**
        // (ADR 2026-09-12 (b)): this loop is the one object that both holds
        // the substrate that drew the picture and hands it to the
        // compositor, so a film cannot be composited from tiles whose
        // credit somebody forgot to pass down.
        let image = try compositor.render(
            atTime: time,
            background: RecapBackground(station: snapshot, reprojection: reprojection),
            credit: credit
        )
        return CompositedFrame(frame: frame, image: image, composeS: Self.seconds(since: composeStarted))
    }

    private static func seconds(since instant: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - instant
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }
}

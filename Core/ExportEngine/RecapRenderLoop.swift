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

    /// Frames composited at once, across station boundaries. Reprojection is a
    /// pure function of each frame's own camera (`Docs/camera-arcs.md` §7) — two
    /// frames never read or write anything the other touches — so compositing
    /// them is embarrassingly parallel. Bounded for
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

    /// The live window of station snapshots: prefetches ahead of the station
    /// being submitted from, evicts everything outside that window, and shares
    /// one fetch between stations that are the same picture. Frames already
    /// submitted hold their station's snapshot themselves, so evicting a key
    /// never pulls a picture out from under a frame in flight.
    private final class StationFetcher {
        let meter = SnapshotMeter()
        private let stations: [RecapSnapshotStations.Station]
        private let provider: MapRenderer
        private let widthPx: Int
        private let heightPx: Int
        private var fetches: [SnapshotKey: Task<MapSnapshot, Error>] = [:]

        init(stations: [RecapSnapshotStations.Station], provider: MapRenderer, widthPx: Int, heightPx: Int) {
            self.stations = stations
            self.provider = provider
            self.widthPx = widthPx
            self.heightPx = heightPx
        }

        /// Makes station `index` the one being submitted from and waits for its
        /// snapshot; `waitS` is how long the loop was blocked on it.
        func enter(_ index: Int, prefetchDepth: Int) async throws -> (snapshot: MapSnapshot, waitS: Double) {
            // Evict anything outside the live window. Named explicitly rather
            // than compared by index, because the keys are values and two distant
            // stations may legitimately be the same picture.
            var live: Set<SnapshotKey> = [key(stations[index])]
            for ahead in 1...prefetchDepth where index + ahead < stations.count {
                let next = key(stations[index + ahead])
                live.insert(next)
                _ = fetch(next)
            }
            fetches = fetches.filter { live.contains($0.key) }

            let blocked = ContinuousClock.now
            let snapshot = try await fetch(key(stations[index])).value
            return (snapshot, RecapRenderLoop.seconds(since: blocked))
        }

        func cancelAll() {
            fetches.values.forEach { $0.cancel() }
        }

        private func key(_ station: RecapSnapshotStations.Station) -> SnapshotKey {
            SnapshotKey(camera: station.camera, map: station.map)
        }

        private func fetch(_ key: SnapshotKey) -> Task<MapSnapshot, Error> {
            if let running = fetches[key] { return running }
            let (provider, meter, widthPx, heightPx) = (provider, meter, widthPx, heightPx)
            let task = Task {
                let started = ContinuousClock.now
                defer { meter.record(RecapRenderLoop.seconds(since: started)) }
                return try await provider.snapshot(
                    key.camera, map: key.map, widthPx: widthPx, heightPx: heightPx
                )
            }
            fetches[key] = task
            return task
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
    /// `only` names the frames the caller will actually use; every other frame
    /// is neither composited nor delivered, and a station none of whose frames
    /// is wanted is never fetched. **The plan itself does not change** — it is
    /// still made over every frame — so each frame that *is* rendered comes from
    /// exactly the station, and therefore exactly the pixels, it would have in a
    /// full render. A GIF export is the caller: it keeps one frame in
    /// `fps / gif_fps` and used to composite all of them.
    ///
    /// Returns what the pass cost, stage by stage (`RenderStats`). A cancelled
    /// render returns what it had spent up to that frame — an abandoned export is
    /// still a measurement of the stage that was slow.
    ///
    /// **One worker pool for the whole film, not one per station.** Frames are
    /// submitted in film order across station boundaries, so while the loop waits
    /// on the next station's snapshot the previous station's last frames are
    /// still compositing, and a crossing arc — about two frames per station
    /// (`Docs/handoff-export-performance.md` §2) — keeps every worker busy
    /// instead of draining the pool at each boundary. Delivery stays strictly in
    /// film order: the encoder is the one thing here that is not safe to hand
    /// frames to out of order.
    ///
    /// Safe to parallelise because frames share nothing mutable:
    /// `SnapshotReprojection` is a value computed fresh per frame,
    /// `compositor.render` allocates its own `CGContext` per call (verified by
    /// reading `FrameCompositor` — no stored `var`, and `VehicleSubjectRenderer`
    /// / `RecapOverlayRenderer` carry none either), and the one place two frames
    /// of the same station *do* share state — `MapSnapshot`'s per-station
    /// projection cache — is lock-guarded and, on a miss, serialises the
    /// underlying call rather than risk two threads inside MapLibre's
    /// Objective-C++ bridge at once (`RecapSnapshot.swift`).
    @discardableResult
    public func renderFrames(
        only wanted: (Int) -> Bool = { _ in true },
        _ deliver: (Int, CGImage) throws -> Bool
    ) async throws -> RenderStats {
        let fullPlan = stations
        var stats = RenderStats()
        stats.stations = fullPlan.count
        // Each station paired with the frames of it that will be drawn; a
        // station left with none is dropped here, before anything fetches it.
        let plan: [PlannedStation] = fullPlan.compactMap { station in
            let frames = station.frames.filter(wanted)
            return frames.isEmpty ? nil : PlannedStation(station: station, frames: frames)
        }
        guard !plan.isEmpty else { return stats }
        let fetcher = StationFetcher(
            stations: plan.map(\.station), provider: provider,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        defer { fetcher.cancelAll() }
        try await composite(plan, fetcher: fetcher, stats: &stats, deliver: deliver)
        // Read after `composite` returns, cancelled or not, rather than in a
        // `defer`: a deferred write lands *after* the return value is copied, so
        // the cancelled path would have reported zero snapshots — the one case
        // where the measurement matters most.
        stats.fetches = fetcher.meter.fetches
        stats.snapshotS = fetcher.meter.totalS
        return stats
    }

    /// One station and the frames of it this render will draw.
    private struct PlannedStation {
        let station: RecapSnapshotStations.Station
        let frames: [Int]
    }

    /// The pool itself: submission walks (station, frame-within-station) and
    /// delivery walks the same order behind it. The only await on the
    /// submission side is a station's snapshot, and the frames already in the
    /// group keep compositing through it.
    private func composite(
        _ plan: [PlannedStation], fetcher: StationFetcher,
        stats: inout RenderStats, deliver: (Int, CGImage) throws -> Bool
    ) async throws {
        let credit = provider.capabilities.attribution
        try await withThrowingTaskGroup(of: CompositedFrame.self) { group in
            var stationIndex = -1, frameIndex = 0, inFlight = 0, nextToDeliver = 0
            var snapshot: MapSnapshot?
            var order: [Int] = []
            var pending: [Int: CompositedFrame] = [:]
            var carryOn = true
            while carryOn {
                while inFlight < Self.compositeConcurrency, stationIndex < plan.count {
                    if stationIndex < 0 || frameIndex >= plan[stationIndex].frames.count {
                        stationIndex += 1
                        frameIndex = 0
                        guard stationIndex < plan.count else { break }
                        let entered = try await fetcher.enter(stationIndex, prefetchDepth: Self.prefetchDepth)
                        snapshot = entered.snapshot
                        stats.waitS += entered.waitS
                    }
                    guard let snapshot else { break }
                    let frame = plan[stationIndex].frames[frameIndex]
                    let stationCamera = plan[stationIndex].station.camera
                    frameIndex += 1
                    order.append(frame)
                    inFlight += 1
                    group.addTask {
                        try self.composite(frame: frame, snapshot: snapshot, stationCamera: stationCamera, credit: credit)
                    }
                }
                guard let done = try await group.next() else { break }
                inFlight -= 1
                pending[done.frame] = done
                while carryOn, nextToDeliver < order.count,
                      let ready = pending.removeValue(forKey: order[nextToDeliver]) {
                    stats.compositeS += ready.composeS
                    let started = ContinuousClock.now
                    carryOn = try deliver(ready.frame, ready.image)
                    stats.deliverS += Self.seconds(since: started)
                    stats.frames += 1
                    nextToDeliver += 1
                }
            }
            if !carryOn { group.cancelAll() }
        }
    }

    /// One composited frame, on its way back from a worker task to the
    /// ordered delivery loop.
    private struct CompositedFrame: Sendable {
        let frame: Int
        let image: CGImage
        let composeS: Double
    }

    /// One frame's work, pulled out of `renderFrames` only to keep its body
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

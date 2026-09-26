import Foundation

extension TrackingConfig {
    /// **How hard the export pushes the phone**, not how the film looks
    /// (arch review 2026-09-24, P1-9 and P1-10).
    ///
    /// Two of these were constants in `RecapRenderLoop` and the third did not
    /// exist. They are the levers D2 (memory) and D3 (seconds per snapshot) are
    /// meant to price on a device, which is exactly why they belong here rather
    /// than in code (`CLAUDE.md` rule 7). None changes a pixel: prefetch and
    /// compositing only change timing, and frames are delivered in order.
    public struct ExportPipeline: Decodable, Equatable {
        /// Stations requested ahead of the one being composited. Bounds provider
        /// concurrency and cache memory: ~8 MB per 1080×1920 snapshot, so 8 deep
        /// is ~64 MB — named, **not measured on a device** (INFERRED).
        public let prefetchDepth: Int
        /// Frames composited at once. Each in flight is a fresh ~8 MB bitmap, so
        /// this times 8 MB is what compositing adds to peak memory (INFERRED).
        public let compositeConcurrency: Int
        /// The longest one map snapshot may take before the export fails instead
        /// of waiting. Without it a snapshot that never completes held the
        /// render — and Cancel, which is read between frames — indefinitely.
        /// 60 s is ~40× the 0.72–1.55 s measured per snapshot on the simulator
        /// (`Docs/handoff-export-performance.md`); INFERRED, device figure owed.
        public let snapshotTimeoutS: Double
        /// The on-device tile cache the map renderer may keep, in MB (2026-09-25).
        /// MapLibre's default is 50 MB (VERIFIED, `MLNOfflineStorage.h`), and a
        /// film that covers a whole island at several zooms, with a terrain DEM
        /// under it, may need more than that. If it does, tiles are evicted and
        /// downloaded again partway through the export. 256 is INFERRED, not
        /// measured: the `render substrate` log line counts tile requests
        /// against distinct tiles, and a gap between the two is the reading that
        /// says whether this is big enough. Timing only; no pixel changes.
        public let mapCacheMb: Int

        public init(prefetchDepth: Int, compositeConcurrency: Int, snapshotTimeoutS: Double, mapCacheMb: Int) {
            self.prefetchDepth = prefetchDepth
            self.compositeConcurrency = compositeConcurrency
            self.snapshotTimeoutS = snapshotTimeoutS
            self.mapCacheMb = mapCacheMb
        }

        /// For hand-built test configs only, like `targetZoomRatio`'s default:
        /// the JSON block is still required, so a config file missing it fails
        /// loudly. Mirrors the shipped values.
        public static let handBuilt = ExportPipeline(
            prefetchDepth: 8, compositeConcurrency: 4, snapshotTimeoutS: 60, mapCacheMb: 256
        )

        enum CodingKeys: String, CodingKey {
            case prefetchDepth = "prefetch_depth"
            case compositeConcurrency = "composite_concurrency"
            case snapshotTimeoutS = "snapshot_timeout_s"
            case mapCacheMb = "map_cache_mb"
        }
    }
}

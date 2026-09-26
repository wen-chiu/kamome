import Foundation

/// **What one export asked of the map renderer**, counted from inside it
/// (2026-09-25, the 859 s Iceland film).
///
/// `render cost` says how long snapshots took; it cannot say *why*. A MapLibre
/// snapshot rebuilds its renderer and re-parses the style every time
/// (`Docs/handoff-export-performance.md` §7), and it may download a tile it
/// already downloaded once if the ambient cache evicted it. Those are two
/// different fixes, and this meter holds the readings that pick between them:
///
/// - **style vs snapshot seconds.** Time from start to `didFinishLoadingStyle`
///   is setup that a persistent renderer would pay once. It is a lower bound
///   on setup: the decoding of tiles into the new renderer comes after it.
/// - **requests vs distinct.** Every network request MapLibre makes, against the
///   distinct URLs among them. A cache hit makes no request, so a repeat means
///   the tile went back to the network. A repeat carrying `If-None-Match` or
///   `If-Modified-Since` is a **revalidation** of an expired tile the cache
///   still holds; a repeat without one is a **refetch**, a tile downloaded
///   twice because the cache no longer had it.
///   (MapLibre 6.27 never calls `didReceiveResponse:` — VERIFIED 2026-09-26,
///   `MapSubstrateMeterTests` — so status codes and bytes are not measurable
///   here; the request side is.)
/// - **peak in flight.** How many snapshotters were running at once, which says
///   whether `prefetch_depth` buys concurrency at all.
///
/// 🔴 **§0.** URLs name tiles, and z/x/y is a place. They are hashed in memory
/// only to count distinct ones, the set is dropped with the reading, and
/// nothing but counts and durations ever leaves this type.
///
/// Process-wide, because MapLibre's network hook is. One export runs at a time
/// (`RecapExportCoordinator`), so `reset()` at export start scopes it.
final class MapSubstrateMeter: @unchecked Sendable {
    struct Reading: Equatable {
        var snapshots = 0
        var failedSnapshots = 0
        /// Successful snapshots whose style-loaded callback arrived. Kept apart
        /// from `snapshots` so a callback that never fires reads as "unknown"
        /// rather than as zero setup.
        var styled = 0
        var styleS = 0.0
        var snapshotS = 0.0
        var peakInFlight = 0
        var requests = 0
        var distinctRequests = 0
        var revalidations = 0
        var refetches = 0

        var meanStyleS: Double? { styled > 0 ? styleS / Double(styled) : nil }
        var meanSnapshotS: Double { snapshots > 0 ? snapshotS / Double(snapshots) : 0 }
    }

    private let lock = NSLock()
    private var reading = Reading()
    private var inFlight = 0
    private var seen = Set<Int>()

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        reading = Reading()
        inFlight = 0
        seen = []
    }

    func read() -> Reading {
        lock.lock()
        defer { lock.unlock() }
        return reading
    }

    func snapshotStarted() {
        lock.lock()
        defer { lock.unlock() }
        inFlight += 1
        reading.peakInFlight = max(reading.peakInFlight, inFlight)
    }

    /// `styleS` is nil when the style never finished loading (the snapshot
    /// failed before it did), so a failure does not count as zero setup.
    func snapshotFinished(totalS: Double, styleS: Double?, succeeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        inFlight = max(0, inFlight - 1)
        guard succeeded else {
            reading.failedSnapshots += 1
            return
        }
        reading.snapshots += 1
        reading.snapshotS += totalS
        if let styleS {
            reading.styled += 1
            reading.styleS += styleS
        }
    }

    func requestSent(url: URL?, conditional: Bool) {
        lock.lock()
        defer { lock.unlock() }
        reading.requests += 1
        guard let url else { return }
        if seen.insert(url.absoluteString.hashValue).inserted {
            reading.distinctRequests += 1
        } else if conditional {
            reading.revalidations += 1
        } else {
            reading.refetches += 1
        }
    }
}
